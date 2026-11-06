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
const keys = { left: false, right: false };
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
  applyDoor();
  scenery = drawScenery();
}

/** The habitat's screen, stretched past a linked edge so Gremlets can walk out through it. */
function applyDoor() {
  door = bridge?.linked && bridge.peerOnline ? bridge.side : null;
  const x = door === 'left' ? -DOOR : 0, w = W + (door ? DOOR : 0);
  world.setEnvironment([{ x, y: GROUND, w, h: H - GROUND - TOP }], platforms);
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
  drawDriveMarker(now / 1000);
  placeBubbles(now / 1000);
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
  for (const [, v] of visitors) {
    const s = toScreen(v.spot.boxX, v.spot.y);
    v.garden.draw(ctx, s.x, s.y, PX);
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

// ---------------------------------------------------------------- drive one yourself (keyboard, or the on-screen pad)

function steer(dt) {
  if (driven == null) return;
  const c = byId(driven);
  if (!c) { driven = null; updateDriveUI(); return; }
  c.speedBoost = 2.4;
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
  if (name === 'jump') {
    if (!c.isGrounded) return;
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
  keys.left = keys.right = false;
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
      : `Driving <b>${c.species.name}</b> · ← → walk · ↑ or Space jump · E wave · Q special · F dance · Esc let go`;
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
  else if ((k === 'arrowup' || k === 'w' || k === ' ') && !e.repeat) { act('jump'); e.preventDefault(); }
  else if (k === 'e' && !e.repeat) act('wave');
  else if (k === 'q' && !e.repeat) act('special');
  else if (k === 'f' && !e.repeat) act('dance');
});
addEventListener('keyup', (e) => {
  const k = e.key.toLowerCase();
  if (k === 'arrowleft' || k === 'a') setKey('left', false);
  if (k === 'arrowright' || k === 'd') setKey('right', false);
});
addEventListener('blur', () => { setKey('left', false); setKey('right', false); });

function wirePad() {
  const pad = document.getElementById('pad');
  if (!pad) return;
  for (const b of pad.querySelectorAll('[data-k]')) {
    const k = b.dataset.k;
    const on = (e) => { e.preventDefault(); if (k === 'jump') act('jump'); else setKey(k, true); };
    const off = (e) => { e.preventDefault(); if (k !== 'jump') setKey(k, false); };
    b.addEventListener('pointerdown', on); b.addEventListener('pointerup', off); b.addEventListener('pointercancel', off); b.addEventListener('pointerleave', off);
  }
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
    setTimeout(() => document.getElementById('hint')?.classList.add('gone'), 7000);
    if (bridge) {
      bridge.onWalk = arriveThroughDoor;
      bridge.onVisitor = (n) => summonCloud(bridge.side, GROUND + clamp01(n.y) * usableH());
      bridge.onKeys = (n) => {
        if (driven == null) return;
        keys.left = !!n.keys?.left; keys.right = !!n.keys?.right;
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
    document.getElementById('rain')?.addEventListener('click', () => summonCloud());
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
  if (params.has('debug')) window.gremlets = { world, toScreen, particles, bridge, summonCloud, takeControl, keys, get driven() { return driven; }, get door() { return door; } };
  requestAnimationFrame((t) => { last = t; frame(t); });
}

addEventListener('resize', () => { layout(); });
document.addEventListener('visibilitychange', () => { last = performance.now(); });
start().catch((err) => {
  document.body.insertAdjacentHTML('beforeend', `<div class="err">Couldn't load the Gremlets: ${err.message}</div>`);
});
