// Gremlets web habitat: the same creatures and engine as the Mac app, living in a browser tab.
// Works with mouse and touch. URL options:
//   ?g=flurrie,kindlet   start with these Gremlets
//   ?showcase=kindlet    single-Gremlet view with a nameplate (used as an NFT's live preview)
import { World, V } from './engine.js';
import { loadIndex, loadSpecies, speciesBase } from './sprites.js';
import { FX, Particles } from './effects.js';

const params = new URLSearchParams(location.search);
const showcase = params.get('showcase') || params.get('nft');
const MAX = 12;
const FAMILIES = [['animal', 'Animals'], ['insect', 'Insects & Bugs'], ['dragon', 'Dragons'], ['dino', 'Dinosaurs'], ['mythic', 'Mythical Beasts'], ['spirit', 'Spirits'], ['guardian', 'Guardians']];

const canvas = document.getElementById('world');
const ctx = canvas.getContext('2d');
const world = new World();
const particles = new Particles();
const art = new Map();          // creature id -> { image, rects }
const zzzTimers = new Map();
let W = 0, H = 0, DPR = 1, PX = 3, GROUND = 0, TOP = 0;
let platforms = [];
let scenery = null;
let index = [];

const hour = new Date().getHours();
const night = hour >= 20 || hour < 6;
const dusk = !night && (hour >= 18 || hour < 7);

// ---------------------------------------------------------------- layout & scenery

const toScreen = (x, y) => ({ x, y: H - y });
const toWorld = (e) => { const r = canvas.getBoundingClientRect(); return V(e.clientX - r.left, H - (e.clientY - r.top)); };

function choosePixelScale() {
  const m = Math.min(innerWidth, innerHeight);
  return showcase ? (m >= 360 ? 3 : 2) : (m < 600 ? 2 : 3);
}

function layout() {
  W = innerWidth; H = innerHeight; DPR = Math.min(devicePixelRatio || 1, 3);
  canvas.width = Math.round(W * DPR); canvas.height = Math.round(H * DPR);
  canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
  GROUND = PX * 9;
  TOP = showcase ? PX * 10 : 64;
  platforms = makePlatforms();
  world.setEnvironment([{ x: 0, y: GROUND, w: W, h: H - GROUND - TOP }], platforms);
  scenery = drawScenery();
}

/** Floating ledges to climb (the web stand-in for app windows). Spaced so every species can jump between them. */
function makePlatforms() {
  const usable = H - GROUND - TOP - 70;
  const rows = showcase ? 1 : Math.max(1, Math.min(4, Math.floor(usable / 140)));
  const kinds = ['shelf', 'moss', 'cloud'];
  const out = [];
  let id = 1;
  for (let r = 1; r <= rows; r++) {
    const y = GROUND + Math.round((usable * r) / (rows + 0.35));
    const perRow = W > 1000 ? 2 : 1;
    for (let i = 0; i < perRow; i++) {
      const w = Math.round(Math.min(Math.max(W * (perRow > 1 ? 0.2 : 0.42), 130), 320) / PX) * PX;
      const slot = perRow > 1 ? (i === 0 ? 0.08 : 0.58) : 0.08;
      const shift = (r % 2 === 0 ? 0.24 : 0) * W;
      const x = Math.round(Math.min(W - w - 12, slot * W + shift) / PX) * PX;
      out.push({ id: id++, x, y: y - PX * 4, w, h: PX * 4, kind: kinds[(r + i) % kinds.length] });
    }
  }
  return out;
}

