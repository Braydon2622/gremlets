// The Terrarium (web/terrarium.html, docs/plans/TERRARIUM.md): an always-on Gremlets home for an iPad on the desk.
//
// It starts as an empty, glossy white glass room with a few Gremlets in it. They find a seed and plant it; moss creeps
// out across the floor, up the glass and over the ceiling; they build twig ledges plank by plank, a tree grows, plants
// and critters arrive, hanging homes go up, then a pond, a rope bridge, a waterfall, a mushroom house… (model.js has
// the plan). It all comes from points: a trickle for being open, more while Claude thinks on your Mac, a burst for
// every finished task (a flag goes in the moss and everyone cheers), and a little for playing with them.
//
// Touch: tap a Gremlet to poke it, hold to pet, drag to throw; tap the moss to plant a flower; tap a critter, a home,
// the pond. Night (9pm to 7am): they climb into the hanging homes or curl up on the moss, the room dims, they're up at
// 7. The scene shifts a few pixels each hour (burn-in), it reloads at 4am, and the bridge to the Mac reconnects forever.
import { World, V } from '../engine.js';
import { loadIndex, loadSpecies } from '../sprites.js';
import { FX, Particles } from '../effects.js';
import { Bridge } from '../bridge.js';
import { phaseAt, shiftAt } from '../terrarium.js';
import { TerraModel, PLAN } from './model.js';
import * as A from './art.js';
import { OfficeView } from './office.js';

const params = new URLSearchParams(location.search);
const SAVE = 'gremlets.terra.v1', INTRO = 'gremlets.terrarium.intro', RELOADED = 'gremlets.terrarium.reloaded';
const SPEED = Math.min(600, Math.max(1, +params.get('speed') || 1));          // ?speed=60: growth runs faster (demo)
const PREVIEW = params.has('preview') ? Math.max(0, +params.get('preview') || 0) : null;   // ?preview=150: built up to there
const clk = /^(\d{1,2}):(\d{2})$/.exec(params.get('clock') || '');
const clockOffset = clk ? (() => { const d = new Date(); d.setHours(+clk[1], +clk[2], 0, 0); return d.getTime() - Date.now(); })() : 0;
const now = () => new Date(Date.now() + clockOffset);
const store = {
  get(k) { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch { return null; } },
  set(k, v) { if (PREVIEW != null) return; try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* private mode */ } },
};
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const pick = (a) => a[Math.floor(Math.random() * a.length)];

const canvas = document.getElementById('world');
const ctx = canvas.getContext('2d');
const world = new World(Date.now() & 0xffff);
const particles = new Particles();
const bridge = new Bridge();
bridge.terrarium = true;
const saved = store.get(SAVE) || {};
const model = new TerraModel(saved.model);
if (PREVIEW != null) { model.points = PREVIEW; for (const p of PLAN) if (p.at <= PREVIEW) model.progress[p.id] = 1; model.moss = model.mossTarget(); }

let W = 0, H = 0, DPR = 1, P = 4, FLOOR = 40, roomH = 600;
let night = phaseAt(now().getHours()) === 'night', dusk = phaseAt(now().getHours()) === 'dusk';
let roomCanvas = null, roomKey = '';
const art = new Map();                    // creature id → sprite sheet
let seedX = saved.seedX ?? null;          // where the first seed went in (the moss spreads out from there)
let plants = Array.isArray(saved.plants) ? saved.plants.slice(0, 80) : [];   // { x, on, kind, s, hue, glow, by }
let flags = Array.isArray(saved.flags) ? saved.flags : [];                    // { x, hue, day }
let critters = [];                       // { kind, x, y, vx, on, f, t }
let tosses = [];                         // planks and seeds flying to a build: { from, to, t, dur, color }
let sessions = [], recent = [];          // Claude, from the Mac
const helpers = new Map();               // session id → creature id
const inside = new Map();                // creature id → home id (asleep inside at night)
const homeSway = new Map();              // home id → time nudged
let toast = null;                        // { text, until }
let lastSave = 0, lastSleepSweep = 0, lastPhaseCheck = 0, lastPlant = 0;

// ---------------------------------------------------------------- the room's geometry (world coords: y up, floor = FLOOR)

const FLOOR_OWNER = -1;
const toScreen = (x, y) => ({ x, y: H - y });
const plan = (id) => PLAN.find((p) => p.id === id);
const built = (id) => model.done(id);
const ledgeOf = (p) => ({ x0: Math.round(p.x0 * W / P) * P, x1: Math.round(p.x1 * W / P) * P, top: Math.round((FLOOR + p.y * roomH) / P) * P, fromLeft: p.x0 + p.x1 < 1 });
const homeOf = (p) => ({ x: Math.round(p.x * W / P) * P, porch: Math.round((FLOOR + p.y * roomH) / P) * P });
const ceilingY = () => H - P * 2;
let windowsKey = '';

/** The walkable things, as the engine's "windows": finished ledges, home porches and the bridge. */
function windows() {
  const out = [];
  for (const p of PLAN) {
    if (!built(p.id)) continue;
    if (p.kind === 'platform') { const l = ledgeOf(p); out.push({ id: p.id, x: l.x0, y: l.top - P * 4, w: l.x1 - l.x0, h: P * 4 }); }
    if (p.kind === 'home') { const h = homeOf(p); out.push({ id: p.id, x: h.x - 12 * P, y: h.porch - P * 2, w: 24 * P, h: P * 2 }); }
    if (p.kind === 'bridge') { const a = ledgeOf(plan(p.from)), b = ledgeOf(plan(p.to)); out.push({ id: p.id, x: a.x1, y: a.top - P * 2, w: b.x0 - a.x1, h: P * 2 }); }
  }
  return out;
}

function applyWorld() {
  const ws = windows();
  const key = ws.map((w) => w.id).join(',') + W + 'x' + H;
  if (key === windowsKey) return;
  windowsKey = key;
  world.setEnvironment([{ x: 0, y: FLOOR, w: W, h: H - FLOOR }], ws);
}

/** Vine ladders: one down from the wall end of each finished ledge, and from each home's porch, to the floor. */
function ladders() {
  const out = [];
  for (const p of PLAN) {
    if (!built(p.id)) continue;
    if (p.kind === 'platform') { const l = ledgeOf(p); out.push({ id: p.id, x: l.fromLeft ? l.x0 + 6 * P : l.x1 - 6 * P, top: l.top, step: l.fromLeft ? 3 * P : -3 * P }); }
    if (p.kind === 'home') { const h = homeOf(p); out.push({ id: p.id, x: h.x + 9 * P, top: h.porch, step: -3 * P }); }
  }
  return out;
}

