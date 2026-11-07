// Gremlets web habitat: the same creatures and engine as the Mac app, living in a browser tab.
// Works with mouse and touch. URL options:
//   ?g=flurrie,kindlet   start with these Gremlets
//   ?showcase=kindlet    single-Gremlet view with a nameplate (used as an NFT's live preview)
import { World, V } from './engine.js';
import { loadIndex, loadSpecies, speciesBase } from './sprites.js';
import { FX, Particles } from './effects.js';
import { Link } from './link.js';
import { Garden } from './garden.js';
import { Bridge } from './bridge.js';
import { IslandArt, Biome, ledgeBiome, ledgeSeed } from './islands.js';
import { Bonsai, layoutBonsai, renderBonsai, MAX_BRANCHES } from './bonsai.js';
import { hex, PixelCanvas } from './pixelart.js';

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
const link = showcase ? null : new Link();
const bridge = showcase ? null : new Bridge();
const DOOR = 120;               // how far the floor runs past a linked edge before a Gremlet is "through"
let door = null;                // 'left' | 'right' when another screen is linked and open
let driven = null;              // creature id steered with the keyboard (or the on-screen pad)
let remoteDrive = false;        // our driven Gremlet walked to the other screen: forward the keys there
let drivenByPeer = false;       // the Gremlet we're showing is being steered from the other screen
const keys = { left: false, right: false, up: false };
const travellers = [];          // rain clouds drifting across: { x, y, dir, speed, art, t }
let cloudArt = null;
const visitors = new Map();     // creature id -> { species, garden, spot, poseTimer, hop }
const portals = [];             // { x, y, t }
let tilt = 0;                   // -1 (phone tipped left) ... 1 (right)
let tiltAsked = false;
const bubbles = [];             // { el, id, until }
let W = 0, H = 0, DPR = 1, PX = 3, GROUND = 0, TOP = 0;
let platforms = [];
let scenery = null;
let index = [];

const hour = new Date().getHours();
const night = hour >= 20 || hour < 6;
const dusk = !night && (hour >= 18 || hour < 7);
const MONTH = Math.min(12, Math.max(1, +params.get('month') || new Date().getMonth() + 1));   // ?month=1 previews a season

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
  placeBonsai();
  applyDoor();
  scenery = drawScenery();
}

/** The habitat's screen, stretched past a linked edge so Gremlets can walk out through it. */
function applyDoor() {
  door = bridge?.linked && bridge.peerOnline ? bridge.side : null;
  const x = door === 'left' ? -DOOR : 0, w = W + (door ? DOOR : 0);
  if (bonsai && isleGone()) placeBonsai();
  // The ledges and the bonsai's foliage pads are the "windows": the engine makes their top edges one-way platforms.
  world.setEnvironment([{ x, y: GROUND, w, h: H - GROUND - TOP }], [...platforms.filter((p) => !p.broken), ...bonsaiPlatforms()]);
}

/** Floating ledges to climb (the web stand-in for app windows), each a biome island. Spaced so every species can jump between them. */
function makePlatforms() {
  const usable = H - GROUND - TOP - 70;
  const rows = showcase ? 1 : Math.max(1, Math.min(4, Math.floor(usable / 140)));
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
      out.push({ id, x, y: y - PX * 4, w, h: PX * 4, seed: ledgeSeed(id), biome: ledgeBiome(id, MONTH) });
      id++;
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

  for (const p of platforms) if (!p.broken) drawPlatform(g, p);
  return cv;
}

const islandArt = new Map();     // `${biome}-${widthPx}-${seed}-${night}` → { body, decor } 1:1 canvases

function islandImages(p) {
  const wpx = Math.max(8, Math.round(p.w / PX)), key = `${p.biome}-${wpx}-${p.seed}-${night}`;
  let a = islandArt.get(key);
  if (!a) {
    a = { body: IslandArt.body(p.biome, wpx, p.seed).toCanvas(), decor: IslandArt.decor(p.biome, wpx, p.seed, night).toCanvas() };
    islandArt.set(key, a);
  }
  return a;
}

/** A floating biome island. The body's top row is the platform's walking surface (so the geometry Gremlets stand on is
 *  unchanged); the terrain hangs below it and the decor grows above. The landmark stands at the outer end, nearest the
 *  screen edge, so islands on the left are mirrored. */