function drawScenery() {
  const cv = document.createElement('canvas');
  cv.width = canvas.width; cv.height = canvas.height;
  const g = cv.getContext('2d');
  g.scale(DPR, DPR);
  g.imageSmoothingEnabled = false;

  // Sky.
  const sky = g.createLinearGradient(0, 0, 0, H);
  if (night) { sky.addColorStop(0, '#1d2347'); sky.addColorStop(1, '#3d3a6b'); }
  else if (dusk) { sky.addColorStop(0, '#7f8fd0'); sky.addColorStop(1, '#f6c2a0'); }
  else { sky.addColorStop(0, '#bfe0f2'); sky.addColorStop(1, '#f6eddd'); }
  g.fillStyle = sky; g.fillRect(0, 0, W, H);

  const rand = mulberry(7);
  if (night) {
    for (let i = 0; i < Math.round(W * H / 9000); i++) {
      g.fillStyle = rand() > 0.85 ? '#fff6c8' : '#cfd6ff';
      const s = rand() > 0.9 ? PX : PX / 2 | 0 || 1;
      g.fillRect(Math.round(rand() * W), Math.round(rand() * (H - GROUND - 40)), s, s);
    }
    pixelDisc(g, W * 0.82, H * 0.16, PX * 7, '#fff3c4', '#e8d79a');
  } else {
    for (let i = 0; i < Math.max(3, Math.round(W / 300)); i++) pixelCloud(g, rand() * W, 30 + rand() * H * 0.35, 0.7 + rand() * 0.8, 'rgba(255,255,255,0.75)');
  }

  // Distant hills.
  g.fillStyle = night ? '#2c3a5c' : dusk ? '#c49a9a' : '#cfe3c4';
  for (let x = 0; x < W; x += PX) {
    const h = GROUND + PX * 6 + Math.round((Math.sin(x / 140) * 10 + Math.sin(x / 57) * 5) / PX) * PX;
    g.fillRect(x, H - h, PX, h);
  }

  // Ground: grass strip with tufts over soil.
  const gy = H - GROUND;
  g.fillStyle = night ? '#3c5a3a' : '#7cc46a'; g.fillRect(0, gy, W, PX * 3);
  g.fillStyle = night ? '#2c4430' : '#5aa54e'; g.fillRect(0, gy + PX * 3, W, PX);
  g.fillStyle = night ? '#4a3a32' : '#a5774f'; g.fillRect(0, gy + PX * 4, W, GROUND - PX * 4);
  g.fillStyle = night ? '#3a2c26' : '#8a5f3e';
  for (let x = 0; x < W; x += PX * 7) g.fillRect(x + ((x / PX) % 3) * PX, gy + PX * 6 + ((x / PX) % 2) * PX * 2, PX, PX);
  g.fillStyle = night ? '#4f7a4a' : '#9ad884';
  for (let x = PX * 2; x < W; x += PX * 11) { g.fillRect(x, gy - PX, PX, PX); g.fillRect(x + PX * 2, gy - PX * 2, PX, PX * 2); }
  // Little flowers.
  for (let x = PX * 5; x < W; x += PX * 37) {
    g.fillStyle = ['#ff9ec4', '#ffe38a', '#a8d8ff'][(x / PX) % 3 | 0];
    g.fillRect(x, gy - PX * 2, PX, PX);
  }

  for (const p of platforms) drawPlatform(g, p);
  return cv;
}

function drawPlatform(g, p) {
  const top = H - (p.y + p.h), x = p.x, w = p.w;
  if (p.kind === 'shelf') {
    g.fillStyle = '#4a2e1a'; g.fillRect(x - PX, top - PX, w + PX * 2, p.h + PX * 2);
    g.fillStyle = '#b98552'; g.fillRect(x, top, w, p.h);
    g.fillStyle = '#d9a673'; g.fillRect(x, top, w, PX);
    g.fillStyle = '#8a5a34'; g.fillRect(x, top + p.h - PX, w, PX);
    for (const bx of [x + PX * 4, x + w - PX * 7]) {          // brackets
      g.fillStyle = '#4a2e1a';
      for (let k = 0; k < 5; k++) g.fillRect(bx, top + p.h + k * PX, PX * (5 - k), PX);
      g.fillStyle = '#c8c0b0'; g.fillRect(bx + PX, top + PX * 2, PX, PX);
    }
  } else if (p.kind === 'moss') {
    g.fillStyle = '#3a4048'; g.fillRect(x - PX, top - PX, w + PX * 2, p.h + PX * 3);
    g.fillStyle = '#9aa0a6'; g.fillRect(x, top, w, p.h + PX);
    g.fillStyle = '#7a8088'; g.fillRect(x, top + p.h, w, PX);
    g.fillStyle = '#6cbf59'; g.fillRect(x - PX, top - PX, w + PX * 2, PX * 2);
    g.fillStyle = '#4f9a44';
    for (let mx = x + PX * 2; mx < x + w - PX; mx += PX * 6) g.fillRect(mx, top + PX, PX, PX * (1 + ((mx / PX) % 3)));
    g.fillStyle = '#ff9ec4'; g.fillRect(x + PX * 5, top - PX * 2, PX, PX);
  } else {
    const cy = top + p.h / 2;
    for (let cx = x + PX * 3; cx < x + w - PX * 2; cx += PX * 6) pixelDisc(g, cx, cy, PX * 4, night ? '#c8d0ec' : '#ffffff', night ? '#9aa4cc' : '#dfe8f4');
  }
}