function layout() {
  DPR = Math.min(2, devicePixelRatio || 1);
  W = innerWidth; H = innerHeight;
  canvas.width = Math.round(W * DPR); canvas.height = Math.round(H * DPR);
  canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
  P = Math.min(W, H) >= 700 ? 4 : 3;
  FLOOR = P * 12;
  roomH = H - FLOOR - P * 16;
  if (seedX == null) seedX = Math.round(W * (0.4 + Math.random() * 0.2));
  roomKey = '';
  windowsKey = '';
  applyWorld();
}

// ---------------------------------------------------------------- the Gremlets

async function addGremlet(id, x = null, quiet = true) {
  if (world.creatures.length >= 8) return null;
  const a = await loadSpecies(id, P);
  const c = world.spawn(a.species, V(x ?? W * (0.25 + Math.random() * 0.5), FLOOR + 40));
  art.set(c.id, a);
  if (!quiet) { say(c.id, pick(['Hello!', 'Is there room for me?', 'I heard about this place!', 'Ooh, cozy.']), 3); c.set('wave', 1.4); }
  return c;
}

const residents = () => world.creatures.filter((c) => !c.hidden);
const isFree = (c) => !c.hidden && !c.task && !c.climb && !['dragged', 'sleep', 'yawn'].includes(c.activity) && !onClaudeDuty(c);
function onClaudeDuty(c) {
  for (const [sid, cid] of helpers) if (cid === c.id) { const s = sessions.find((o) => o.id === sid); if (s && s.state === 'waiting') return true; }
  return false;
}

/** Where to stand and where the work goes, for a project. */
function site(p, near = null) {
  const fx = (f) => Math.round(f * W);
  switch (p.kind) {
    case 'platform': { const l = ledgeOf(p); const prog = model.progress[p.id] ?? 0; const n = Math.max(1, Math.round((l.x1 - l.x0) / (P * 4))); const k = Math.min(n - 1, Math.floor(n * prog)); const x = l.fromLeft ? l.x0 + k * P * 4 + 2 * P : l.x1 - k * P * 4 - 2 * P; return { stand: clamp(x + (l.fromLeft ? 30 : -30), 30, W - 30), to: V(x, l.top) }; }
    case 'home': { const h = homeOf(p); return { stand: h.x - 40, to: V(h.x, h.porch + 8 * P) }; }
    case 'bridge': { const a = ledgeOf(plan(p.from)), b = ledgeOf(plan(p.to)); const mx = (a.x1 + b.x0) / 2; return { stand: mx, to: V(mx, a.top) }; }
    case 'pond': { const x = fx((p.x0 + p.x1) / 2); return { stand: fx(p.x0) - 20, to: V(x, FLOOR) }; }
    case 'waterfall': case 'waterwheel': { const l = ledgeOf(plan('deck4')); return { stand: l.x0 - 30, to: V(l.x0 + 4 * P, (l.top + FLOOR) / 2) }; }
    case 'lanterns': { const l = ledgeOf(plan('deck1')); return { stand: (l.x0 + l.x1) / 2, to: V((l.x0 + l.x1) / 2, l.top - 6 * P) }; }
    case 'vines': return { stand: fx(0.5), to: V(fx(0.5), H - P * 20) };
    case 'tree': case 'shroomhouse': case 'lanternbloom': case 'crystal': case 'seed': {
      const x = p.kind === 'seed' ? seedX : p.kind === 'lanternbloom' ? fx(0.38) : fx(p.x);
      return { stand: x + (x < W / 2 ? 34 : -34), to: V(x, FLOOR + 10) };
    }
    default: { const x = mossyX(near) ?? fx(0.5); return { stand: x, to: V(x, FLOOR + 8) }; }
  }
}

/** A spot along the floor where there's moss (near `near`, if given). */
function mossyX(near = null) {
  if (model.moss <= 0 || seedX == null) return null;
  const reach = Math.min(1, model.moss / 0.3) * W * 0.75;
  const lo = Math.max(30, seedX - reach), hi = Math.min(W - 30, seedX + reach);
  if (near != null) return clamp(near + (Math.random() * 2 - 1) * 160, lo, hi);
  return lo + Math.random() * (hi - lo);
}

const builders = (id) => world.creatures.filter((c) => c.task?.kind === 'build' && c.task.id === id).length;

/** Their choices (instead of the engine's wandering, most of the time). */
function crewDecide(c) {
  if (c.hidden) return true;
  if (night) { c.set('idle', 2); return true; }
  const p = model.next();
  const want = p ? (p.kind === 'platform' || p.kind === 'home' || p.kind === 'bridge' ? 3 : 2) : 0;
  if (p && builders(p.id) < want && Math.random() < 0.85) { startTask(c, { kind: 'build', id: p.id }); return true; }
  const r = Math.random();
  const ls = ladders();
  if (r < 0.25 && model.moss > 0.05) { const x = mossyX(); if (x != null) { startTask(c, { kind: 'tend', x }); return true; } }
  if (r < 0.45 && critters.length) { const k = pick(critters); if (k.on === 'floor') { startTask(c, { kind: 'critter', x: k.x }); return true; } }
  if (r < 0.62 && ls.length && c.ground === FLOOR_OWNER) { startTask(c, { kind: 'climb', ladder: pick(ls).id }); return true; }
  if (r < 0.7) { const f = world.creatures.find((o) => o !== c && !o.hidden && o.isGrounded && Math.abs(o.pos.x - c.pos.x) < 300 && o.ground === c.ground); if (f) { c.facing = f.pos.x > c.pos.x ? 1 : -1; c.set('wave', 1.2); return true; } }
  return false;
}

function startTask(c, t) {
  world.endSocial(c);
  c.task = { terra: true, started: world.clock, ...t };
  c.set('idle', 0.05);
}