function drawPlatform(g, p) {
  const top = H - (p.y + p.h), a = islandImages(p), flip = p.x + p.w / 2 < W / 2;
  g.save();
  g.translate(flip ? p.x + p.w : p.x, 0);
  if (flip) g.scale(-1, 1);
  g.drawImage(a.decor, 0, top - a.decor.height * PX, a.decor.width * PX, a.decor.height * PX);
  g.drawImage(a.body, 0, top, a.body.width * PX, a.body.height * PX);
  g.restore();
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
  // Visitors from the Mac are saved separately (they go home again).
  try { localStorage.setItem('gremlets.roster', JSON.stringify(world.creatures.filter((c) => !visitors.has(c.id)).map((c) => c.species.id))); } catch { /* private mode */ }
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
let lastTap = null;

canvas.addEventListener('pointerdown', (e) => {
  askForTilt();
  const p = toWorld(e), t = performance.now() / 1000;
  world.cursor = p;
  const c = world.creatureAt(p);
  if (!c) { tapGarden(p); return; }
  const now2 = performance.now();
  if (lastTap && lastTap.id === c.id && now2 - lastTap.t < 320) { lastTap = null; takeControl(c); e.preventDefault(); return; }
  lastTap = { id: c.id, t: now2 };
  if (visitors.has(c.id)) say(c.id, visitors.get(c.id).garden.describe(), 3.5);
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
  steer(dt);
  world.step(dt);
  handleEvents(world.drainEvents());
  checkCrossings(now / 1000);
  updateTravellers(dt, now / 1000);
  updateFerry(dt, now / 1000);
  updateBoss(dt);
  updateDebris(dt);
  updateSession(now / 1000);
  updateMinions(now / 1000);
  respawnPlatforms(now / 1000);
  for (const c of world.creatures) {
    if (c.activity !== 'sleep') continue;
    const t = (zzzTimers.get(c.id) || 0) - dt;
    if (t <= 0) { particles.burst(FX.zzz, head(c, 0.85), { dx: [14 * c.facing, 22 * c.facing], dy: [40, 48], duration: 1.4, spin: 0 }); zzzTimers.set(c.id, 1.6); }
    else zzzTimers.set(c.id, t);
  }
  updateVisitors(dt, now / 1000);
  applyTilt(dt);
  particles.update(dt);
  draw();
  drawPortals(now / 1000);
  drawDoor(now / 1000);
  drawTravellers(now / 1000);
  drawFerry(now / 1000);
  drawAdventure(now / 1000);
  drawDriveMarker(now / 1000);
  placeBubbles(now / 1000);
  requestAnimationFrame(frame);
}

function draw() {
  const shake = performance.now() / 1000 < shakeUntil ? PX * 1.5 : 0;
  ctx.setTransform(DPR, 0, 0, DPR, (Math.random() - 0.5) * shake * DPR, (Math.random() - 0.5) * shake * DPR);
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(scenery, 0, 0, W, H);
  // Soft shadows under grounded Gremlets.
  ctx.fillStyle = night ? 'rgba(0,0,20,0.28)' : 'rgba(60,40,20,0.16)';
  for (const c of world.creatures) {
    if (!c.isGrounded) continue;
    const s = toScreen(c.pos.x, c.pos.y);
    ctx.beginPath(); ctx.ellipse(s.x, s.y - 1, c.size.x * 0.26, PX * 1.2, 0, 0, Math.PI * 2); ctx.fill();
  }
  for (const [, v] of visitors) {
    const s = toScreen(v.spot.boxX, v.spot.y);
    v.garden.draw(ctx, s.x, s.y, PX);
  }
  drawBonsai(performance.now() / 1000);   // behind the Gremlets, so the ones on its pads stand in front
  for (const c of world.creatures) {
    const a = art.get(c.id);
    if (!a) continue;
    if (c.id === driven && performance.now() / 1000 < life.hurtUntil && Math.floor(performance.now() / 90) % 2) continue;   // blink while hurt
    const r = a.rects[c.boosting ? c.species.frame('fly', c.animTime) : c.currentFrame];
    if (!r) continue;
    const w = r.w * PX, h = r.h * PX;
    const s = toScreen(c.pos.x, c.pos.y);
    ctx.save();
    ctx.translate(Math.round(s.x), Math.round(s.y));
    if (c.facing < 0) ctx.scale(-1, 1);
    ctx.drawImage(a.image, r.x, r.y, r.w, r.h, -w / 2, -h, w, h);
    ctx.restore();
  }
  drawMinions(performance.now() / 1000);
  particles.draw(ctx, toScreen, PX);
}

// ---------------------------------------------------------------- tilt (phones): tip it and they slide

function onOrientation(e) {
  const angle = (screen.orientation && screen.orientation.angle) || window.orientation || 0;
  let side = e.gamma ?? 0;                                   // portrait: left-right tilt
  if (angle === 90) side = -(e.beta ?? 0);
  else if (angle === -90 || angle === 270) side = e.beta ?? 0;
  else if (angle === 180) side = -side;
  const t = Math.max(-1, Math.min(1, side / 40));
  tilt = Math.abs(t) < 0.12 ? 0 : t;                         // a little dead zone so they don't drift when held level
}

/** iPhones only share motion after a tap, so ask on the first one. */
function askForTilt() {
  if (tiltAsked || showcase) return;
  tiltAsked = true;
  const D = window.DeviceOrientationEvent;
  if (!D) return;
  if (typeof D.requestPermission === 'function') {
    D.requestPermission().then((r) => { if (r === 'granted') addEventListener('deviceorientation', onOrientation); }).catch(() => {});
  } else {
    addEventListener('deviceorientation', onOrientation);
  }
}

function applyTilt(dt) {
  if (!tilt) return;
  for (const c of world.creatures) {
    if (c.activity === 'airborne') c.vel = V(c.vel.x + tilt * 900 * dt, c.vel.y);
    else if (c.isGrounded && c.activity !== 'dragged' && !visitors.has(c.id) && Math.abs(tilt) > 0.45 && Math.random() < dt * 1.2 * Math.abs(tilt)) {
      // Tipped far enough: whoops, off they tumble downhill.
      c.ground = null;
      c.vel = V(tilt * 380, 160);
      c.facing = tilt > 0 ? 1 : -1;
      c.set('airborne');
    }
  }
}

// ---------------------------------------------------------------- phone link: visitors from the Mac

const VKEY = 'gremlets.visitors';
function saveVisitors() {
  try { localStorage.setItem(VKEY, JSON.stringify([...visitors.values()].map((v) => ({ species: v.species, harvest: v.garden.harvested })))); } catch { /* private mode */ }
}
function loadVisitors() { try { return JSON.parse(localStorage.getItem(VKEY) || '[]'); } catch { return []; } }

/** Where a visitor gardens: its own ledge (widest free one), or the ground. World coordinates. */
function gardenSpot() {
  const need = 38 * PX + 70;
  const taken = new Set([...visitors.values()].map((v) => v.spot.key));
  const ledge = [...platforms].filter((p) => p.w >= need && !taken.has('p' + p.id)).sort((a, b) => b.w - a.w)[0];
  if (ledge) return { key: 'p' + ledge.id, y: ledge.y + ledge.h, boxX: ledge.x + 19 * PX + 6, standX: ledge.x + 38 * PX + 40, ground: false };
  const n = taken.size;
  const boxX = Math.min(W - 60, W * 0.22 + n * (38 * PX + 90));
  return { key: 'g' + n, y: GROUND, boxX, standX: boxX + 19 * PX + 34, ground: true };
}

async function arrive(species, harvest = [], quiet = false) {
  if (!index.some((s) => s.id === species)) return;
  const spot = gardenSpot();
  portals.push({ x: spot.standX, y: spot.y + 40, t: performance.now() / 1000 });
  await new Promise((r) => setTimeout(r, quiet ? 0 : 600));
  const c = await addGremlet(species, V(spot.standX, spot.y + 30));
  const garden = new Garden();
  garden.harvested = harvest;
  visitors.set(c.id, { species, garden, spot, poseTimer: 0, hop: 0 });
  saveVisitors();
  saveRoster();
  updateLinkUI();
  if (!quiet) setTimeout(() => say(c.id, 'Hi! I hopped over from your Mac ✨', 4), 700);
}

/** Keeps each visitor at its window box, tending it; the garden grows while it does. */
function updateVisitors(dt, t) {
  for (const [id, v] of visitors) {
    const c = byId(id);
    if (!c) { visitors.delete(id); saveVisitors(); updateLinkUI(); continue; }
    const there = c.isGrounded && Math.abs(c.pos.y - v.spot.y) < 3 && Math.abs(c.pos.x - v.spot.standX) < 14;
    const event = v.garden.update(dt, there, t);
    if (event) gardenFx(v, event);
    if (event === 'harvest') { say(id, v.garden.msg, 5); saveVisitors(); }
    if (c.activity === 'dragged' || !c.isGrounded) continue;
    if (there) {
      if ((v.poseTimer -= dt) <= 0 || c.activity !== 'idle') {
        v.poseTimer = 1.8 + Math.random() * 1.4;
        c.set('idle', 30);
        c.idleVariant = ['crouch', 'crouch', 'look', 'pet'][Math.floor(Math.random() * 4)];
        c.facing = v.spot.boxX < c.pos.x ? -1 : 1;
      }
    } else if (['idle', 'walk', 'follow', 'wave', 'peek', 'chase', 'land'].includes(c.activity) && t > v.hop) {
      // Hop back to the box.
      v.hop = t + 2.5;
      world.launch(c, world.ballistic(c.pos, v.spot.standX, v.spot.y, 40));
    }
  }
}

function gardenFx(v, event) {
  const top = V(v.spot.boxX, v.spot.y + PX * 20);
  if (event === 'water') particles.burst(FX.rain, top, { count: 6, dx: [-30, 30], dy: [-40, -20], duration: 0.6, stagger: 0.06, spin: 0 });
  else if (event === 'plant') particles.burst(FX.dust, V(v.spot.boxX, v.spot.y + PX * 6), { count: 3, dx: [-20, 20], dy: [0, 8], duration: 0.45, spin: 0 });
  else if (event === 'shoo') particles.burst(FX.smallBang, top, { dy: [10, 16], duration: 0.6, spin: 0 });
  else if (event === 'harvest') particles.burst(null, top, { imgs: [FX.sparkle, FX.heart, FX.smallStar, FX.petal], count: 12, dx: [-60, 60], dy: [10, 60], duration: 1.4, stagger: 0.05 });
}

function tapGarden(p) {
  for (const [id, v] of visitors) {
    const halfW = 19 * PX + 6;
    if (Math.abs(p.x - v.spot.boxX) < halfW && p.y > v.spot.y - 4 && p.y < v.spot.y + PX * 22) {
      const did = v.garden.help();
      if (did) { gardenFx(v, did); particles.burst(FX.smallHeart, V(v.spot.boxX, v.spot.y + PX * 18), { dy: [20, 30], duration: 0.9 }); }
      say(id, v.garden.describe(), 3);
      return true;
    }
  }
  return false;
}

async function sendHome() {
  const btn = document.getElementById('home');
  btn.disabled = true;
  for (const [id, v] of [...visitors]) {
    const c = byId(id);
    try {
      await link.sendHome(v.species, v.garden.harvested);
    } catch (err) {
      if (c) say(id, "Couldn't reach your Mac. Try again in a moment.", 4);
      continue;
    }
    if (c) { say(id, 'Bye! See you on the Mac 💻', 1.4); portals.push({ x: c.pos.x, y: c.pos.y + c.size.y * 0.45, t: performance.now() / 1000 }); }
    visitors.delete(id);
    setTimeout(() => removeGremlet(id), 700);
  }
  saveVisitors();
  btn.disabled = false;
  updateLinkUI();
}

function drawPortals(t) {
  for (let i = portals.length - 1; i >= 0; i--) {
    const p = portals[i], age = t - p.t;
    if (age > 1.6) { portals.splice(i, 1); continue; }
    const k = age < 0.3 ? age / 0.3 : age > 1.3 ? (1.6 - age) / 0.3 : 1;
    const s = toScreen(p.x, p.y);
    ctx.save();
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ['#a98bea', '#6fb8f0', '#ff8fbf'].forEach((col, j) => {
      const r = (40 - j * 10) * k;
      ctx.strokeStyle = col; ctx.lineWidth = 4;
      ctx.setLineDash([9, 6]); ctx.lineDashOffset = (j % 2 ? 1 : -1) * age * 60;
      ctx.beginPath(); ctx.ellipse(s.x, s.y, Math.max(1, r), Math.max(1, r * 1.3), 0, 0, Math.PI * 2); ctx.stroke();
    });
    ctx.restore();
  }
}

function say(id, text, secs) {
  const host = document.getElementById('bubbles');
  if (!host || !text) return;
  for (const b of bubbles.filter((b) => b.id === id)) { b.el.remove(); bubbles.splice(bubbles.indexOf(b), 1); }
  const el = document.createElement('div');
  el.className = 'say'; el.textContent = text;
  host.appendChild(el);
  bubbles.push({ el, id, until: performance.now() / 1000 + secs });
}
function placeBubbles(t) {
  for (let i = bubbles.length - 1; i >= 0; i--) {
    const b = bubbles[i], c = byId(b.id);
    if (!c || t > b.until) { b.el.remove(); bubbles.splice(i, 1); continue; }
    const s = toScreen(c.pos.x, c.pos.y + c.size.y + 8);
    b.el.style.left = Math.round(Math.min(W - 40, Math.max(40, s.x))) + 'px';
    b.el.style.top = Math.round(s.y) + 'px';
  }
}

function updateLinkUI() {
  if (!link) return;
  const chip = document.getElementById('linkchip'), home = document.getElementById('home');
  chip.hidden = !link.paired;
  chip.textContent = link.connected ? '📱 Linked' : '📱 Connecting…';
  chip.classList.toggle('off', !link.connected);
  home.hidden = !link.paired || visitors.size === 0;
}

// ---------------------------------------------------------------- screen bridge: walk off one screen, onto the next

const clamp01 = (v) => Math.max(0, Math.min(1, v));
const usableH = () => Math.max(1, H - GROUND - TOP);
const inward = () => (bridge?.side === 'right' ? -1 : 1);

function checkCrossings(t) {
  if (!bridge) return;
  for (const c of [...world.creatures]) {
    if (visitors.has(c.id) || c.activity === 'dragged') continue;
    // How far past the linked edge it is (negative while still on this screen).
    const out = door === 'right' ? c.pos.x - W : door === 'left' ? -c.pos.x : -Infinity;
    if (door && c.isGrounded && c.id !== driven && out > -c.size.x * 0.25 && c.facing !== inward()) {
      // A Gremlet wandering into the doorway thinks twice, so a screen doesn't empty itself. Just-arrived ones turn back.
      if (c.doorChoice == null) c.doorChoice = t - (c.arrived ?? -99) > 10 && Math.random() < 0.3;
      if (!c.doorChoice) c.facing = inward();
    } else if (out < -c.size.x * 1.5) c.doorChoice = null;
    const outward = c.isGrounded || c.activity === 'crouch' ? c.facing !== inward() : c.vel.x * inward() < 0;
    if (door && out > c.size.x * 0.35 && outward) leave(c);
  }
}

function leave(c) {
  const wasDriven = c.id === driven;
  bridge.cross({
    type: 'walk', species: c.species.id, y: clamp01((c.pos.y - GROUND) / usableH()),
    vx: Math.round(c.vel.x), vy: Math.round(c.vel.y), air: !c.isGrounded, drive: wasDriven,
  });
  particles.burst(null, V(door === 'right' ? W - 14 : 14, c.pos.y + c.size.y * 0.5), { imgs: [FX.sparkle, FX.smallStar], count: 6, dx: [-30, 30], dy: [-20, 40], duration: 0.8, stagger: 0.04 });
  if (wasDriven) { driven = null; remoteDrive = !drivenByPeer; drivenByPeer = false; updateDriveUI(); }
  zzzTimers.delete(c.id);
  removeGremlet(c.id);
}

async function arriveThroughDoor(note) {
  if (!index.some((s) => s.id === note.species)) return;
  if (!door) applyDoor();
  const a = await loadSpecies(note.species, PX);
  const half = a.species.size.x * 0.4, dir = inward();
  const x = bridge.side === 'right' ? W + half : -half;
  const air = !!note.air;
  const y = air ? GROUND + clamp01(note.y) * usableH() : GROUND;
  const c = await addGremlet(note.species, V(x, y));
  c.facing = dir; c.arrived = performance.now() / 1000; c.doorChoice = false;
  if (air) { c.vel = V(Math.max(160, Math.abs(note.vx || 0)) * dir, note.vy || 120); c.set('airborne'); }
  else { c.ground = -1; c.edgeDecided = false; c.set('walk', 2.2 + Math.random()); }
  particles.burst(null, V(bridge.side === 'right' ? W - 14 : 14, y + c.size.y * 0.5), { imgs: [FX.sparkle, FX.smallStar], count: 6, dx: [-30, 30], dy: [-20, 40], duration: 0.8, stagger: 0.04 });
  if (note.drive) {
    driven = c.id; drivenByPeer = !remoteDrive; remoteDrive = false;
    c.autoWalk = performance.now() / 1000 + 0.9;      // step fully onto this screen before waiting for keys
    updateDriveUI();
  }
  if (Math.random() < 0.6) setTimeout(() => say(c.id, ['Made it! ✨', 'Hello, other screen!', 'Whoa, new screen!', 'I walked here!'][Math.floor(Math.random() * 4)], 2.4), 500);
}

function drawDoor(t) {
  if (!door) return;
  const x = door === 'right' ? W - 3 : 3, top = H - GROUND - 150, bottom = H - GROUND;
  ctx.save();
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  const g = ctx.createLinearGradient(0, top, 0, bottom);
  g.addColorStop(0, 'rgba(169,139,234,0)'); g.addColorStop(1, 'rgba(169,139,234,0.55)');
  ctx.fillStyle = g;
  ctx.fillRect(door === 'right' ? W - 26 : 0, top, 26, bottom - top);
  ctx.strokeStyle = '#a98bea'; ctx.lineWidth = 3; ctx.setLineDash([8, 6]); ctx.lineDashOffset = -t * 40;
  ctx.beginPath(); ctx.moveTo(x, top + 20); ctx.lineTo(x, bottom); ctx.stroke();
  ctx.restore();
}

// ---------------------------------------------------------------- travelling rain cloud (crosses linked screens too)

async function summonCloud(fromSide = null, y = null) {
  if (travellers.length >= 2) return;
  if (!cloudArt) cloudArt = await loadSpecies('puffcloud', PX).catch(() => null);
  if (!cloudArt) return;
  const dir = fromSide === 'left' ? 1 : fromSide === 'right' ? -1 : Math.random() < 0.5 ? 1 : -1;
  const s = PX * 3, w = 32 * s;
  travellers.push({
    x: dir > 0 ? -w * 0.5 : W + w * 0.5, y: y ?? GROUND + usableH() * 0.66, dir, speed: 70 + Math.random() * 30,
    s, w, rainT: 0, touched: new Set(), t0: performance.now() / 1000,
  });
}

function updateTravellers(dt, t) {
  for (let i = travellers.length - 1; i >= 0; i--) {
    const v = travellers[i];
    v.x += v.dir * v.speed * dt;
    v.rainT -= dt;
    const bottom = v.y - v.w * 0.25;
    if (v.rainT <= 0) {
      v.rainT = 0.045;
      const fall = bottom - GROUND;
      particles.burst(FX.rain, V(v.x + (Math.random() - 0.5) * v.w * 0.6, bottom), { dy: [-fall, -fall + 6], dx: [-6, 6], duration: Math.max(0.3, fall / 520), spin: 0 });
    }
    for (const c of world.creatures) {
      if (v.touched.has(c.id) || !c.isGrounded || c.isAsleep || c.id === driven || visitors.has(c.id)) continue;
      if (Math.abs(c.pos.x - v.x) > v.w * 0.35) continue;
      v.touched.add(c.id);
      c.facing = v.x > c.pos.x ? 1 : -1;
      if (Math.random() < 0.6) world.startDance(c, 2.6, false);
      else world.poke(c);
    }
    const gone = v.dir > 0 ? v.x - v.w * 0.5 > W : v.x + v.w * 0.5 < 0;
    if (gone) {
      const through = v.dir > 0 ? 'right' : 'left';
      if (door === through) bridge.cross({ type: 'visitor', kind: 'raincloud', y: clamp01((v.y - GROUND) / usableH()) });
      travellers.splice(i, 1);
    }
  }
}

function drawTravellers(t) {
  if (!cloudArt) return;
  for (const v of travellers) {
    const f = cloudArt.species.frame('idle', t - v.t0), r = cloudArt.rects[f];
    if (!r) continue;
    const w = r.w * v.s, h = r.h * v.s, s = toScreen(v.x, v.y);
    ctx.save();
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.imageSmoothingEnabled = false;
    ctx.translate(Math.round(s.x), Math.round(s.y + Math.sin(t * 2) * 4));
    if (v.dir < 0) ctx.scale(-1, 1);
    ctx.drawImage(cloudArt.image, r.x, r.y, r.w, r.h, -w / 2, -h / 2, w, h);
    ctx.restore();
  }
}

// ---------------------------------------------------------------- the sky ferry (sails over from the Mac and back)
//
// The Mac's sky ferry leaves through the doorway with its passengers. Here it sails in at the height it left, stops
// a while so they hop off, lets a couple of Gremlets from this screen climb aboard, and sails back to the Mac.
// The same leaf boat and dandelion as IslandArt.ferry on the Mac (a straight port of the pixel drawing).

let ferry = null;      // { x, y, dir, phase: 'in'|'docked'|'out', targetX, until, pass: [{ species, art }], boarding: Map(id -> deadline), t0 }
const ferryFrames = [];
function ferryImage(frame) {
  if (ferryFrames[frame]) return ferryFrames[frame];
  const cv = new PixelCanvas(44, 34);
  // A big curled leaf for a boat, carried by a huge dandelion puff (same as the Mac's).
  const cx = 22, cy = 25;
  for (let n = 0; n < 26; n++) {
    const a = n / 26 * 2 * Math.PI + (frame % 2 === 0 ? 0 : 0.12), r = n % 2 === 0 ? 8.6 : 7.4;
    cv.line(cx, cy, cx + Math.cos(a) * r, cy + Math.sin(a) * r * 0.9, 0xEDEDE4);
    cv.set(Math.trunc(cx + Math.cos(a) * r), Math.trunc(cy + Math.sin(a) * r * 0.9), 0xFFFFFF);
  }
  cv.blob(cx, cy, 2, 2, 0xC9B79C, 0xE0D2B8);
  cv.line(cx, cy - 2, cx, 10, 0x6CC04A);
  cv.line(cx - 1, 16, 7, 9, 0xD8D4C8); cv.line(cx + 1, 16, 37, 9, 0xD8D4C8);
  for (let x = 2; x < 42; x++) {
    const t = (x - 2) / 39, curl = Math.round(Math.pow(Math.abs(t - 0.5) * 2, 3) * 5), depth = Math.max(2, Math.round(Math.sin(t * Math.PI) * 5));
    for (let y = 0; y < depth; y++) cv.set(x, 3 + curl + y - (depth - 1) + 3, y === depth - 1 ? 0x8BD66A : (y === 0 ? 0x3E7A34 : 0x5E9E46));
  }
  for (let x = 5; x <= 38; x++) cv.set(x, 8, 0x8BD66A);
  for (let x = 8; x < 38; x += 6) { cv.set(x, 6, 0x3E7A34); cv.set(x + 1, 5, 0x3E7A34); }
  for (let x = 6; x <= 37; x++) cv.set(x, 7, 0x6CC04A);
  cv.outline(0.6);
  ferryFrames[frame] = cv.toCanvas();
  return ferryFrames[frame];
}
const ferryDeck = () => ferry.y + 9 * PX;     // the deck is 9 art pixels above the hull's bottom
const ferryHalf = () => 22 * PX;

async function ferryArrives(note) {
  const riders = (Array.isArray(note.riders) ? note.riders : []).filter((s) => typeof s === 'string' && index.some((i) => i.id === s)).slice(0, 3);
  if (ferry) { for (const s of riders) arriveThroughDoor({ species: s, y: 0 }); return; }
  if (!door) applyDoor();
  const dir = inward();
  const y = Math.max(GROUND + 70, Math.min(H - TOP - 200, GROUND + clamp01(+note.y || 0.5) * usableH()));
  const pass = [];
  for (const s of riders) pass.push({ species: s, art: await loadSpecies(s, PX).catch(() => null) });
  ferry = {
    x: bridge.side === 'right' ? W + ferryHalf() : -ferryHalf(), y, dir, phase: 'in',
    targetX: W * (dir > 0 ? 0.36 : 0.64), until: 0, pass: pass.filter((p) => p.art), boarding: new Map(), t0: performance.now() / 1000,
  };
}

function updateFerry(dt, t) {
  if (!ferry) return;
  const f = ferry;
  if (f.phase === 'in') {
    const d = f.targetX - f.x;
    f.x += Math.sign(d) * Math.min(Math.abs(d), 150 * dt);
    if (Math.abs(d) < 2) {
      f.phase = 'docked'; f.until = t + 11;
      // Passengers hop off onto this screen.
      const off = f.pass.splice(0);
      off.forEach((p, i) => setTimeout(async () => {
        if (!ferry) return;
        const c = await addGremlet(p.species, V(ferry.x + (i - 1) * 26, ferryDeck()));
        c.facing = ferry.dir; c.arrived = performance.now() / 1000; c.cameByFerry = c.arrived; c.doorChoice = false;
        c.vel = V(ferry.dir * (60 + Math.random() * 90), 300); c.set('airborne');
        if (i === 0) setTimeout(() => say(c.id, ['Made it! ⛵️', 'Hello, other screen!', 'What a ride!'][Math.floor(Math.random() * 3)], 2.4), 700);
      }, 400 + i * 450));
    }
  } else if (f.phase === 'docked') {
    // A few seconds in, up to two Gremlets from here jump aboard (never one that only just arrived).
    if (t > f.until - 7 && f.boarding.size + f.pass.length < 2 && Math.random() < dt * 0.8) {
      const c = world.creatures.filter((o) => o.isGrounded && !o.isAsleep && o.id !== driven && !visitors.has(o.id) && !f.boarding.has(o.id)
        && t - (o.cameByFerry ?? -999) > 90 && Math.abs(o.pos.x - f.x) < 420 && ferryDeck() - o.pos.y < 320 && ferryDeck() > o.pos.y)
        .sort((a, b) => Math.abs(a.pos.x - f.x) - Math.abs(b.pos.x - f.x))[0];
      if (c && door) { f.boarding.set(c.id, t + 4); world.launch(c, world.ballistic(c.pos, f.x + (Math.random() - 0.5) * 30, ferryDeck(), 40)); }
    }
    if (t > f.until) {
      f.phase = 'out';
      // The other screen closed meanwhile: anyone aboard hops back off here.
      if (!door) for (const p of f.pass.splice(0)) addGremlet(p.species, V(f.x, ferryDeck())).then((c) => { c.vel = V(-f.dir * 100, 280); c.set('airborne'); });
    }
  } else {
    f.x -= f.dir * 165 * dt;
    if (f.dir > 0 ? f.x < -ferryHalf() : f.x > W + ferryHalf()) {
      const through = f.dir > 0 ? 'left' : 'right';
      if (door === through) bridge.cross({ type: 'visitor', kind: 'ferry', y: clamp01((f.y - GROUND) / usableH()), riders: f.pass.map((p) => p.species) });
      // The Mac went away while it sailed out: its passengers stay on this screen after all.
      else for (const p of f.pass) addGremlet(p.species, V(f.dir > 0 ? ferryHalf() : W - ferryHalf(), GROUND));
      ferry = null;
      saveRoster(); updateCount();
      return;
    }
  }
  // Jumpers caught by the deck as they come down onto it.
  for (const [id, deadline] of f.boarding) {
    const c = byId(id);
    if (!c || t > deadline || c.isGrounded && t > deadline - 3.4) { f.boarding.delete(id); continue; }
    if (c.activity === 'airborne' && c.vel.y <= 0 && Math.abs(c.pos.x - f.x) < ferryHalf() * 0.8 && Math.abs(c.pos.y - ferryDeck()) < 16) {
      f.boarding.delete(id);
      f.pass.push({ species: c.species.id, art: art.get(c.id) });
      removeGremlet(c.id);
    }
  }
}

function drawFerry(t) {
  if (!ferry) return;
  const f = ferry, bob = Math.sin(t * 1.6) * 3;
  const img = ferryImage(Math.floor(t * 8) % 2);
  const s = toScreen(f.x, f.y + bob);
  ctx.save();
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.imageSmoothingEnabled = false;
  ctx.save();
  ctx.translate(Math.round(s.x), Math.round(s.y));
  // The art faces right with its propeller at the stern; it points the way it's going.
  const heading = f.phase === 'out' ? -f.dir : f.dir;
  if (heading < 0) ctx.scale(-1, 1);
  ctx.drawImage(img, -ferryHalf(), -34 * PX, 44 * PX, 34 * PX);
  ctx.restore();
  // Passengers stand on the deck, in front of the balloon and its ropes.
  f.pass.forEach((p, i) => {
    const r = p.art.rects[p.art.species.frame('idle', t - f.t0 + i)];
    if (!r) return;
    const w = r.w * PX, h = r.h * PX, ps = toScreen(f.x + (i - (f.pass.length - 1) / 2) * 30, ferryDeck() + bob);
    ctx.save();
    ctx.translate(Math.round(ps.x), Math.round(ps.y));
    if (f.phase === 'out' ? f.dir > 0 : f.dir < 0) ctx.scale(-1, 1);
    ctx.drawImage(p.art.image, r.x, r.y, r.w, r.h, -w / 2, -h, w, h);
    ctx.restore();
  });
  ctx.restore();
}

// ---------------------------------------------------------------- drive one yourself (keyboard, or the on-screen pad)

function steer(dt) {
  if (driven == null) return;
  const c = byId(driven);
  if (!c) { driven = null; updateDriveUI(); return; }
  c.speedBoost = 2.4;
  boots(c, dt);
  let dir = (keys.right ? 1 : 0) - (keys.left ? 1 : 0);
  if (!dir && c.autoWalk && performance.now() / 1000 < c.autoWalk) dir = inward();
  if (c.activity === 'airborne') {
    if (dir) c.vel = V(c.vel.x + (dir * c.species.walkSpeed * 2.6 - c.vel.x) * Math.min(1, dt * 5), c.vel.y);
    return;
  }
  if (!c.isGrounded) return;
  if (dir) {
    c.facing = dir; c.edgeDecided = true; c.doorChoice = true;
    if (c.activity !== 'walk') c.set('walk', 0.3); else c.timer = 0.3;
    return;
  }
  if (c.activity === 'walk') { c.idleVariant = 'idle'; c.set('idle', 0.4); return; }
  if (c.activity === 'idle') { c.timer = Math.max(c.timer, 0.3); return; }
  if (c.timer < 0.05 && !['crouch', 'sleep', 'yawn', 'wake'].includes(c.activity)) { c.idleVariant = 'idle'; c.set('idle', 0.4); }
}

function act(name) {
  if (remoteDrive && driven == null) { bridge?.cross({ type: 'keys', keys: { ...keys }, act: name }); return; }
  const c = byId(driven);
  if (!c) return;
  if (name === 'mine') { swing(); return; }
  if (name === 'jump') {
    if (!c.isGrounded) return;
    c.jumpAt = performance.now() / 1000;
    const moving = keys.left || keys.right;
    world.launch(c, V(moving ? c.facing * c.species.walkSpeed * 2.6 : c.facing * 30, Math.sqrt(2 * world.gravity * 190 * (c.species.jumpPower || 1))));
  } else if (!c.isGrounded) return;
  else if (name === 'wave') c.set('wave', 1.3);
  else if (name === 'special') world.startSpecial(c);
  else if (name === 'dance') world.startDance(c, 3, true);
}

function setKey(k, down) {
  if (keys[k] === down) return;
  keys[k] = down;
  if (remoteDrive && driven == null) bridge?.cross({ type: 'keys', keys: { ...keys } });
}

function takeControl(c) {
  if (driven === c?.id) c = null;
  if (driven != null) { const old = byId(driven); if (old) old.speedBoost = 1; }
  driven = c ? c.id : null;
  remoteDrive = false; drivenByPeer = false;
  keys.left = keys.right = keys.up = false;
  life.n = HEARTS; life.hurtUntil = 0;
  if (c) say(c.id, 'You drive! 🎮', 1.6);
  updateDriveUI();
}

function updateDriveUI() {
  const hint = document.getElementById('drivehint'), pad = document.getElementById('pad');
  if (!hint) return;
  const c = byId(driven);
  const touch = matchMedia('(pointer: coarse)').matches;
  if (c && drivenByPeer) {
    hint.innerHTML = `<b>${c.species.name}</b> is being driven from the other screen`;
  } else if (c) {
    hint.innerHTML = touch
      ? `Driving <b>${c.species.name}</b>. Use the pad · Double-tap it again to let go`
      : `Driving <b>${c.species.name}</b> · ← → walk · Space jump (hold to fly) · X mine · E wave · Q special · F dance · Esc let go`;
  } else if (remoteDrive) {
    hint.innerHTML = 'Your Gremlet is on the other screen. Keep driving with the same keys · Esc to stop';
  }
  hint.hidden = !(c || remoteDrive);
  if (pad) pad.hidden = !(touch && (c || remoteDrive));
}

function drawDriveMarker(t) {
  const c = byId(driven);
  if (!c) return;
  const s = toScreen(c.pos.x, c.pos.y + c.size.y + 10 + Math.abs(Math.sin(t * 5)) * 6);
  ctx.save();
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.fillStyle = '#ff7a4d';
  const p = Math.max(2, PX - 1), x = Math.round(s.x), y = Math.round(s.y);
  for (let row = 0; row < 4; row++) ctx.fillRect(x - (3 - row) * p, y - (4 - row) * p, (7 - row * 2) * p, p);
  ctx.restore();
}

addEventListener('keydown', (e) => {
  if (e.target.closest?.('input, textarea')) return;
  if (e.key === 'Escape') { if (driven != null || remoteDrive) { takeControl(null); e.preventDefault(); } return; }
  if (e.key === 'Tab' && driven == null && !remoteDrive && world.creatures.length) {
    const mid = W / 2, pick = [...world.creatures].filter((c) => !visitors.has(c.id)).sort((a, b) => Math.abs(a.pos.x - mid) - Math.abs(b.pos.x - mid))[0];
    if (pick) { takeControl(pick); e.preventDefault(); }
    return;
  }
  if (driven == null && !remoteDrive) return;
  const k = e.key.toLowerCase();
  if (k === 'arrowleft' || k === 'a') { setKey('left', true); e.preventDefault(); }
  else if (k === 'arrowright' || k === 'd') { setKey('right', true); e.preventDefault(); }
  else if (k === 'arrowup' || k === 'w' || k === ' ') { if (!e.repeat) { setKey('up', true); act('jump'); } e.preventDefault(); }
  else if ((k === 'x' || k === 'j') && !e.repeat) act('mine');
  else if (k === 'e' && !e.repeat) act('wave');
  else if (k === 'q' && !e.repeat) act('special');
  else if (k === 'f' && !e.repeat) act('dance');
});
addEventListener('keyup', (e) => {
  const k = e.key.toLowerCase();
  if (k === 'arrowleft' || k === 'a') setKey('left', false);
  if (k === 'arrowright' || k === 'd') setKey('right', false);
  if (k === 'arrowup' || k === 'w' || k === ' ') setKey('up', false);
});
addEventListener('blur', () => { setKey('left', false); setKey('right', false); setKey('up', false); });

function wirePad() {
  const pad = document.getElementById('pad');
  if (!pad) return;
  for (const b of pad.querySelectorAll('[data-k]')) {
    const k = b.dataset.k;
    const on = (e) => { e.preventDefault(); if (k === 'mine') act('mine'); else if (k === 'jump') { setKey('up', true); act('jump'); } else setKey(k, true); };
    const off = (e) => { e.preventDefault(); if (k === 'jump') setKey('up', false); else if (k !== 'mine') setKey(k, false); };
    b.addEventListener('pointerdown', on); b.addEventListener('pointerup', off); b.addEventListener('pointercancel', off); b.addEventListener('pointerleave', off);
  }
}

// ---------------------------------------------------------------- adventure: pickaxe, rocket boots, hearts and the Grumble King

const HEARTS = 5;
const life = { n: HEARTS, hurtUntil: 0 };
const swings = [];               // { id, t0 }
const debris = [];               // pixel chips: { x, y, vx, vy, color, t, life }
let boss = null;
let crownHolder = null;          // creature id wearing the crown (beat the boss)
let shakeUntil = 0;
const now_ = () => performance.now() / 1000;
/** Pickaxe chips in the island's own colours: its turf, soil and stone. */
function chipColors(p) { const pal = Biome.palette(p.biome); return [pal.top, pal.soil, pal.stone].map(hex); }

function chips(x, y, colors, n, spread = 1) {
  for (let i = 0; i < n; i++) {
    debris.push({ x: x + (Math.random() - 0.5) * 10 * spread, y, vx: (Math.random() - 0.5) * 360 * spread, vy: 180 + Math.random() * 320,
      color: colors[i % colors.length], t: 0, life: 0.9 + Math.random() * 0.6 });
  }
}

function updateDebris(dt) {
  for (let i = debris.length - 1; i >= 0; i--) {
    const d = debris[i];
    d.t += dt; d.vy -= 1500 * dt; d.x += d.vx * dt; d.y += d.vy * dt;
    if (d.y < GROUND) { d.y = GROUND; d.vy = -d.vy * 0.35; d.vx *= 0.6; }
    if (d.t > d.life) debris.splice(i, 1);
  }
}

/** Swing the pickaxe: bonks Gremlets, chips platforms (four hits breaks one) and hurts the boss. */
function swing() {
  const c = byId(driven);
  if (!c) return;
  const t = now_();
  if (c.swingAt && t - c.swingAt < 0.3) return;
  c.swingAt = t;
  swings.push({ id: c.id, t0: t });
  const f = c.facing, w = c.size.x, h = c.size.y;
  const box = { x0: f > 0 ? c.pos.x - w * 0.1 : c.pos.x - w * 0.95, x1: f > 0 ? c.pos.x + w * 0.95 : c.pos.x + w * 0.1, y0: c.pos.y - PX * 7, y1: c.pos.y + h * 0.9 };
  const hits = (x0, x1, y0, y1) => x1 > box.x0 && x0 < box.x1 && y1 > box.y0 && y0 < box.y1;
  const tip = V(c.pos.x + f * w * 0.6, c.pos.y + h * 0.25);
  let hit = false;
  if (boss && boss.hp > 0) {
    const b = bossBox();
    if (hits(b.x0, b.x1, b.y0, b.y1)) { hurtBoss(boss.state === 'rest' ? 2 : 1, c); hit = true; }
  }
  for (const o of world.creatures) {
    if (o === c || visitors.has(o.id) || o.activity === 'dragged') continue;
    const b = o.bounds;
    if (!hits(b.x, b.x + b.w, b.y, b.y + b.h)) continue;
    hit = true;
    world.endSocial(o);
    o.ground = null; o.vel = V(f * 260, 360); o.facing = -f; o.set('airborne');
    particles.burst(FX.bang, head(o), { dy: [8, 12], duration: 0.7, spin: 0 });
    if (Math.random() < 0.35) say(o.id, ['Hey!', 'Bonk!', 'Ow!', 'Rude!'][Math.floor(Math.random() * 4)], 1.4);
  }
  const p = platforms.find((q) => !q.broken && hits(q.x, q.x + q.w, q.y, q.y + q.h));
  if (p) {
    hit = true;
    p.dmg = (p.dmg || 0) + 1;
    const at = Math.max(p.x + PX * 2, Math.min(p.x + p.w - PX * 2, tip.x));
    chips(at, p.y + p.h, chipColors(p), 6);
    if (p.dmg >= 4) breakPlatform(p);
  } else if (!hit && c.isGrounded && c.ground < 0) {
    chips(tip.x, GROUND, night ? ['#4a3a32', '#3c5a3a'] : ['#a5774f', '#7cc46a', '#8a5f3e'], 4, 0.6);   // just dirt
  }
  if (hit) particles.burst(null, tip, { imgs: [FX.smallStar, FX.star], count: 3, dx: [-24, 24], dy: [6, 30], duration: 0.5 });
}

function breakPlatform(p) {
  p.broken = true; p.respawnAt = now_() + 25;
  for (let x = p.x; x < p.x + p.w; x += PX * 6) chips(x, p.y + p.h * 0.5, chipColors(p), 3, 0.8);
  applyDoor(); scenery = drawScenery();
  shakeUntil = now_() + 0.18;
  const c = byId(driven);
  if (c && Math.random() < 0.7) say(c.id, ['Mined it! ⛏', 'Timber!', 'Block get!'][Math.floor(Math.random() * 3)], 1.6);
}

function respawnPlatforms(t) {
  for (const p of platforms) {
    if (!p.broken || t < p.respawnAt) continue;
    if (world.creatures.some((c) => c.pos.x > p.x - 20 && c.pos.x < p.x + p.w + 20 && c.pos.y + c.size.y > p.y && c.pos.y < p.y + p.h)) { p.respawnAt = t + 2; continue; }
    p.broken = false; p.dmg = 0;
    applyDoor(); scenery = drawScenery();
    for (let x = p.x; x < p.x + p.w; x += PX * 12) particles.burst(FX.sparkle, V(x, p.y + p.h), { dy: [10, 30], duration: 0.8, delay: Math.random() * 0.3 });
  }
}

/** Rocket boots: hold jump in the air to fly up, while the fuel lasts. */
function boots(c, dt) {
  const t = now_();
  const air = c.activity === 'airborne';
  c.boosting = !!(air && keys.up && (c.fuel ?? 1) > 0 && t > (c.jumpAt || 0) + 0.18);
  if (c.boosting) {
    c.fuel = Math.max(0, (c.fuel ?? 1) - dt * 0.5);
    c.vel = V(c.vel.x, Math.min(c.vel.y + 2700 * dt, 430));
    c.bootT = (c.bootT || 0) - dt;
    if (c.bootT <= 0) {
      c.bootT = 0.035;
      particles.burst(null, V(c.pos.x + (Math.random() - 0.5) * c.size.x * 0.25, c.pos.y + 2), { imgs: [FX.flame2, FX.sparkle, FX.flame2], dx: [-10, 10], dy: [-44, -26], duration: 0.35, spin: 0 });
    }
  } else if (c.isGrounded) c.fuel = Math.min(1, (c.fuel ?? 1) + dt * 0.9);
}

function hurtDriven(n, fromX) {
  const c = byId(driven), t = now_();
  if (!c || t < life.hurtUntil) return;
  life.n -= n; life.hurtUntil = t + 1.3;
  const away = c.pos.x >= fromX ? 1 : -1;
  world.endSocial(c);
  c.ground = null; c.vel = V(away * 340, 340); c.set('airborne');
  particles.burst(FX.bang, head(c), { dy: [8, 12], duration: 0.7, spin: 0 });
  if (life.n <= 0) {
    life.n = HEARTS;
    particles.burst(null, head(c, 0.6), { imgs: [FX.heart, FX.smallHeart], count: 6, dx: [-40, 40], dy: [20, 60], duration: 1.2, stagger: 0.05 });
    say(c.id, 'Ouch… hearts refilled! 💫', 2);
  }
}

// ---- the Grumble King: a giant Gremlet that hovers, slams down and can chase you onto the other screen

async function spawnBoss({ species = null, hp = null, side = null, y = null } = {}) {
  if (boss || !index.length) return;
  const pool = index.filter((s) => !['puffcloud'].includes(s.id));
  const id = species && index.some((s) => s.id === species) ? species : pool[Math.floor(Math.random() * pool.length)].id;
  const art2 = await loadSpecies(id, PX).catch(() => null);
  if (!art2 || boss) return;
  const s = PX * (W < 600 ? 2.2 : 2.7), bw = art2.rects[0].w * s;
  const hoverY = GROUND + usableH() * 0.55;
  boss = {
    art: art2, id, name: `King ${art2.species.name}`, s, bw, bh: art2.rects[0].h * s,
    x: side === 'left' ? -bw * 0.5 : side === 'right' ? W + bw * 0.5 : W / 2,
    y: side ? (y ?? hoverY) : H, hoverY, max: 24, hp: hp ?? 24, state: side ? 'hover' : 'enter', timer: 2.2,
    dir: side === 'right' ? -1 : 1, vy: 0, flash: 0, t0: now_(), helpT: 2.5, targetX: W / 2, arrived: side ? now_() : 0,
  };
  for (const c of world.creatures) if (c.isGrounded && !c.isAsleep && c.id !== driven) { c.facing = boss.x > c.pos.x ? 1 : -1; c.set('alert', 0.6); world.emit('alert', { id: c.id }); }
  updateBossUI();
}

function bossBox() {
  return { x0: boss.x - boss.bw * 0.34, x1: boss.x + boss.bw * 0.34, y0: boss.y, y1: boss.y + boss.bh * 0.78 };
}

function hurtBoss(n, by) {
  if (!boss || boss.hp <= 0) return;
  boss.hp = Math.max(0, boss.hp - n);
  boss.flash = 0.12;
  if (by) boss.lastHitter = by.id;
  particles.burst(null, V(boss.x + (Math.random() - 0.5) * boss.bw * 0.4, boss.y + boss.bh * 0.45), { imgs: [FX.star, FX.smallStar], count: 3, dx: [-50, 50], dy: [10, 60], duration: 0.6 });
  if (boss.hp <= 0) defeatBoss();
  updateBossUI();
}

function defeatBoss() {
  const at = V(boss.x, boss.y + boss.bh * 0.45);
  particles.burst(null, at, { imgs: [FX.star, FX.sparkle, FX.heart, FX.smallStar], count: 28, dx: [-220, 220], dy: [-60, 220], duration: 1.6, stagger: 0.015 });
  shakeUntil = now_() + 0.5;
  const winner = byId(boss.lastHitter) || byId(driven) || [...world.creatures].sort((a, b) => Math.abs(a.pos.x - boss.x) - Math.abs(b.pos.x - boss.x))[0];
  boss = null;
  updateBossUI();
  for (const c of world.creatures) if (c.isGrounded && c.id !== driven) world.startDance(c, 4, false);
  if (winner) {
    crownHolder = winner.id;
    try { localStorage.setItem('gremlets.crown', winner.species.id); } catch { /* private mode */ }
    setTimeout(() => say(winner.id, 'Victory! 👑', 2.6), 300);
  }
}

function updateBoss(dt) {
  if (!boss) return;
  const b = boss, t = now_();
  b.flash = Math.max(0, b.flash - dt);
  const target = byId(driven) || world.creatures.filter((c) => !visitors.has(c.id))[0];
  switch (b.state) {
    case 'enter':
      b.y += (b.hoverY - b.y) * Math.min(1, dt * 2.2);
      if (Math.abs(b.y - b.hoverY) < 6) { b.state = 'hover'; b.timer = 2; }
      break;
    case 'hover': {
      b.timer -= dt;
      if (target && Math.random() < dt * 0.8) b.targetX = target.pos.x;
      b.x += Math.max(-260, Math.min(260, (b.targetX - b.x) * 1.6)) * dt;
      b.y += (b.hoverY + Math.sin(t * 2.4) * 14 - b.y) * Math.min(1, dt * 3);
      // Now and then it storms off to the linked screen. Chase it!
      if (door && t - b.arrived > 6 && b.timer <= 0 && Math.random() < 0.3) { b.state = 'leave'; b.dir = door === 'right' ? 1 : -1; break; }
      if (b.timer <= 0) { b.state = 'windup'; b.timer = 0.55; }
      break;
    }
    case 'windup':
      b.timer -= dt;
      b.y += 60 * dt;
      if (b.timer <= 0) { b.state = 'slam'; b.vy = -300; }
      break;
    case 'slam':
      b.vy -= 3200 * dt;
      b.y += b.vy * dt;
      if (b.y <= GROUND) { b.y = GROUND; b.state = 'rest'; b.timer = 1.6; shockwave(); }
      break;
    case 'rest':
      b.timer -= dt;
      if (b.timer <= 0) { b.state = 'rise'; }
      break;
    case 'rise':
      b.y += (b.hoverY - b.y) * Math.min(1, dt * 2.4);
      if (Math.abs(b.y - b.hoverY) < 10) { b.state = 'hover'; b.timer = 1.6 + Math.random() * 1.6; }
      break;
    case 'leave':
      b.x += b.dir * 300 * dt;
      b.y += (b.hoverY - b.y) * Math.min(1, dt * 2);
      if (b.dir > 0 ? b.x - b.bw * 0.5 > W : b.x + b.bw * 0.5 < 0) {
        if (door) bridge.cross({ type: 'visitor', kind: 'boss', species: b.id, hp: b.hp, y: clamp01((b.y - GROUND) / usableH()) });
        boss = null; updateBossUI();
        const c = byId(driven);
        if (c) say(c.id, 'It went to the other screen! After it! ➡', 2.4);
        return;
      }
      break;
  }
  // Arriving through the doorway: drift fully onto this screen first.
  if (b.arrived && b.state === 'hover' && (b.x < b.bw * 0.4 || b.x > W - b.bw * 0.4)) b.targetX = W / 2;
  // Touching the boss while it's low hurts.
  const c = byId(driven);
  if (c && ['slam', 'rest', 'windup'].includes(b.state)) {
    const bb = bossBox(), cb = c.bounds;
    if (cb.x + cb.w > bb.x0 && cb.x < bb.x1 && cb.y + cb.h > bb.y0 && cb.y < bb.y1) hurtDriven(1, b.x);
  }
  // The rest of the gang helps out with their special moves.
  b.helpT -= dt;
  if (b.helpT <= 0) {
    b.helpT = 1.8 + Math.random();
    const helpers = world.creatures.filter((o) => o.id !== driven && o.isGrounded && !o.isAsleep && !visitors.has(o.id) && Math.abs(o.pos.x - b.x) < 340);
    const h = helpers[Math.floor(Math.random() * helpers.length)];
    if (h) {
      h.facing = b.x > h.pos.x ? 1 : -1;
      world.startSpecial(h);
      setTimeout(() => hurtBoss(0.5, null), 450);
    }
  }
}

function shockwave() {
  shakeUntil = now_() + 0.35;
  dustRing(boss.x);
  for (const c of world.creatures) {
    if (!c.isGrounded || c.pos.y > GROUND + 4 || visitors.has(c.id)) continue;
    const d = c.pos.x - boss.x;
    if (Math.abs(d) > 260) continue;
    if (c.id === driven) { if (Math.abs(d) < boss.bw * 0.55) hurtDriven(1, boss.x); continue; }
    world.endSocial(c);
    c.ground = null; c.vel = V(Math.sign(d || 1) * (300 - Math.abs(d)), 260 + (260 - Math.abs(d))); c.set('airborne');
  }
}

function dustRing(x) {
  for (const side of [-1, 1]) {
    for (let i = 0; i < 4; i++) particles.burst(FX.dust, V(x + side * (20 + i * 26), GROUND + 4), { dx: side < 0 ? [-90, -40] : [40, 90], dy: [0, 20], duration: 0.55, delay: i * 0.04, spin: 0 });
  }
}

function updateBossUI() {
  const btn = document.getElementById('boss');
  if (btn) btn.classList.toggle('on', !!boss);
}

// ---- drawing

const PICK = ['.ggggggg.', 'gGGGGGGGg', 'g...h...g', '....h....', '....h....', '....h....', '....h....', '....h....', '....h....', '....h....'];
const PICK_COLORS = { g: '#5b616b', G: '#c9cfd6', h: '#8a5a34' };
const CROWN = ['y.y.y', 'yyyyy', 'yRyRy', 'yyyyy'];

function stampRows(rows, colors, x, y, p) {
  for (let r = 0; r < rows.length; r++) for (let k = 0; k < rows[r].length; k++) {
    const col = colors[rows[r][k]];
    if (!col) continue;
    ctx.fillStyle = col; ctx.fillRect(x + k * p, y + r * p, p, p);
  }
}

let hudCache = { at: 0, y: 0 };
function hudTop() {     // just under the header bar, however tall it wraps on this screen
  const t = performance.now();
  if (t - hudCache.at > 1000) { const bar = document.getElementById('bar'); hudCache = { at: t, y: bar ? Math.round(bar.getBoundingClientRect().bottom) : TOP }; }
  return hudCache.y;
}

function drawAdventure(t) {
  ctx.save();
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.imageSmoothingEnabled = false;
  // Cracks on chipped platforms.
  ctx.fillStyle = 'rgba(40,24,16,0.75)';
  for (const p of platforms) {
    if (p.broken || !p.dmg) continue;
    const top = H - (p.y + p.h), rnd = mulberry(p.id * 31);
    for (let i = 0; i < p.dmg * 3; i++) {
      let x = p.x + PX * 2 + Math.floor(rnd() * (p.w - PX * 4) / PX) * PX, y = top;
      for (let k = 0; k < 3; k++) { ctx.fillRect(x, y, PX, PX); x += (rnd() < 0.5 ? -PX : PX); y += PX; }
    }
  }
  // Debris.
  for (const d of debris) {
    ctx.globalAlpha = Math.min(1, (d.life - d.t) * 3);
    ctx.fillStyle = d.color;
    const s = toScreen(d.x, d.y);
    ctx.fillRect(Math.round(s.x), Math.round(s.y) - PX, PX, PX);
  }
  ctx.globalAlpha = 1;
  // Boss (with its ground shadow and crown).
  if (boss) {
    const b = boss, name = { hover: 'fly', enter: 'fly', rise: 'fly', leave: 'fly', windup: 'alert', slam: 'fall', rest: 'dizzy' }[b.state] || 'idle';
    const f = b.art.species.frame(name, t - b.t0), r = b.art.rects[f];
    const sh = toScreen(b.x, GROUND), lift = Math.max(0, b.y - GROUND);
    ctx.fillStyle = 'rgba(40,20,40,0.22)';
    ctx.beginPath(); ctx.ellipse(sh.x, sh.y - 2, b.bw * 0.3 * Math.max(0.4, 1 - lift / 600), PX * 3, 0, 0, Math.PI * 2); ctx.fill();
    if (r) {
      const w = r.w * b.s, h = r.h * b.s, s = toScreen(b.x, b.y);
      const jitter = b.state === 'windup' ? (Math.random() - 0.5) * 6 : 0;
      ctx.save();
      ctx.translate(Math.round(s.x + jitter), Math.round(s.y));
      if (b.dir < 0 || (b.state !== 'leave' && byId(driven) && byId(driven).pos.x < b.x)) ctx.scale(-1, 1);
      if (b.flash > 0) ctx.filter = 'brightness(2.2)';
      ctx.drawImage(b.art.image, r.x, r.y, r.w, r.h, -w / 2, -h, w, h);
      ctx.restore();
      const cp = Math.max(3, Math.round(b.s * 0.9));
      const headY = toScreen(0, b.y + b.art.species.headTop * (b.s / b.art.species.scale)).y;
      stampRows(CROWN, { y: '#ffcf3a', R: '#e8455a' }, Math.round(s.x + jitter - cp * 2.5), Math.round(headY - cp * 4 + Math.sin(t * 3) * 2), cp);
    }
    // Health bar.
    const bw = Math.min(360, W * 0.6), bx = (W - bw) / 2, by = hudTop() + 8;
    ctx.fillStyle = 'rgba(43,36,51,0.78)'; ctx.fillRect(bx - 4, by - 4, bw + 8, 22);
    ctx.fillStyle = '#5a2030'; ctx.fillRect(bx, by, bw, 14);
    ctx.fillStyle = b.flash > 0 ? '#ffb3c4' : '#ff5e7e'; ctx.fillRect(bx, by, Math.round(bw * b.hp / b.max), 14);
    ctx.font = '700 12px system-ui, sans-serif'; ctx.fillStyle = '#fff'; ctx.textAlign = 'center';
    ctx.fillText(`👑 ${b.name}`, W / 2, by + 11);
  }
  // Pickaxe swings.
  for (let i = swings.length - 1; i >= 0; i--) {
    const sw = swings[i], c = byId(sw.id), k = (t - sw.t0) / 0.22;
    if (!c || k > 1) { swings.splice(i, 1); continue; }
    const s = toScreen(c.pos.x + c.facing * c.size.x * 0.12, c.pos.y + c.size.y * 0.42);
    const p = Math.max(2, PX - 1);
    ctx.save();
    ctx.translate(Math.round(s.x), Math.round(s.y));
    if (c.facing < 0) ctx.scale(-1, 1);
    ctx.rotate(-1.3 + 3.2 * (1 - (1 - k) * (1 - k)));
    stampRows(PICK, PICK_COLORS, -4.5 * p, -PICK.length * p, p);
    ctx.restore();
  }
  // Crown on the champion.
  const champ = byId(crownHolder);
  if (champ) {
    const s = toScreen(champ.pos.x, champ.pos.y + champ.species.headTop), p = Math.max(2, PX - 1);
    stampRows(CROWN, { y: '#ffcf3a', R: '#e8455a' }, Math.round(s.x - p * 2.5), Math.round(s.y - p * 4), p);
  }
  // Hearts and boot fuel for the Gremlet you're driving.
  const c = byId(driven);
  if (c && !drivenByPeer) {
    const p = Math.max(2, PX - 1), y0 = hudTop() + (boss ? 36 : 8);
    for (let i = 0; i < HEARTS; i++) {
      const full = i < life.n;
      stampRows(['.rr.rr.', 'rRRrrrr', 'rrrrrrr', '.rrrrr.', '..rrr..', '...r...'], full ? { r: '#ff5e7e', R: '#ffd1dc' } : { r: 'rgba(43,36,51,0.25)', R: 'rgba(43,36,51,0.25)' }, 12 + i * p * 8, y0, p);
    }
    const fuel = c.fuel ?? 1;
    if (fuel < 0.999) {
      ctx.fillStyle = 'rgba(43,36,51,0.3)'; ctx.fillRect(12, y0 + p * 7 + 4, p * 39, p);
      ctx.fillStyle = '#6fb8f0'; ctx.fillRect(12, y0 + p * 7 + 4, Math.round(p * 39 * fuel), p);
    }
  }
  ctx.restore();
}

// ---------------------------------------------------------------- the project bonsai: a scripted Claude session grows it
// Same record, layout and art as the Mac app (web/js/bonsai.js). "▶ Watch a Claude session" plays a ~40 s script: a
// branch sprouts, ~30 file edits each add a leaf, two subagents hop in beside the tree, tests pass (a golden fruit),
// the task is done (a blossom). The tree stays between sessions and is saved, so it sprawls over visits.

const PROJECT = 'gremlets-web';
const BONSAI_KEY = 'gremlets.bonsai';
const SESSION_EDITS = 30;
let bonsai = null;               // { tree, layout, base, scale, S, isle, art, key, planted, boingAt }
let session = null;              // the script playing now: { t0, steps, step, edits }
const minions = [];              // tiny subagent Gremlets hopping beside the tree: { art, dx, facing, phase, t0, leaveAt }

function loadBonsai() {
  try { const t = Bonsai.fromJSON(JSON.parse(localStorage.getItem(BONSAI_KEY) || 'null')); return t ? { tree: t, planted: -9 } : null; }
  catch { return null; }
}
function saveBonsai() { if (bonsai) try { localStorage.setItem(BONSAI_KEY, JSON.stringify(bonsai.tree)); } catch { /* private mode */ } }
const isleGone = () => bonsai.isle == null || !platforms.some((p) => p.id === bonsai.isle && !p.broken);

/** Roots the tree on the widest island (pot centred on its top surface), scaled to the headroom above it. Layout points
 *  map to screen pixels at `S` = scale × PX / 3: the Mac shows the art at three pixels per art pixel; phones use PX = 2. */
function placeBonsai() {
  if (!bonsai) return;
  const isle = platforms.filter((p) => !p.broken).sort((a, b) => b.w - a.w)[0];
  const L = layoutBonsai(bonsai.tree);
  const base = isle ? V(isle.x + isle.w / 2, isle.y + isle.h) : V(W / 2, GROUND);
  const headroom = H - TOP - base.y - 12;
  const fit = Math.min(1, headroom / Math.max(1, (L.bounds.y + L.bounds.h) * PX / 3), (W - 16) / Math.max(1, L.bounds.w * PX / 3));
  const scale = Math.round(Math.max(0.4, fit) * 20) / 20;
  Object.assign(bonsai, { layout: L, base, scale, S: scale * PX / 3, isle: isle ? isle.id : null, key: null });
}

/** The foliage pads as one-way platforms, in the rect form `setEnvironment` takes (same rule as the Mac: pads at least
 *  17 px in radius, the first sixteen). Ids are stable per branch and twig, so a Gremlet rides a pad that grows. */
function bonsaiPlatforms() {
  if (!bonsai) return [];
  const { layout: L, base, S } = bonsai, out = [], seen = {};
  L.pads.forEach((pad, n) => {
    const k = seen[pad.branch] = (seen[pad.branch] ?? -1) + 1;
    if (pad.rx * S < 17 || n >= 16) return;
    const y = base.y + (pad.center.y + pad.ry * 0.8) * S;
    const x0 = base.x + (pad.center.x - pad.rx * 0.7) * S, x1 = base.x + (pad.center.x + pad.rx * 0.7) * S;
    out.push({ id: 1000 + (pad.branch < 0 ? MAX_BRANCHES : pad.branch) * 4 + k, x: x0, y: y - PX * 2, w: x1 - x0, h: PX * 2 });
  });
  return out;
}

const treePoint = (p) => V(bonsai.base.x + p.x * bonsai.S, bonsai.base.y + p.y * bonsai.S);
const padOf = (branch) => bonsai.layout.pads.find((p) => p.branch === branch) ?? bonsai.layout.pads[bonsai.layout.pads.length - 1];
const mainLimb = (branch) => bonsai.layout.limbs.filter((l) => l.points.length === 3)[branch];

/** The tree grows a leaf, bloom or fruit on the session's branch, with the matching little effect at that pad. */
function growBonsai(part) {
  const br = bonsai.tree.grow(part);
  if (br == null) return;
  placeBonsai(); applyDoor();
  const at = treePoint(padOf(br).center);
  if (part === 'leaf') particles.burst(null, at, { imgs: [FX.leaf, FX.leaf2], count: 2, dx: [-16, 16], dy: [-30, -6], duration: 1.1 });
  else if (part === 'bloom') particles.burst(null, at, { imgs: [FX.petal, FX.sparkle], count: 5, dx: [-26, 26], dy: [-10, 30], duration: 1.2, stagger: 0.05 });
  else particles.burst(null, at, { imgs: [FX.star, FX.sparkle, FX.smallStar], count: 7, dx: [-24, 24], dy: [0, 36], duration: 1, stagger: 0.04 });
  saveBonsai();
}

function caption(text) {
  const el = document.getElementById('session');
  if (!el) return;
  el.hidden = !text;
  if (text) el.firstElementChild.textContent = text;
}

/** "▶ Watch a Claude session": plants the tree if there is none, then plays the script. Another press, another branch. */
function watchSession() {
  if (session) return;
  const t0 = now_();
  if (!bonsai) {
    bonsai = { tree: new Bonsai(PROJECT, t0), planted: t0 };
    placeBonsai(); applyDoor();
    particles.burst(null, V(bonsai.base.x, bonsai.base.y + 20), { imgs: [FX.leaf, FX.sparkle, FX.dust], count: 8, dx: [-40, 40], dy: [0, 50], duration: 1, stagger: 0.03 });
  }
  const tree = bonsai.tree, steps = [];
  const at = (t, f) => steps.push({ t, f });
  const helpers = () => { const n = minions.filter((m) => !m.leaveAt).length; return n ? ` · ${n} subagent${n === 1 ? '' : 's'} helping` : ''; };
  at(0, () => {
    const sprouted = tree.startSession('web-' + Math.round(t0), t0);
    placeBonsai(); applyDoor();
    bonsai.boingAt = now_();
    const where = sprouted ? treePoint(mainLimb(tree.currentBranch).points[0]) : treePoint(padOf(tree.currentBranch).center);
    particles.burst(null, where, { imgs: [FX.dust, FX.leaf, FX.sparkle], count: 6, dx: [-20, 20], dy: [4, 30], duration: 0.8 });
    caption(sprouted ? `🌱 Claude starts a session on ${PROJECT} · a new branch sprouts` : `🌿 Claude starts a session on ${PROJECT} · the tree thickens`);
    saveBonsai();
  });
  let t = 1.4;
  for (let i = 1; i <= SESSION_EDITS; i++) {
    if (i === 15) { at(t, () => caption(`Claude is reading the code…${helpers()}`)); t += 2.4; }
    at(t, () => { growBonsai('leaf'); session.edits++; caption(`Claude is editing files… ${session.edits} edit${session.edits === 1 ? '' : 's'}${helpers()}`); });
    t += 0.5;
  }
  at(3.2, () => summonMinion(-1));
  at(5.6, () => summonMinion(1));
  at(19, () => dismissMinion());
  at(21.5, () => dismissMinion());
  at(23.5, () => { growBonsai('fruit'); caption(`✓ Tests pass · a golden fruit (${session.edits} edits so far)`); });
  at(29, () => { growBonsai('bloom'); caption('🌸 Task done · a blossom opens'); });
  at(34, () => {
    tree.endSession(); saveBonsai();
    caption(`Session over · ${tree.edits} edit${tree.edits === 1 ? '' : 's'} and ${tree.branches.length} branch${tree.branches.length === 1 ? '' : 'es'} on the ${tree.species} · press ▶ again for another`);
  });
  at(40, () => caption(null));
  steps.sort((a, b) => a.t - b.t);
  session = { t0, steps, step: 0, edits: 0 };
  document.getElementById('watch')?.classList.add('on');
  updateSession(t0);   // the branch sprouts on the press itself
}

function updateSession(t) {
  if (!session) return;
  const { steps } = session;
  while (session && session.step < steps.length && t - session.t0 >= steps[session.step].t) steps[session.step++].f();
  if (session && session.step >= steps.length) { session = null; document.getElementById('watch')?.classList.remove('on'); }
}

/** A subagent: a half-size copy of one of the Gremlets here, hopping on the island beside the pot. */
async function summonMinion(side) {
  if (!bonsai) return;
  const pool = world.creatures.filter((c) => art.has(c.id));
  const c = pool[Math.floor(Math.random() * pool.length)];
  const a = c ? art.get(c.id) : (index.length ? await loadSpecies(index[Math.floor(Math.random() * index.length)].id, PX).catch(() => null) : null);
  if (!a || !bonsai) return;
  const isle = platforms.find((p) => p.id === bonsai.isle);
  const room = isle ? isle.w / 2 - 12 : 60;
  const dx = side * Math.min(room, bonsai.layout.potWidth * bonsai.S / 2 + 12 + Math.random() * 12);
  minions.push({ art: a, dx, facing: -side, phase: Math.random() * 6.28, t0: now_(), leaveAt: null });
  particles.burst(null, V(bonsai.base.x + dx, bonsai.base.y + 14), { imgs: [FX.sparkle, FX.smallStar], count: 5, dx: [-16, 16], dy: [-6, 26], duration: 0.7, stagger: 0.04 });
}
function dismissMinion() {
  const m = minions.find((m) => !m.leaveAt);
  if (!m || !bonsai) return;
  m.leaveAt = now_();
  particles.burst(null, V(bonsai.base.x + m.dx, bonsai.base.y + 14), { imgs: [FX.sparkle, FX.smallStar], count: 5, dx: [-16, 16], dy: [-6, 26], duration: 0.7, stagger: 0.04 });
}
function updateMinions(t) {
  for (let i = minions.length - 1; i >= 0; i--) if (!bonsai || (minions[i].leaveAt && t > minions[i].leaveAt + 0.4)) minions.splice(i, 1);
}

function drawMinions(t) {
  if (!bonsai) return;
  for (const m of minions) {
    const a = m.art, age = t - m.t0;
    const k = m.leaveAt ? Math.max(0, 1 - (t - m.leaveAt) / 0.4) : Math.min(1, age / 0.4);   // pop in, shrink away
    const hop = Math.max(0, Math.sin(age * 5.5 + m.phase)) * 9;
    const f = a.species.frame(hop > 1 ? 'jump' : 'idle', age), r = a.rects[f];
    if (!r) continue;
    const sc = PX / 2 * k, w = r.w * sc, h = r.h * sc;
    const x = bonsai.base.x + m.dx + Math.sin(age * 1.3 + m.phase) * 8, g = toScreen(x, bonsai.base.y), s = toScreen(x, bonsai.base.y + hop);
    ctx.fillStyle = night ? 'rgba(0,0,20,0.28)' : 'rgba(60,40,20,0.16)';
    ctx.beginPath(); ctx.ellipse(g.x, g.y - 1, Math.max(1, w * 0.26), PX * 0.7, 0, 0, Math.PI * 2); ctx.fill();
    ctx.save();
    ctx.translate(Math.round(s.x), Math.round(s.y));
    if (m.facing < 0) ctx.scale(-1, 1);
    ctx.drawImage(a.image, r.x, r.y, r.w, r.h, -w / 2, -h, w, h);
    ctx.restore();
  }
}

const keyframe = (vals, u) => { const n = vals.length - 1, f = Math.max(0, Math.min(n, u * n)), i = Math.min(n - 1, Math.floor(f)); return vals[i] + (vals[i + 1] - vals[i]) * (f - i); };

/** The tree's image at 1 art pixel, remade only when the record, season or scale changes (like the Mac's layer cache). */
function bonsaiArt() {
  const tree = bonsai.tree, age = tree.ageDays(Date.now() / 1000);
  const key = [tree.edits, tree.blooms, tree.fruit, tree.branches.length, tree.sessions, MONTH, night, bonsai.scale, Math.floor(age)].join('|');
  if (bonsai.key !== key) {
    const r = renderBonsai(tree, bonsai.layout, bonsai.scale, MONTH, night, age);
    bonsai.art = { img: r.canvas.toCanvas(), anchor: r.anchor, w: r.canvas.w, h: r.canvas.h };
    bonsai.key = key;
  }
  return bonsai.art;
}

function drawBonsai(t) {
  if (!bonsai) return;
  const a = bonsaiArt(), s = toScreen(bonsai.base.x, bonsai.base.y), wpx = a.w * PX, hpx = a.h * PX;
  const pop = keyframe([0.1, 1.12, 0.96, 1], (t - bonsai.planted) / 0.6);                 // pops in when planted
  const boing = bonsai.boingAt ? keyframe([1, 0.94, 1.04, 0.99, 1], (t - bonsai.boingAt) / 0.5) : 1;   // springs when a branch sprouts
  ctx.save();
  ctx.translate(Math.round(s.x), Math.round(s.y));
  ctx.scale(pop, pop * boing);
  ctx.drawImage(a.img, -Math.round(a.anchor.x * wpx), -Math.round((1 - a.anchor.y) * hpx), wpx, hpx);
  ctx.restore();
  // The project's name tag hangs under the pot.
  const fs = PX > 2 ? 10 : 9;
  ctx.save();
  ctx.font = `800 ${fs}px ui-rounded, "SF Pro Rounded", system-ui, sans-serif`;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const tw = Math.round(Math.min(bonsai.layout.potWidth * bonsai.S + 30, ctx.measureText(PROJECT).width + 12)), th = fs + 6;
  const tx = Math.round(s.x - tw / 2), ty = Math.round(s.y + bonsai.layout.potHeight * bonsai.S + 3);
  ctx.fillStyle = 'rgba(26,23,20,0.72)';
  if (ctx.roundRect) { ctx.beginPath(); ctx.roundRect(tx, ty, tw, th, 4); ctx.fill(); } else ctx.fillRect(tx, ty, tw, th);
  ctx.fillStyle = '#fff';
  ctx.fillText(PROJECT, Math.round(s.x), ty + th / 2 + 0.5, tw - 8);
  ctx.restore();
}

// ---------------------------------------------------------------- link sheet

function updateRoomUI() {
  if (!bridge) return;
  applyDoor();
  const chip = document.getElementById('roomchip');
  if (chip) {
    chip.hidden = !bridge.linked;
    chip.textContent = bridge.peerOnline ? `🔗 Linked ${bridge.side === 'right' ? '→' : '←'}` : '🔗 Waiting…';
    chip.classList.toggle('off', !bridge.peerOnline);
  }
  const sheet = document.getElementById('linker');
  if (!sheet || sheet.hidden) return;
  const choose = document.getElementById('lk-choose'), share = document.getElementById('lk-share');
  choose.hidden = bridge.linked; share.hidden = !bridge.linked;
  if (bridge.linked) {
    const url = bridge.inviteUrl();
    document.getElementById('lk-url').value = url;
    document.getElementById('lk-status').textContent = bridge.peerOnline
      ? `Linked! Gremlets can walk off the ${bridge.side} edge of this screen.`
      : `Open this link on the other screen. Its ${bridge.side === 'right' ? 'left' : 'right'} edge will lead back here.`;
    drawQR(url);
  }
}

function drawQR(text) {
  const holder = document.getElementById('lk-qr');
  if (!holder || holder.dataset.text === text || !window.qrcode) return;
  const qr = window.qrcode(0, 'M');
  qr.addData(text); qr.make();
  const n = qr.getModuleCount(), cell = Math.max(3, Math.floor(200 / (n + 8)));
  const cv = document.createElement('canvas');
  cv.width = cv.height = (n + 8) * cell;
  const g = cv.getContext('2d');
  g.fillStyle = '#fff'; g.fillRect(0, 0, cv.width, cv.height); g.fillStyle = '#2b2433';
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (qr.isDark(r, c)) g.fillRect((c + 4) * cell, (r + 4) * cell, cell, cell);
  holder.replaceChildren(cv);
  holder.dataset.text = text;
}

function wireLinker() {
  const sheet = document.getElementById('linker');
  if (!sheet || !bridge) return;
  const open = () => { sheet.hidden = false; updateRoomUI(); };
  const close = () => { sheet.hidden = true; };
  document.getElementById('link').addEventListener('click', open);
  document.getElementById('lk-close').addEventListener('click', close);
  sheet.addEventListener('click', (e) => { if (e.target === sheet) close(); });
  for (const b of sheet.querySelectorAll('[data-side]')) b.addEventListener('click', () => { bridge.create(b.dataset.side); updateRoomUI(); });
  document.getElementById('lk-copy').addEventListener('click', async (e) => {
    const input = document.getElementById('lk-url');
    try { await navigator.clipboard.writeText(input.value); e.target.textContent = 'Copied'; }
    catch { input.select(); e.target.textContent = 'Selected'; }
    setTimeout(() => (e.target.textContent = 'Copy link'), 1800);
  });
  document.getElementById('lk-unlink').addEventListener('click', () => { bridge.unlink(); updateRoomUI(); });
  document.getElementById('lk-rain').addEventListener('click', () => { summonCloud(bridge.side === 'right' ? 'left' : 'right'); close(); });
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
    const hintEl = document.getElementById('hint');
    if (hintEl && matchMedia('(pointer: coarse)').matches) hintEl.textContent = hintEl.textContent.replace('Double-click', 'Double-tap');
    setTimeout(() => document.getElementById('hint')?.classList.add('gone'), 7000);
    if (bridge) {
      bridge.onWalk = arriveThroughDoor;
      bridge.onVisitor = (n) => {
        if (n.kind === 'ferry') ferryArrives(n);
        else if (n.kind === 'boss') spawnBoss({ species: n.species, hp: Math.max(1, Math.min(24, +n.hp || 24)), side: bridge.side, y: GROUND + clamp01(n.y) * usableH() });
        else summonCloud(bridge.side, GROUND + clamp01(n.y) * usableH());
      };
      bridge.onKeys = (n) => {
        if (driven == null) return;
        keys.left = !!n.keys?.left; keys.right = !!n.keys?.right; keys.up = !!n.keys?.up;
        if (n.act) act(n.act);
      };
      bridge.onStatus = updateRoomUI;
      wireLinker();
      bridge.start();
      setInterval(updateRoomUI, 5000);
      if (bridge.justJoined) setTimeout(() => { document.getElementById('linker').hidden = false; updateRoomUI(); }, 400);
      updateRoomUI();
    }
    wirePad();
    // The project bonsai: a saved tree takes root again (?fresh starts over); ▶ plays a Claude session on it.
    bonsai = params.has('fresh') ? null : loadBonsai();
    if (bonsai) { placeBonsai(); applyDoor(); }
    document.getElementById('watch')?.addEventListener('click', watchSession);
    if (params.has('watch')) setTimeout(watchSession, 1500);
    document.getElementById('rain')?.addEventListener('click', () => summonCloud());
    document.getElementById('boss')?.addEventListener('click', () => {
      if (boss) return;
      spawnBoss();
      if (driven == null && !remoteDrive) {
        const mid = W / 2, pick = [...world.creatures].filter((c) => !visitors.has(c.id)).sort((a, b) => Math.abs(a.pos.x - mid) - Math.abs(b.pos.x - mid))[0];
        if (pick) takeControl(pick);
      }
    });
    if (params.has('boss')) setTimeout(() => spawnBoss(), 1200);
    try {
      const champ = localStorage.getItem('gremlets.crown');
      const c = champ && world.creatures.find((o) => o.species.id === champ);
      if (c) crownHolder = c.id;
    } catch { /* private mode */ }
    // Now and then a rain cloud drifts by on its own.
    setInterval(() => { if (!document.hidden && Math.random() < 0.1) summonCloud(); }, 60_000);
    if (link?.paired) {
      for (const v of loadVisitors()) await arrive(v.species, v.harvest || [], true);
      link.onArrive = ({ species }) => arrive(species);
      link.onStatus = updateLinkUI;
      link.start();
      document.getElementById('home').addEventListener('click', sendHome);
      updateLinkUI();
    }
  }
  if (params.has('debug')) window.gremlets = { world, toScreen, particles, bridge, summonCloud, takeControl, keys, spawnBoss, swing, act, life, watchSession, get platforms() { return platforms; }, get boss() { return boss; }, get driven() { return driven; }, get door() { return door; }, get bonsai() { return bonsai; }, get session() { return session; } };
  requestAnimationFrame((t) => { last = t; frame(t); });
}

addEventListener('resize', () => { layout(); });
document.addEventListener('visibilitychange', () => { last = performance.now(); });
start().catch((err) => {
  document.body.insertAdjacentHTML('beforeend', `<div class="err">Couldn't load the Gremlets: ${err.message}</div>`);
});