function pixelDisc(g, cx, cy, r, fill, shade) {
  for (let y = -r; y <= r; y += PX) for (let x = -r; x <= r; x += PX) {
    if (x * x + y * y > r * r) continue;
    g.fillStyle = y > r * 0.35 ? shade : fill;
    g.fillRect(Math.round((cx + x) / PX) * PX, Math.round((cy + y) / PX) * PX, PX, PX);
  }
}

function pixelCloud(g, cx, cy, s, color) {
  g.fillStyle = color;
  for (const [dx, dy, r] of [[0, 0, 14], [16, 3, 11], [-15, 4, 10], [6, -8, 10]]) {
    const R = r * s;
    for (let y = -R; y <= R; y += PX) for (let x = -R; x <= R; x += PX) {
      if (x * x + y * y <= R * R) g.fillRect(Math.round((cx + dx * s + x) / PX) * PX, Math.round((cy + dy * s + y) / PX) * PX, PX, PX);
    }
  }
}

function mulberry(seed) { let s = seed; return () => { s = (s + 0x6d2b79f5) >>> 0; let t = Math.imul(s ^ (s >>> 15), s | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

// ---------------------------------------------------------------- creatures

async function addGremlet(id, at) {
  if (world.creatures.length >= MAX) removeGremlet(world.creatures[0].id);
  const a = await loadSpecies(id, PX);
  const x = at?.x ?? (W * (0.15 + Math.random() * 0.7));
  const c = world.spawn(a.species, V(x, at?.y ?? H - TOP - a.species.size.y - 4));
  art.set(c.id, a);
  saveRoster();
  updateCount();
  return c;
}

function removeGremlet(id) { world.remove(id); art.delete(id); saveRoster(); updateCount(); }

function saveRoster() {
  if (showcase) return;
  try { localStorage.setItem('gremlets.roster', JSON.stringify(world.creatures.map((c) => c.species.id))); } catch { /* private mode */ }
}
function loadRoster() { try { return JSON.parse(localStorage.getItem('gremlets.roster') || 'null'); } catch { return null; } }

// ---------------------------------------------------------------- effects (same mapping as the Mac app)

const byId = (id) => world.creatures.find((c) => c.id === id);
const head = (c, k = 0.8) => V(c.pos.x, c.pos.y + c.size.y * k);

function handleEvents(events) {
  for (const e of events) {
    const c = byId(e.id ?? e.rider ?? e.a);
    if (!c) continue;
    switch (e.type) {
      case 'poked': particles.burst(FX.heart, head(c), { dy: [36, 46], duration: 1.3 }); break;
      case 'petted':
        particles.burst(FX.heart, head(c), { dx: [-16, -12], dy: [36, 46], duration: 1.3 });
        particles.burst(FX.smallHeart, head(c), { dx: [12, 18], dy: [30, 40], duration: 1.2, delay: 0.25 });
        break;
      case 'alert': case 'tagged': case 'startled': particles.burst(FX.bang, V(c.pos.x + c.facing * c.size.x * 0.18, c.pos.y + c.size.y * 0.8), { dy: [8, 12], duration: 0.8, spin: 0 }); break;
      case 'wokeUp': if (c.activity === 'wake') particles.burst(FX.bang, head(c), { dy: [8, 12], duration: 0.8, spin: 0 }); break;
      case 'dizzy': particles.orbit(() => V(c.pos.x, c.pos.y + c.size.y * 0.72)); break;
      case 'landed': if (e.impact > 650) dust(c, Math.min(1, e.impact / 2000)); break;
      case 'tookOff': dust(c, 0.3); break;
      case 'special': special(e.effect, c); break;
      case 'greet': { const b = byId(e.b); if (b) particles.burst(FX.heart, V((c.pos.x + b.pos.x) / 2, c.pos.y + c.size.y * 0.8), { dy: [30, 40], duration: 1.3 }); break; }
      case 'bump': { const b = byId(e.b); if (b) particles.burst(null, V((c.pos.x + b.pos.x) / 2, c.pos.y + c.size.y * 0.5), { imgs: [FX.smallStar, FX.star], count: 4, dx: [-26, 26], dy: [4, 26], duration: 0.6 }); break; }
      case 'stacked': particles.burst(FX.smallHeart, head(c), { dx: [8, 12], dy: [30, 40], duration: 1.2 }); break;
      case 'danceBeat': particles.burst(null, head(c, 0.75), { imgs: [FX.note, FX.note2], dx: [-26, 26], dy: [26, 42], duration: 1.1 }); break;
    }
  }
}

function dust(c, s) {
  for (const side of [-1, 1]) {
    particles.burst(FX.dust, V(c.pos.x + side * 10, c.pos.y + 4), { dx: side < 0 ? [-26 - 26 * s, -26] : [26, 26 + 26 * s], dy: [0, 8], duration: 0.45, spin: 0 });
  }
}

function special(effect, c) {
  const f = c.facing, d = 0.3;
  const mouth = V(c.pos.x + f * c.size.x * 0.22, c.pos.y + c.size.y * 0.42);
  const top = head(c, 0.75), mid = head(c, 0.45);
  const fwd = (a, b) => (f < 0 ? [-b, -a] : [a, b]);
  const o = (img, at, opts) => particles.burst(img, at, { delay: d, ...opts });
  switch (effect) {
    case 'fire': o(null, mouth, { imgs: [FX.flame, FX.flame2], count: 7, dx: fwd(45, 90), dy: [-4, 18], duration: 0.55, stagger: 0.05 }); break;
    case 'smoke': o(FX.smoke, mouth, { count: 5, dx: fwd(20, 50), dy: [10, 30], duration: 0.9, stagger: 0.06 }); break;
    case 'snow': o(FX.snow, V(top.x, top.y + 30), { count: 7, dx: [-45, 45], dy: [-60, -30], duration: 1.4, stagger: 0.07 }); break;
    case 'rain': o(FX.rain, V(top.x, top.y + 24), { count: 8, dx: [-22, 22], dy: [-70, -50], duration: 0.7, stagger: 0.06, spin: 0 }); break;
    case 'petals': o(FX.petal, top, { count: 7, dx: [-40, 40], dy: [20, 50], duration: 1.2, stagger: 0.04 }); break;
    case 'leaves': o(null, top, { imgs: [FX.leaf, FX.leaf2], count: 7, dx: [-40, 40], dy: [20, 50], duration: 1.2, stagger: 0.04 }); break;
    case 'seeds': o(FX.seed, top, { count: 7, dx: [-40, 40], dy: [20, 50], duration: 1.2, stagger: 0.04 }); break;
    case 'pollen': o(FX.pollen, top, { count: 7, dx: [-40, 40], dy: [20, 50], duration: 1.2, stagger: 0.04 }); break;
    case 'steam': o(FX.steam, top, { count: 4, dx: [-18, 18], dy: [30, 55], duration: 1.4, stagger: 0.18 }); break;
    case 'clouds': o(FX.cloud, top, { count: 4, dx: [-18, 18], dy: [30, 55], duration: 1.4, stagger: 0.18 }); break;
    case 'bubbles': o(FX.bubble, mouth, { count: 6, dx: [-20, 30], dy: [30, 60], duration: 1.3, stagger: 0.1 }); break;
    case 'notes': o(null, top, { imgs: [FX.note, FX.note2], count: 5, dx: [-30, 30], dy: [25, 50], duration: 1.3, stagger: 0.15 }); break;
    case 'ink': o(FX.ink, mid, { count: 6, dx: fwd(-50, -20), dy: [-6, 12], duration: 0.9, stagger: 0.03 }); break;
    case 'stomp': case 'bonk': case 'roar':
      setTimeout(() => { dust(c, 0.9); if (effect !== 'stomp') particles.burst(FX.bang, head(c), { dy: [8, 12], duration: 0.8, spin: 0 }); }, d * 1000);
      break;
    case 'bark':
      for (let i = 0; i < 3; i++) o(FX.smallBang, V(top.x + (i - 1) * 22, top.y + 8), { dy: [14, 22], duration: 0.6, delay: d + i * 0.18, spin: 0 });
      break;
    default: o(null, mid, { imgs: [FX.sparkle, FX.smallStar], count: 6, dx: [-40, 40], dy: [-10, 40], duration: 0.9, stagger: 0.06 });
  }
}

// ---------------------------------------------------------------- input (mouse + touch)

let press = null;
let lastHover = null;

canvas.addEventListener('pointerdown', (e) => {
  const p = toWorld(e), t = performance.now() / 1000;
  world.cursor = p;
  const c = world.creatureAt(p);
  if (!c) return;
  try { canvas.setPointerCapture(e.pointerId); } catch { /* synthetic or already-released pointer */ }
  press = { c, start: p, dragging: false, petted: false };
  // Hold still on a Gremlet to pet it (touch-friendly).
  press.holdTimer = setTimeout(() => {
    if (press && !press.dragging) { press.petted = true; press.petLoop = setInterval(() => world.pet(c, 120), 120); world.pet(c, 300); }
  }, 420);
  e.preventDefault();
});

canvas.addEventListener('pointermove', (e) => {
  const p = toWorld(e), t = performance.now() / 1000;
  if (e.pointerType === 'mouse' || press) world.cursor = p;
  if (press) {
    if (!press.dragging && Math.hypot(p.x - press.start.x, p.y - press.start.y) > 8 && !press.petted) {
      press.dragging = true;
      clearTimeout(press.holdTimer);
      world.beginDrag(press.c, press.start, t);
      canvas.classList.add('grabbing');
    }
    if (press.dragging) world.drag(press.c, p, t);
    return;
  }
  // Mouse: rubbing the cursor over a Gremlet pets it, like on the desktop.
  const c = world.creatureAt(p);
  canvas.classList.toggle('over', !!c);
  if (c && lastHover) world.pet(c, Math.hypot(p.x - lastHover.x, p.y - lastHover.y));
  lastHover = p;
});

function release(e) {
  if (!press) { if (e.pointerType !== 'mouse') world.cursor = null; return; }
  const t = performance.now() / 1000;
  clearTimeout(press.holdTimer); clearInterval(press.petLoop);
  if (press.dragging) { world.drag(press.c, toWorld(e), t); world.endDrag(press.c, t); }
  else if (!press.petted) world.poke(press.c);
  canvas.classList.remove('grabbing');
  press = null;
  if (e.pointerType !== 'mouse') world.cursor = null;
}
canvas.addEventListener('pointerup', release);
canvas.addEventListener('pointercancel', release);
canvas.addEventListener('pointerleave', (e) => { if (e.pointerType === 'mouse' && !press) { world.cursor = null; lastHover = null; } });

// ---------------------------------------------------------------- loop

let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  world.step(dt);
  handleEvents(world.drainEvents());
  for (const c of world.creatures) {
    if (c.activity !== 'sleep') continue;
    const t = (zzzTimers.get(c.id) || 0) - dt;
    if (t <= 0) { particles.burst(FX.zzz, head(c, 0.85), { dx: [14 * c.facing, 22 * c.facing], dy: [40, 48], duration: 1.4, spin: 0 }); zzzTimers.set(c.id, 1.6); }
    else zzzTimers.set(c.id, t);
  }
  particles.update(dt);
  draw();
  requestAnimationFrame(frame);
}

function draw() {
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(scenery, 0, 0, W, H);
  // Soft shadows under grounded Gremlets.
  ctx.fillStyle = night ? 'rgba(0,0,20,0.28)' : 'rgba(60,40,20,0.16)';
  for (const c of world.creatures) {
    if (!c.isGrounded) continue;
    const s = toScreen(c.pos.x, c.pos.y);
    ctx.beginPath(); ctx.ellipse(s.x, s.y - 1, c.size.x * 0.26, PX * 1.2, 0, 0, Math.PI * 2); ctx.fill();
  }
  for (const c of world.creatures) {
    const a = art.get(c.id);
    if (!a) continue;
    const r = a.rects[c.currentFrame];
    if (!r) continue;
    const w = r.w * PX, h = r.h * PX;
    const s = toScreen(c.pos.x, c.pos.y);
    ctx.save();
    ctx.translate(Math.round(s.x), Math.round(s.y));
    if (c.facing < 0) ctx.scale(-1, 1);
    ctx.drawImage(a.image, r.x, r.y, r.w, r.h, -w / 2, -h, w, h);
    ctx.restore();
  }
  particles.draw(ctx, toScreen, PX);
}

// ---------------------------------------------------------------- UI

function updateCount() {
  const el = document.getElementById('count');
  if (el) el.textContent = `${world.creatures.length} / ${MAX}`;
}

async function buildPicker() {
  const grid = document.getElementById('picker-grid');
  const b = await speciesBase();
  grid.innerHTML = '';
  for (const [fam, title] of FAMILIES) {
    const members = index.filter((s) => s.family === fam);
    if (!members.length) continue;
    const h = document.createElement('h3'); h.textContent = `${title} · ${members.length}`; grid.appendChild(h);
    const row = document.createElement('div'); row.className = 'row'; grid.appendChild(row);
    for (const s of members) {
      const btn = document.createElement('button');
      btn.className = 'pick'; btn.title = s.name;
      btn.innerHTML = `<span class="thumb" style="background-image:url('${b}${s.id}/sheet.png')"></span><span class="nm">${s.name}</span><span class="el">${s.element}</span>`;
      btn.addEventListener('click', () => { addGremlet(s.id); closePicker(); });
      row.appendChild(btn);
    }
  }
}
function openPicker() { document.getElementById('picker').hidden = false; }
function closePicker() { document.getElementById('picker').hidden = true; }

async function start() {
  PX = choosePixelScale();
  document.documentElement.style.setProperty('--px', PX);
  document.body.classList.toggle('night', night);
  layout();
  index = await loadIndex();

  if (showcase) {
    document.body.classList.add('showcase');
    const info = index.find((s) => s.id === showcase) || index[0];
    const c = await addGremlet(info.id, V(W / 2, GROUND + 4));
    const plate = document.getElementById('plate');
    plate.innerHTML = `<b>${c.species.name}</b> <span>${c.species.element} · ${c.species.family}</span><p>${c.species.description}</p>`;
    plate.hidden = false;
  } else {
    const wanted = (params.get('g') || '').split(',').filter((id) => index.some((s) => s.id === id));
    let ids = wanted.length ? wanted : loadRoster()?.filter((id) => index.some((s) => s.id === id));
    if (!ids || !ids.length) {
      const n = Math.min(innerWidth, innerHeight) < 600 ? 4 : 6;
      const rest = index.map((s) => s.id).filter((id) => !['flurrie', 'kindlet', 'dandelet'].includes(id)).sort(() => Math.random() - 0.5);
      ids = ['flurrie', 'kindlet', 'dandelet', ...rest].slice(0, n);
    }
    await Promise.all(ids.slice(0, MAX).map((id, i) => addGremlet(id, V(W * (0.12 + 0.76 * (i + 0.5) / ids.length), H - TOP - 120 - (i % 3) * 30))));
    buildPicker();
    document.getElementById('add').addEventListener('click', openPicker);
    document.getElementById('close').addEventListener('click', closePicker);
    document.getElementById('picker').addEventListener('click', (e) => { if (e.target.id === 'picker') closePicker(); });
    document.getElementById('party').addEventListener('click', async () => {
      for (const c of [...world.creatures]) removeGremlet(c.id);
      const picks = index.map((s) => s.id).sort(() => Math.random() - 0.5).slice(0, Math.min(innerWidth, innerHeight) < 600 ? 5 : 8);
      for (const id of picks) addGremlet(id);
    });
    setTimeout(() => document.getElementById('hint')?.classList.add('gone'), 7000);
  }
  if (params.has('debug')) window.gremlets = { world, toScreen, particles };
  requestAnimationFrame((t) => { last = t; frame(t); });
}

addEventListener('resize', () => { layout(); });
document.addEventListener('visibilitychange', () => { last = performance.now(); });
start().catch((err) => {
  document.body.insertAdjacentHTML('beforeend', `<div class="err">Couldn't load the Gremlets: ${err.message}</div>`);
});