/** The next step of a task, whenever its current move ends. */
function crewTask(c) {
  const t = c.task;
  if (world.clock - t.started > 50 || (night && !['home', 'lantern'].includes(t.kind))) { c.task = null; c.carrying = null; c.set('idle', 0.3); return; }
  const goFloor = () => {
    if (c.ground === FLOOR_OWNER) return true;
    const s = world.supportingSurface(c);
    if (!s) return false;
    c.targetX = c.pos.x - s.minX < s.maxX - c.pos.x ? s.minX - 14 : s.maxX + 14;   // walk off the end
    c.facing = c.targetX > c.pos.x ? 1 : -1; c.set('walk', 8);
    return false;
  };
  const walkTo = (x) => {
    if (Math.abs(c.pos.x - x) <= 8) return true;
    c.targetX = clamp(x, 20, W - 20); c.facing = x > c.pos.x ? 1 : -1; c.set('walk', 10);
    return false;
  };
  switch (t.kind) {
    case 'build': {
      const p = plan(t.id);
      if (!p || built(t.id) || model.next()?.id !== t.id) { c.task = null; c.set('idle', 0.4); return; }
      if (!goFloor()) return;
      // (Spots picked at random, in the moss, are kept for the whole task; the rest move with the work.)
      const fixed = ['plants', 'critters', 'overgrown'].includes(p.kind);
      const s = fixed ? (t.site ??= site(p, c.pos.x)) : site(p);
      if (!walkTo(s.stand)) return;
      // Work: a swing, a plank (or a seed, a stone…) up to the site, and the project moves on.
      c.facing = s.to.x > c.pos.x ? 1 : -1;
      const thinking = sessions.filter((o) => o.state === 'thinking').length;
      const amount = 0.7 * SPEED * (1 + 0.5 * Math.min(2, thinking));
      tosses.push({ from: V(c.pos.x + c.facing * 10, c.pos.y + c.size.y * 0.7), to: s.to, t: 0, dur: 0.55, kind: p.kind });
      c.set('wave', 0.7);
      if (model.work(t.id, amount)) c.task = null;
      if (p.kind === 'plants' || p.kind === 'critters') growExtras(p);
      return;
    }
    case 'tend': {
      if (!goFloor() || !walkTo(t.x)) return;
      c.set('wave', 1.2);
      particles.burst(FX.rain, V(c.pos.x + c.facing * 14, c.pos.y + 20), { count: 4, dx: [-8, 8], dy: [-20, -6], duration: 0.6, stagger: 0.1 });
      const near = plants.find((pl) => pl.on === 'floor' && Math.abs(pl.x - c.pos.x) < 40 && pl.s < 1);
      if (near) near.s = Math.min(1, near.s + 0.25);
      c.task = null; return;
    }
    case 'critter': {
      if (!goFloor() || !walkTo(t.x)) return;
      c.set('wave', 1.4); say(c.id, pick(['Hi, little one!', 'Hello!', '♥', 'Ooh!']), 1.6); c.task = null; return;
    }
    case 'climb': {
      const l = ladders().find((o) => o.id === t.ladder);
      if (!l) { c.task = null; return; }
      if (!goFloor() || !walkTo(l.x)) return;
      c.climb = { x: l.x, top: l.top, step: l.step, onTop: t.onTop };
      c.task = null; c.set('dragged');
      return;
    }
    case 'home': {
      const l = ladders().find((o) => o.id === t.home);
      if (!l) { c.task = null; return; }
      if (c.ground === t.home) { inside.set(c.id, t.home); c.hidden = true; c.task = null; c.set('sleep', 9999); return; }
      if (!goFloor() || !walkTo(l.x)) return;
      c.climb = { x: l.x, top: l.top, step: l.step, onTop: { kind: 'home', home: t.home } };
      c.task = null; c.set('dragged'); return;
    }
    case 'lantern': c.set('idle', 2); return;   // holding it up (updateClaude ends it)
    default: c.task = null; c.set('idle', 0.3);
  }
}

/** Climbing a vine ladder: up it goes, then a step onto the ledge (or into the home). */
function updateClimbs(dt) {
  for (const c of world.creatures) {
    const k = c.climb;
    if (!k) continue;
    if (c.activity !== 'dragged') { c.climb = null; continue; }
    c.pos = V(k.x + Math.sin(world.clock * 9) * 1.5, Math.min(k.top, c.pos.y + 80 * dt));
    c.animTime += dt;
    if (c.pos.y >= k.top) {
      c.pos = V(k.x + k.step, k.top);
      c.climb = null; c.vel = V(0, 0);
      c.set('land', 0.2);
      if (k.onTop?.kind === 'home') { const id = k.onTop.home; setTimeout(() => { if (night) { inside.set(c.id, id); c.hidden = true; c.set('sleep', 9999); } }, 400); }
    }
  }
}

// ---------------------------------------------------------------- what grows: plants and critters

function surfacesForPlants() {
  const out = [];
  if (model.moss > 0) {
    const reach = Math.min(1, model.moss / 0.3) * W * 0.75;
    out.push({ on: 'floor', lo: Math.max(14, seedX - reach), hi: Math.min(W - 14, seedX + reach), y: FLOOR });
  }
  if (model.moss > 0.2) for (const p of PLAN) if (p.kind === 'platform' && built(p.id)) { const l = ledgeOf(p); out.push({ on: p.id, lo: l.x0 + 8, hi: l.x1 - 8, y: l.top }); }
  return out;
}

function addPlant(kind, glow = false, at = null) {
  const ss = surfacesForPlants();
  if (!ss.length) return null;
  const s = at ? ss.find((o) => o.on === 'floor') : pick(ss);
  if (!s) return null;
  const x = at ?? s.lo + Math.random() * (s.hi - s.lo);
  if (plants.some((p) => p.on === s.on && Math.abs(p.x - x) < 10)) return null;
  const p = { x: Math.round(x), on: s.on, kind, s: 0.1, hue: Math.floor(Math.random() * 4), glow };
  plants.push(p);
  if (plants.length > 80) plants.shift();
  return p;
}

/** Plants and critters arrive as their project's work goes in. */
function growExtras(p) {
  const prog = model.progress[p.id] ?? 0;
  if (p.kind === 'plants') {
    const have = plants.filter((pl) => pl.by === p.id).length;
    if (have < Math.round(p.n * prog)) {
      const kind = p.glow ? 2 : p.id === 'sprig' ? 1 : p.id === 'garden' ? pick([0, 0, 1, 3]) : pick([0, 0, 1]);
      const pl = addPlant(kind, !!p.glow);
      if (pl) pl.by = p.id;
    }
  }
}

function spawnCritters() {
  critters = [];
  for (const p of PLAN) {
    if (p.kind !== 'critters' || !built(p.id)) continue;
    for (const kind of p.kinds) critters.push(newCritter(kind));
  }
}

function newCritter(kind) {
  const flies = kind === 'bee' || kind === 'butterfly' || kind === 'firefly';
  const ss = surfacesForPlants();
  const s = ss.length ? pick(ss) : { on: 'floor', lo: 40, hi: W - 40, y: FLOOR };
  const x = s.lo + Math.random() * (s.hi - s.lo);
  return { kind, x, y: flies ? FLOOR + 60 + Math.random() * roomH * 0.6 : s.y, on: flies ? 'air' : s.on, lo: s.lo, hi: s.hi, vx: (Math.random() < 0.5 ? -1 : 1) * (kind === 'snail' ? 3 : kind === 'ladybug' ? 12 : 30), f: 0, t: Math.random() * 10, home: V(x, FLOOR + roomH * 0.4) };
}

function updateCritters(dt, t) {
  for (const k of critters) {
    k.t += dt;
    if (k.on === 'air') {
      if (k.kind === 'firefly' && !night) { k.y = FLOOR + 6; continue; }   // resting in the moss by day
      const tx = k.home.x + Math.sin(k.t * 0.3 + k.x * 0.01) * W * 0.25, ty = k.home.y + Math.sin(k.t * 0.5) * roomH * 0.25;
      k.vx = (tx - k.x) * 0.4; k.x += k.vx * dt; k.y += (ty - k.y) * 0.4 * dt + Math.sin(k.t * 6) * 0.4;
      k.f = Math.floor(k.t * (k.kind === 'bee' ? 14 : 6)) % 2;
    } else {
      if (Math.random() < dt * 0.15) k.vx = -k.vx;
      k.x += k.vx * dt;
      if (k.x < k.lo || k.x > k.hi) { k.vx = -k.vx; k.x = clamp(k.x, k.lo, k.hi); }
    }
  }
  for (const p of plants) if (p.s < 1) p.s = Math.min(1, p.s + dt / 240);
}

// ---------------------------------------------------------------- Claude, from the Mac

bridge.onClaude = (n) => {
  const ok = (s) => ['thinking', 'waiting', 'done'].includes(s);
  const clean = (p) => String(p ?? '').slice(0, 32);
  const before = new Map(sessions.map((s) => [s.id, s.state]));
  sessions = n.sessions.filter((s) => s && typeof s.id === 'string' && ok(s.state)).slice(0, 8).map((s) => ({ id: s.id.slice(0, 12), project: clean(s.project), state: s.state }));
  recent = (Array.isArray(n.recent) ? n.recent : []).filter((e) => e && ok(e.state)).slice(-5).map((e) => ({ project: clean(e.project), state: e.state, at: +e.at || 0 }));
  // Each finished task (by its time, so nothing counts twice): a burst of growth, a flag and a cheer.
  for (const e of recent) if (e.state === 'done' && model.taskDone(e.at)) celebrateTask(e.project);
  for (const s of sessions) if (s.state === 'done' && before.get(s.id) !== 'done') { /* counted via recent */ }
  for (const id of [...helpers.keys()]) if (!sessions.some((s) => s.id === id)) helpers.delete(id);
  applyDim(); renderStrip(); renderLeaf(); save();
};

// The Back Office on the Mac: its latest events join the strip, and good news (a sale, a green run) sparkles.
let office = [];
const OFFICE_ICON = { workshop: '🛠', railroad: '🚂', aquarium: '🐟', postOffice: '🕊', factory: '📦', board: '📌', farm: '🏁' };
const officeView = new OfficeView();
bridge.onOffice = (n) => {
  officeView.update(n, true);
  const seen = new Set(office.map((e) => e.at + e.title));
  office = n.events.filter((e) => e && typeof e.title === 'string').slice(-5).map((e) => ({ room: String(e.room ?? '').slice(0, 16), title: String(e.title).slice(0, 40), severity: e.severity, at: +e.at || 0 }));
  for (const e of office) if (!seen.has(e.at + e.title) && e.severity === 'good') {
    const x = mossyX() ?? W / 2;
    particles.burst(FX.sparkle, V(x, FLOOR + 30), { count: 5, dx: [-30, 30], dy: [10, 60], duration: 1.1, stagger: 0.06 });
    model.played(Date.now() / 1000);
  }
  renderStrip();
};

function celebrateTask(project) {
  const day = now().toDateString();
  flags = flags.filter((f) => f.day === day);
  const x = clamp((mossyX() ?? W * 0.5) + (Math.random() - 0.5) * 80, 30, W - 30);
  flags.push({ x: Math.round(x), hue: flags.length, day });
  particles.burst(FX.sparkle, V(x, FLOOR + 20), { count: 10, dx: [-40, 40], dy: [20, 90], duration: 1.3, stagger: 0.05 });
  particles.burst(FX.leaf, V(x, FLOOR + 30), { count: 6, dx: [-60, 60], dy: [30, 110], duration: 1.6, stagger: 0.08, imgs: [FX.leaf, FX.leaf2, FX.smallHeart] });
  for (const c of residents()) if (c.isGrounded && !c.isAsleep) { c.task = null; c.set('dance', 2.2); }
  showToast(`${project}: done ✓  The Gremlets are cheering.`);
}

function helperFor(s) {
  let c = world.byId(helpers.get(s.id));
  if (c && !c.hidden) return c;
  const taken = new Set(helpers.values());
  c = residents().find((o) => !taken.has(o.id));
  if (c) helpers.set(s.id, c.id);
  return c;
}

function updateClaude() {
  for (const s of sessions) {
    const c = helperFor(s);
    if (!c) continue;
    if (s.state !== 'waiting') { if (c.task?.kind === 'lantern') c.task = null; continue; }
    if (c.hidden) { wakeFromHome(c); continue; }
    if (c.isAsleep) { c.set('wake', c.animationLength('wake')); continue; }
    const i = sessions.filter((o) => o.state === 'waiting').indexOf(s);
    const x = i % 2 === 0 ? 46 + (i >> 1) * 70 : W - 46 - (i >> 1) * 70;
    if (c.climb || !c.isGrounded) continue;
    if (c.ground !== FLOOR_OWNER) { if (!c.task) startTask(c, { kind: 'tend', x }); continue; }
    if (Math.abs(c.pos.x - x) > 8) { if (c.activity !== 'walk') { c.task = { terra: true, kind: 'lantern', started: world.clock }; c.targetX = x; c.facing = x > c.pos.x ? 1 : -1; c.set('walk', 30); } }
    else if (c.activity !== 'idle' || c.timer < 0.5) { c.task = { terra: true, kind: 'lantern', started: world.clock }; c.targetX = null; c.facing = x < W / 2 ? 1 : -1; c.set('idle', 3); }
  }
}

// ---------------------------------------------------------------- night

function setPhase() {
  const h = now().getHours(), p = phaseAt(h);
  const wasNight = night;
  night = p === 'night'; dusk = p === 'dusk';
  document.body.classList.toggle('night', night);
  document.documentElement.style.background = night ? '#1b2133' : '#eef3f7';
  if (wasNight && !night) morning();
  applyDim();
  const s = shiftAt(h);
  document.body.style.transform = `translate(${s.x}px, ${s.y}px)`;
  const day = now().toDateString();
  if (h === 4 && store.get(RELOADED) !== day && PREVIEW == null) { try { localStorage.setItem(RELOADED, JSON.stringify(day)); } catch { /* */ } location.reload(); }
}

function bedtime(t) {
  if (!night || t - lastSleepSweep < 2) return;
  lastSleepSweep = t;
  const homes = PLAN.filter((p) => p.kind === 'home' && built(p.id));
  const room = new Map(homes.map((h) => [h.id, [...inside.values()].filter((v) => v === h.id).length]));
  for (const c of residents()) {
    if (onClaudeDuty(c) || c.climb || !c.isGrounded || ['dragged', 'wake', 'react'].includes(c.activity)) continue;
    if (c.activity === 'sleep') { c.timer = Math.max(c.timer, 60); c.energy = Math.min(c.energy, 0.4); continue; }
    if (c.isAsleep || c.task?.kind === 'home') continue;
    const home = homes.find((h) => room.get(h.id) < 2);
    if (home) { room.set(home.id, room.get(home.id) + 1); startTask(c, { kind: 'home', home: home.id }); continue; }
    c.task = null; c.set('yawn', c.animationLength('yawn'));
  }
}

function wakeFromHome(c) {
  const id = inside.get(c.id);
  inside.delete(c.id);
  c.hidden = false;
  const p = plan(id);
  if (p) { const h = homeOf(p); c.pos = V(h.x - 6 * P, h.porch); }
  c.set('wave', 1.4);
}

function morning() {
  for (const c of world.creatures) {
    if (c.hidden) wakeFromHome(c);
    else if (c.isAsleep) { c.timer = 0; c.set('wake', c.animationLength('wake')); }
  }
  showToast('Good morning! ☀️');
}

const dim = document.getElementById('tdim');
function applyDim() { dim.style.opacity = night ? (sessions.some((s) => s.state === 'waiting') ? '0.5' : '0.75') : '0'; }

// ---------------------------------------------------------------- touch

let press = null;
const toWorld = (e) => V(e.clientX, H - e.clientY);
canvas.addEventListener('pointerdown', (e) => {
  const p = toWorld(e);
  let c = world.creatureAt(p);
  if (c?.hidden) c = null;
  press = { p, c, t: performance.now(), moved: false, petLoop: null };
  if (c) press.petTimer = setTimeout(() => { if (press && !press.moved) { press.petted = true; press.petLoop = setInterval(() => world.pet(c, 120), 120); world.pet(c, 300); model.played(Date.now() / 1000); } }, 380);
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener('pointermove', (e) => {
  if (!press) return;
  const p = toWorld(e);
  if (!press.moved && Math.hypot(p.x - press.p.x, p.y - press.p.y) > 10 && press.c && !press.petted) {
    press.moved = true; clearTimeout(press.petTimer);
    const c = press.c;
    if (c.climb) c.climb = null;
    if (c.hidden) return;
    c.task = null;
    world.beginDrag(c, p, performance.now() / 1000);
  }
  if (press.moved && press.c) world.drag(press.c, p, performance.now() / 1000);
});
const release = (e) => {
  if (!press) return;
  clearTimeout(press.petTimer); clearInterval(press.petLoop);
  const p = toWorld(e);
  if (press.moved && press.c) world.endDrag(press.c, performance.now() / 1000);
  else if (press.c && !press.petted) { world.poke(press.c); particles.burst(FX.smallHeart, V(press.c.pos.x, press.c.pos.y + press.c.size.y), { count: 2, dx: [-10, 10], dy: [16, 30], duration: 0.8 }); model.played(Date.now() / 1000); }
  else if (!press.c) tapScene(p);
  press = null;
};
canvas.addEventListener('pointerup', release);
canvas.addEventListener('pointercancel', release);

/** Tapping the room: a critter, a home, the pond, or the moss (a flower comes up there). */
function tapScene(p) {
  const k = critters.find((o) => Math.hypot(o.x - p.x, o.y - p.y) < 26);
  if (k) {
    if (k.on === 'air') { k.home = V(clamp(p.x + (Math.random() - 0.5) * 300, 40, W - 40), FLOOR + roomH * (0.2 + Math.random() * 0.6)); }
    else k.vx = -k.vx * 2;
    particles.burst(FX.smallHeart, V(k.x, k.y + 10), { count: 1, dx: [-4, 4], dy: [12, 20], duration: 0.7 });
    return;
  }
  for (const h of PLAN.filter((o) => o.kind === 'home' && built(o.id))) {
    const g = homeOf(h);
    if (Math.abs(p.x - g.x) < 12 * P && p.y > g.porch && p.y < g.porch + 22 * P) {
      homeSway.set(h.id, performance.now() / 1000);
      for (const [cid, hid] of inside) if (hid === h.id && !night) wakeFromHome(world.byId(cid));
      return;
    }
  }
  const pond = plan('pond');
  if (built('pond') && p.x > pond.x0 * W && p.x < pond.x1 * W && p.y < FLOOR + 20) {
    particles.burst(FX.rain, V(p.x, FLOOR + 4), { count: 5, dx: [-14, 14], dy: [10, 30], duration: 0.6 });
    return;
  }
  // The moss: a flower comes up where you tapped (now and then), and someone comes to water it.
  if (model.moss > 0.05 && p.y < FLOOR + 40 && performance.now() / 1000 - lastPlant > 8) {
    const pl = addPlant(pick([0, 0, 1, 3]), false, p.x);
    if (pl) {
      lastPlant = performance.now() / 1000;
      particles.burst(FX.sparkle, V(pl.x, FLOOR + 8), { count: 3, dx: [-10, 10], dy: [6, 20], duration: 0.7 });
      model.played(Date.now() / 1000);
      const c = residents().filter(isFree).sort((a, b) => Math.abs(a.pos.x - pl.x) - Math.abs(b.pos.x - pl.x))[0];
      if (c) startTask(c, { kind: 'tend', x: pl.x + 14 });
      save();
    }
    return;
  }
  particles.burst(FX.sparkle, V(p.x, p.y), { count: 1, dx: [-2, 2], dy: [2, 6], duration: 0.5 });
}

// ---------------------------------------------------------------- bubbles, toast, the recent strip, the progress leaf

const bubbles = [];
function say(id, text, secs) {
  const host = document.getElementById('bubbles');
  for (const b of bubbles.filter((b) => b.id === id)) { b.el.remove(); bubbles.splice(bubbles.indexOf(b), 1); }
  const el = document.createElement('div'); el.className = 'say'; el.textContent = text;
  host.appendChild(el);
  bubbles.push({ el, id, until: performance.now() / 1000 + secs });
}
function placeBubbles(t) {
  for (let i = bubbles.length - 1; i >= 0; i--) {
    const b = bubbles[i], c = world.byId(b.id);
    if (!c || c.hidden || t > b.until) { b.el.remove(); bubbles.splice(i, 1); continue; }
    const s = toScreen(c.pos.x, c.pos.y + c.size.y + 8);
    b.el.style.left = Math.round(clamp(s.x, 60, W - 60)) + 'px'; b.el.style.top = Math.round(s.y) + 'px';
  }
}
function showToast(text) {
  const el = document.getElementById('ttoast');
  el.textContent = text; el.classList.add('on');
  toast = performance.now() / 1000 + 5;
}

const icons = Object.fromEntries(['thinking', 'waiting', 'done'].map((s) => [s, A.icon(s).toDataURL()]));
const lanternImg = A.icon('waiting');
function renderStrip() {
  const strip = document.getElementById('trecent');
  const n = Date.now() / 1000;
  const ago = (t) => { const s = Math.max(0, n - t); return s < 90 ? 'now' : s < 3600 ? `${Math.round(s / 60)}m` : `${Math.round(s / 3600)}h`; };
  const words = { thinking: 'thinking', waiting: 'needs you', done: 'done' };
  const items = [...recent.map((e) => ({ ...e, claude: true })), ...office.map((e) => ({ ...e, claude: false }))].sort((a, b) => a.at - b.at).slice(-5);
  strip.replaceChildren(...items.map((e) => {
    const el = document.createElement('div'); el.className = 'tcard ' + (e.claude ? e.state : 'office ' + (e.severity || ''));
    if (e.claude) el.append(Object.assign(document.createElement('img'), { src: icons[e.state], alt: '' }));
    else el.append(Object.assign(document.createElement('b'), { textContent: OFFICE_ICON[e.room] ?? '🏢', className: 'ticon' }));
    const t = document.createElement('span'); t.textContent = e.claude ? `${e.project} · ${words[e.state]}` : e.title;
    el.append(t, Object.assign(document.createElement('small'), { textContent: ago(e.at) }));
    return el;
  }));
}

function renderLeaf() {
  const cur = model.next(), up = model.upcoming();
  const building = cur && model.started(cur.id) ? `building ${cur.label}` : cur ? `about to start ${cur.label}` : up ? `next idea: ${up.project.label}` : 'all done, just living';
  const flagsToday = flags.filter((f) => f.day === now().toDateString()).length;
  document.getElementById('tstage').textContent = model.stage();
  document.getElementById('tdoing').textContent = building + (flagsToday ? ` · ${flagsToday} ⚑ today` : '');
  document.getElementById('tbar').style.width = `${Math.round((cur && model.started(cur.id) ? model.progress[cur.id] : up?.frac ?? 1) * 100)}%`;
}

// ---------------------------------------------------------------- events

function handleModel() {
  const evs = model.drain();
  if (evs.length) renderLeaf();
  for (const e of evs) {
    const p = plan(e.id);
    if (e.type === 'built' && p) {
      applyWorld();
      const s = site(p);
      particles.burst(FX.sparkle, s.to, { count: 8, dx: [-40, 40], dy: [0, 50], duration: 1.1, stagger: 0.05 });
      if (p.kind === 'critters') { spawnCritters(); }
      if (p.kind === 'seed') showToast('They planted a seed. Something is starting… 🌱');
      else showToast(`✨ They finished ${p.label}!`);
      for (const c of residents()) if (c.isGrounded && !c.isAsleep && !onClaudeDuty(c) && Math.abs(c.pos.x - s.to.x) < 400) { c.task = null; c.set('dance', 1.8); }
      // Some places bring a new neighbour.
      if (['home1', 'home2', 'shroomhouse', 'bridge'].includes(p.id)) newcomer();
      save();
    }
    if (e.type === 'unlocked' && p) showToast(`The Gremlets have an idea: ${p.label}.`);
  }
}

let index = [];
async function newcomer() {
  if (world.creatures.length >= 8 || !index.length) return;
  const have = new Set(world.creatures.map((c) => c.species.id));
  const id = pick(index.map((s) => s.id).filter((i) => !have.has(i)));
  if (!id) return;
  const c = await addGremlet(id, Math.random() < 0.5 ? 30 : W - 30, false);
  if (c) save();
}

// ---------------------------------------------------------------- saving

function save() {
  store.set(SAVE, { model: model.toJSON(), seedX, plants: plants.map((p) => ({ x: p.x, on: p.on, kind: p.kind, s: Math.round(p.s * 100) / 100, hue: p.hue, glow: p.glow, by: p.by })), flags, roster: residents().map((c) => c.species.id).concat([...inside.keys()].map((id) => world.byId(id)?.species.id).filter(Boolean)) });
}

// ---------------------------------------------------------------- the loop

let last = performance.now();
function frame(nowMs) {
  const dt = Math.min(0.05, (nowMs - last) / 1000); last = nowMs;
  const t = nowMs / 1000;
  const thinking = sessions.filter((s) => s.state === 'thinking').length;
  model.tick(dt * SPEED, { thinking });
  handleModel();
  updateClimbs(dt);
  world.step(dt);
  for (const e of world.drainEvents()) if (e.type === 'landed' || e.type === 'poked') { /* quiet */ }
  updateCritters(dt, t);
  updateClaude();
  bedtime(t);
  for (const k of tosses) k.t += dt;
  tosses = tosses.filter((k) => k.t < k.dur);
  particles.update(dt);
  if (t - lastPhaseCheck > 20) { lastPhaseCheck = t; setPhase(); renderStrip(); renderLeaf(); }
  if (t - lastSave > 30) { lastSave = t; save(); }
  if (toast && t > toast) { document.getElementById('ttoast').classList.remove('on'); toast = null; }
  if (!officeView.frame(night)) { draw(t); placeBubbles(t); }
  requestAnimationFrame(frame);
}

function draw(t) {
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.imageSmoothingEnabled = false;
  // The room and its moss (redrawn as the moss grows).
  const key = `${W}x${H}-${Math.round(model.moss * 60)}-${night}-${built('overgrown')}`;
  if (key !== roomKey) {
    roomKey = key;
    roomCanvas = roomCanvas || document.createElement('canvas');
    roomCanvas.width = W; roomCanvas.height = H;
    A.paintRoom(roomCanvas.getContext('2d'), { W, H, P, floor: FLOOR, m: model.moss, seedX, night, overgrown: built('overgrown') });
  }
  ctx.drawImage(roomCanvas, 0, 0, W, H);
  const g = ctx, fy = H - FLOOR, m = model.moss;
  // Hanging vines (decoration) from the ceiling.
  if (built('vines')) for (let i = 0; i < 7; i++) A.paintVine(g, { x: Math.round(W * (0.1 + i * 0.13) / P) * P, top: P * 3, bottom: P * (16 + ((i * 7) % 20)) + H * 0.12, P, t, night });
  // Everything they've built (or are building).
  for (const p of PLAN) {
    const prog = model.progress[p.id] ?? 0;
    if (prog <= 0 && p.kind !== 'tree') continue;
    switch (p.kind) {
      case 'platform': { const l = ledgeOf(p); A.paintLedge(g, { x0: l.x0, x1: l.x1, y: H - l.top, p: prog, P, moss: m, night, fromLeft: l.fromLeft }); break; }
      case 'tree': if (prog > 0) A.paintTree(g, { x: Math.round(W * p.x / P) * P, y: fy, s: 0.25 + Math.max(0, model.points - p.at) / 160, P, t, night, p: prog }); break;
      case 'home': { const h = homeOf(p); const nudged = homeSway.get(p.id); const age = nudged ? t - nudged : 9; const sway = age < 3 ? Math.round(Math.sin(age * 7) * 4 * Math.exp(-age)) * P : 0; A.paintHome(g, { x: h.x, y: H - h.porch, p: prog, P, t, night, sway, sleepers: [...inside.values()].filter((v) => v === p.id).length, ceiling: P * 2 }); break; }
      case 'pond': A.paintPond(g, { x0: Math.round(p.x0 * W / P) * P, x1: Math.round(p.x1 * W / P) * P, y: fy, p: prog, P, t, night }); break;
      case 'bridge': { const a = ledgeOf(plan(p.from)), b = ledgeOf(plan(p.to)); A.paintBridge(g, { xa: a.x1, xb: b.x0, y: H - a.top, p: prog, P, night }); break; }
      case 'waterfall': { const l = ledgeOf(plan('deck4')); A.paintFalls(g, { x: l.x0 + 2 * P, top: H - l.top + 4 * P, bottom: fy, p: prog, P, t, night }); break; }
      case 'waterwheel': { const l = ledgeOf(plan('deck4')); A.paintWheel(g, { x: l.x0 - 4 * P, y: fy - 14 * P, p: prog, P, t }); break; }
      case 'shroomhouse': A.paintShroomHouse(g, { x: Math.round(W * p.x / P) * P, y: fy, p: prog, P, night }); break;
      case 'lanternbloom': A.paintBloom(g, { x: Math.round(W * 0.38 / P) * P, y: fy, p: prog, P, t, night }); break;
      case 'crystal': A.paintCrystal(g, { x: Math.round(W * p.x / P) * P, y: fy, p: prog, P, t, night }); break;
      case 'lanterns': {
        let i = 0;
        for (const d of PLAN.filter((o) => o.kind === 'platform' && built(o.id))) {
          const l = ledgeOf(d);
          for (const fx of [0.3, 0.7]) if (i++ < Math.ceil(prog * 8)) A.paintLantern(g, { x: Math.round((l.x0 + (l.x1 - l.x0) * fx) / P) * P, y: H - l.top + 4 * P, P, t, night, i });
        }
        break;
      }
      case 'seed': if (prog < 1) A.px(g, seedX, fy - P * 2, 2, 2, '#8a5f3e', P); break;
    }
  }
  // Vine ladders.
  for (const l of ladders()) A.paintVine(g, { x: l.x, top: H - l.top + P * 4, bottom: fy, P, t, night });
  // Plants, flags, critters.
  for (const p of plants) {
    const y = p.on === 'floor' ? fy - P * 2 : H - ledgeOf(plan(p.on) ?? plan('deck1')).top - P;
    A.paintPlant(g, { x: p.x, y, kind: p.kind, s: p.s, P, t, night, glow: p.glow, hue: p.hue });
  }
  const today = now().toDateString();
  for (const f of flags) if (f.day === today) A.paintFlag(g, { x: f.x, y: fy - P, P, t, hue: f.hue });
  for (const k of critters) A.paintCritter(g, { kind: k.kind, x: Math.round(k.x), y: Math.round(H - k.y), f: k.f, P: Math.max(2, P - 1), facing: k.vx, night });
  // The things flying to a build: planks, seeds, stones.
  for (const k of tosses) {
    const u = k.t / k.dur;
    const x = k.from.x + (k.to.x - k.from.x) * u, y = k.from.y + (k.to.y - k.from.y) * u + Math.sin(u * Math.PI) * 50;
    const s = toScreen(x, y);
    A.px(g, s.x, s.y, k.kind === 'platform' || k.kind === 'bridge' || k.kind === 'home' ? 3 : 1, 1, k.kind === 'pond' || k.kind === 'waterfall' ? A.C.water : k.kind === 'plants' || k.kind === 'seed' ? A.C.mossLight : A.C.wood, P);
  }
  // The Gremlets (and soft shadows, and nests at night).
  for (const c of world.creatures) {
    if (c.hidden) continue;
    const s = toScreen(c.pos.x, c.pos.y);
    if (c.isGrounded) {
      ctx.fillStyle = night ? 'rgba(0,0,20,0.28)' : 'rgba(80,100,120,0.16)';
      ctx.beginPath(); ctx.ellipse(s.x, s.y - 1, c.size.x * 0.26, P * 1.2, 0, 0, Math.PI * 2); ctx.fill();
      if (c.activity === 'sleep') { A.px(g, s.x - 7 * P, s.y - P, 14, 1, A.C.woodDark, P); A.px(g, s.x - 8 * P, s.y - 3 * P, 3, 2, A.C.twig, P); A.px(g, s.x + 5 * P, s.y - 3 * P, 3, 2, A.C.twig, P); }
    }
    const a = art.get(c.id);
    const r = a?.rects[c.currentFrame];
    if (!r) continue;
    const w = r.w * P, h = r.h * P;
    ctx.save(); ctx.translate(Math.round(s.x), Math.round(s.y)); if (c.facing < 0) ctx.scale(-1, 1);
    ctx.drawImage(a.image, r.x, r.y, r.w, r.h, -w / 2, -h, w, h);
    ctx.restore();
  }
  drawClaude(t);
  particles.draw(ctx, toScreen, P);
  A.paintGlass(g, { W, H, P, night });
}

function drawClaude(t) {
  for (const s of sessions) {
    const c = world.byId(helpers.get(s.id));
    if (!c || c.hidden) continue;
    const head = toScreen(c.pos.x, c.pos.y + c.size.y * 0.95);
    if (s.state === 'thinking') {
      const bob = Math.sin(t * 2.2 + c.id) * P;
      const cx = Math.round(head.x + c.facing * 4), cy = Math.round(head.y - 10 * P + bob);
      ctx.fillStyle = night ? 'rgba(220,226,245,0.95)' : 'rgba(255,255,255,0.97)';
      ctx.fillRect(cx - 7 * P, cy - 3 * P, 14 * P, 6 * P); ctx.fillRect(cx - 5 * P, cy - 5 * P, 10 * P, 10 * P);
      ctx.strokeStyle = 'rgba(150,165,190,0.6)'; ctx.lineWidth = 1; ctx.strokeRect(cx - 7 * P + 0.5, cy - 3 * P + 0.5, 14 * P, 6 * P);
      ctx.fillRect(Math.round(head.x) - P, Math.round(head.y - 2 * P), 2 * P, 2 * P);
      ctx.fillStyle = '#6a7390';
      for (let i = 0; i < 3; i++) if (Math.floor(t * 3) % 4 > i) ctx.fillRect(cx + (i - 1) * 3 * P - P / 2, cy - P / 2, P, P);
    } else if (s.state === 'waiting' && c.task?.kind === 'lantern' && c.targetX == null) {
      const hand = toScreen(c.pos.x + c.facing * c.size.x * 0.28, c.pos.y + c.size.y * 0.62);
      const L = 9 * P * 1.2, swing = Math.sin(t * 2.4) * P;
      const gr = ctx.createRadialGradient(hand.x, hand.y + L * 0.4, 2, hand.x, hand.y + L * 0.4, 50);
      gr.addColorStop(0, `rgba(255,210,110,${0.45 + 0.1 * Math.sin(t * 6)})`); gr.addColorStop(1, 'rgba(255,200,90,0)');
      ctx.fillStyle = gr; ctx.fillRect(hand.x - 50, hand.y + L * 0.4 - 50, 100, 100);
      ctx.drawImage(lanternImg, Math.round(hand.x - L / 2 + swing), Math.round(hand.y), L, L);
      const foot = toScreen(c.pos.x - c.facing * c.size.x * 0.45, c.pos.y);
      ctx.font = `700 ${Math.max(11, Math.round(P * 3.5))}px ui-rounded, system-ui, sans-serif`;
      const tw = Math.ceil(ctx.measureText(s.project).width), bw = tw + 4 * P, bh = 6 * P;
      const bx = Math.round(clamp(foot.x - bw / 2, 4, W - bw - 4)), by = Math.round(foot.y - 14 * P);
      ctx.fillStyle = '#6b4428'; ctx.fillRect(Math.round(foot.x) - P / 2, by + bh, P, 14 * P - bh);
      ctx.fillStyle = '#c9a15a'; ctx.fillRect(bx, by, bw, bh); ctx.fillStyle = '#9c7840'; ctx.fillRect(bx, by + bh - P, bw, P);
      ctx.fillStyle = '#3a2614'; ctx.textBaseline = 'middle'; ctx.fillText(s.project, bx + 2 * P, by + bh / 2);
    }
  }
}

// ---------------------------------------------------------------- start

// Keep the iPad awake. iPadOS can drop the lock at any time (a notification, Low Power Mode, a tap elsewhere), so
// hold on to it, ask again when it's released, on every tap, and once a minute as a backstop.
let wakeLock = null;
async function wake() {
  if (document.hidden || (wakeLock && !wakeLock.released)) return;
  try {
    wakeLock = await navigator.wakeLock?.request('screen');
    wakeLock?.addEventListener('release', () => { wakeLock = null; setTimeout(wake, 1000); });
  } catch { wakeLock = null; /* not allowed here */ }
}
document.addEventListener('pointerdown', wake, { passive: true });
setInterval(wake, 60_000);

async function start() {
  layout();
  addEventListener('resize', () => { layout(); });
  index = await loadIndex();
  // The engine's own choices, used when the crew has nothing for them (flyers mostly stay on their feet here).
  const baseDecide = world.decide.bind(world), baseTask = world.taskDecide.bind(world);
  world.decide = (c) => {
    if (crewDecide(c)) return;
    const flies = c.species.flies;
    if (flies && Math.random() < 0.8) c.species.flies = false;
    baseDecide(c);
    c.species.flies = flies;
  };
  world.taskDecide = (c) => { if (c.task?.terra) crewTask(c); else baseTask(c); };
  world.mossMinutes = 0;   // (the engine's own sprouts stay out of it: the Terrarium has its plants)
  const roster = (saved.roster || []).filter((id) => index.some((s) => s.id === id));
  const ids = roster.length ? roster.slice(0, 8) : ['flurrie', 'kindlet', 'dandelet'].filter((id) => index.some((s) => s.id === id));
  await Promise.all(ids.map((id, i) => addGremlet(id, W * (0.3 + 0.4 * (i + 0.5) / ids.length))));
  spawnCritters();
  if (PREVIEW != null) { for (const p of PLAN) if (built(p.id) && p.kind === 'plants') for (let i = 0; i < p.n; i++) { const pl = addPlant(p.glow ? 2 : pick([0, 0, 1, 3]), !!p.glow); if (pl) { pl.s = 1; pl.by = p.id; } } }
  // From the Mac: Gremlets walking over move in; Claude's status (bridge.onClaude above).
  bridge.onWalk = async (n) => {
    if (world.creatures.some((c) => c.species.id === n.species) || !index.some((s) => s.id === n.species)) return;
    const c = await addGremlet(n.species, n.to === 'left' ? 24 : W - 24, false);
    if (c) save();
  };
  bridge.onStatus = () => { document.getElementById('tlink').classList.toggle('on', bridge.connected); };
  bridge.start();
  setPhase(); renderStrip(); renderLeaf();
  wake();
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { wake(); last = performance.now(); } });
  if (!store.get(INTRO) && PREVIEW == null) document.getElementById('tintro').hidden = false;
  document.getElementById('tintro-ok').addEventListener('click', () => { try { localStorage.setItem(INTRO, '1'); } catch { /* */ } document.getElementById('tintro').hidden = true; });
  if (params.has('debug')) window.terra = { officeView, world, model, bridge, get sessions() { return sessions; }, helpers, inside, get critters() { return critters; }, get plants() { return plants; }, get flags() { return flags; }, ladders, setPhase, celebrateTask };
  requestAnimationFrame((ms) => { last = ms; frame(ms); });
}

start().catch((err) => { document.body.insertAdjacentHTML('beforeend', `<div class="err">Couldn't start the Terrarium: ${err.message}</div>`); });
