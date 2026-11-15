// Gremlets keychain simulator: a 240x240 round screen + a turning ring + one button (press on the screen).
// Everything here is meant to port to the real device (ESP32 + round LCD + encoder): fixed-step logic,
// integer-ish pixel drawing, sprite sheets straight from Species/<id>/.

const LAYOUT = new URLSearchParams(location.search).get('layout') === 'keypad' ? 'keypad' : 'dial';
document.body.dataset.layout = LAYOUT;
const W = 240, H = LAYOUT === 'keypad' ? 150 : 240, CX = W / 2, CY = H / 2, GROUND = H - 62 + (LAYOUT === 'keypad' ? 26 : 0), SCALE = LAYOUT === 'keypad' ? 2 : 3;
const cv = document.getElementById(LAYOUT === 'keypad' ? 'screenK' : 'screen');
cv.width = W; cv.height = H;
const g = cv.getContext('2d');
g.imageSmoothingEnabled = false;

// ---------------------------------------------------------------- sprites
const sheets = {};
async function loadSheet(id) {
  if (sheets[id]) return sheets[id];
  const [json, img] = await Promise.all([
    fetch(`/Species/${id}/sheet.json`).then(r => r.json()),
    new Promise((ok, bad) => { const i = new Image(); i.onload = () => ok(i); i.onerror = bad; i.src = `/Species/${id}/sheet.png`; }),
  ]);
  const tags = {};
  for (const t of json.meta.frameTags) tags[t.name] = { from: t.from, to: t.to };
  const dur = json.frames.map(f => f.duration);
  return (sheets[id] = { img, tags, dur });
}

// ---------------------------------------------------------------- state
const save = (() => { try { return JSON.parse(localStorage.getItem('gremlets.keychain') || '{}'); } catch { return {}; } })();
const S = {
  id: save.id || 'nestkeeper2',
  sheet: null,
  x: CX, y: GROUND, vy: 0, facing: 1, falling: false,
  anim: 'idle', frame: 0, ft: 0, animUntil: 0, loopAnim: true,
  mode: 'free',            // free | eat | pet | play | sleep | dizzy | adopt | celebrate | needs
  modeUntil: 0,
  knob: 0, knobVel: 0, lastKnobAt: 0, spinHot: 0,
  berry: null,             // {x, y, vy}
  fullness: save.fullness ?? 0.7, moss: save.moss ?? 0.6, energy: 0.9,
  hearts: [], sparks: [], drops: [],
  menu: null,              // {items, sel, openedAt}
  clockUntil: 0,
  nightOverride: null, timeOffset: 0,
  claude: 'idle', claudeUntil: 0, claudeLive: false,
  pressAt: 0, pressDown: false, lastPress: 0, holdFired: false,
  flash: 0,
  goX: null, swarm: null,
  // little fireflies, each with its own speed and mood (like the koi)
  bugs: Array.from({ length: 6 }, (_, i) => ({ x: 30 + i * 35, y: 40 + (i % 3) * 18, vx: 0, vy: 0, speed: 18 + Math.random() * 26, desire: 0.4 + Math.random() * 0.6, ph: Math.random() * 6 })),
};
const persist = () => { try { localStorage.setItem('gremlets.keychain', JSON.stringify({ id: S.id, fullness: S.fullness, moss: S.moss })); } catch {} };

const now = () => performance.now() / 1000;
const simDate = () => new Date(Date.now() + S.timeOffset * 1000);
const isNight = () => S.nightOverride ?? (() => { const h = simDate().getHours(); return h >= 21 || h < 7; })();

function play(name, { loop = true, seconds = 0 } = {}) {
  if (!S.sheet || !S.sheet.tags[name]) name = 'idle';
  if (S.anim !== name) { S.anim = name; S.frame = 0; S.ft = 0; }
  S.loopAnim = loop;
  S.animUntil = seconds ? now() + seconds : 0;
}

function setMode(m, seconds = 0) { S.mode = m; S.modeUntil = seconds ? now() + seconds : 0; }

// ---------------------------------------------------------------- the firefly on the rim (follows the ring)
function firefly() {
  const a = S.knob * Math.PI / 180;
  return { x: CX + Math.sin(a) * 92, y: CY - Math.cos(a) * 92 };
}

// ---------------------------------------------------------------- input: ring
function turn(deg) {
  if (S.menu) {
    S.menu.acc = (S.menu.acc || 0) + deg;
    while (Math.abs(S.menu.acc) >= 24) {
      const d = Math.sign(S.menu.acc);
      S.menu.sel = (S.menu.sel + d + S.menu.items.length) % S.menu.items.length;
      S.menu.acc -= d * 24;
    }
    return;
  }
  const t = now(), dt = Math.max(0.016, t - S.lastKnobAt);
  S.knobVel = S.knobVel * 0.6 + (deg / dt) * 0.4;
  S.lastKnobAt = t;
  S.knob = (S.knob + deg + 360) % 360;
  knobEl.style.transform = `rotate(${S.knob}deg)`;
  if (LAYOUT === 'keypad') S.goX = Math.max(30, Math.min(W - 30, S.x + deg * 1.6));
  if (S.mode === 'sleep' && Math.abs(deg) > 0) { /* turning gently doesn't wake it */ }
}

const knobEl = document.getElementById(LAYOUT === 'keypad' ? 'knobK' : 'knob');
let dragA = null;
const angleAt = e => { const r = knobEl.getBoundingClientRect(); return Math.atan2(e.clientY - (r.top + r.height / 2), e.clientX - (r.left + r.width / 2)) * 180 / Math.PI; };
knobEl.addEventListener('pointerdown', e => { if (LAYOUT === 'keypad' && e.target.closest('.kcap')) return; dragA = angleAt(e); knobEl.setPointerCapture(e.pointerId); knobEl.classList.add('dragging'); });
knobEl.addEventListener('pointermove', e => {
  if (dragA === null) return;
  const a = angleAt(e); let d = a - dragA; if (d > 180) d -= 360; if (d < -180) d += 360;
  dragA = a; turn(d);
});
const endDrag = () => { dragA = null; knobEl.classList.remove('dragging'); };
knobEl.addEventListener('pointerup', endDrag); knobEl.addEventListener('pointercancel', endDrag);
document.getElementById(LAYOUT === 'keypad' ? 'deviceK' : 'device').addEventListener('wheel', e => { e.preventDefault(); turn(e.deltaY > 0 ? 15 : -15); }, { passive: false });

// ---------------------------------------------------------------- input: button (press the screen)
function pressDown() { if (S.pressDown) return; S.pressDown = true; S.pressAt = now(); S.holdFired = false; }
function pressUp() {
  if (!S.pressDown) return; S.pressDown = false;
  if (S.holdFired) return;
  const t = now();
  if (S.menu) { choose(S.menu.items[S.menu.sel]); return; }
  if (S.claude === 'needs') { S.claude = 'idle'; setMode('free'); return; }
  if (S.mode === 'sleep') { setMode('free'); play('wake', { loop: false, seconds: 1.2 }); S.energy = Math.max(S.energy, 0.5); return; }
  if (t - S.lastPress < 0.35) { S.lastPress = 0; pet(); return; }
  S.lastPress = t;
  setTimeout(() => { if (S.lastPress === t) dropBerry(LAYOUT === 'keypad' ? S.x + S.facing * 30 : firefly().x); }, 360);
}
const pressEl = LAYOUT === 'keypad' ? document.querySelector('#knobK .kcap') : cv;
pressEl.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); pressDown(); });
pressEl.addEventListener('pointerup', pressUp);
pressEl.addEventListener('pointerleave', () => { if (S.pressDown) pressUp(); });
// keypad: three keys = "go here" (like the koi swimming to where you pressed)
function goKey(i) {
  if (S.menu) { S.menu.sel = Math.min(S.menu.items.length - 1, i * 2); return; }
  if (S.mode === 'sleep') { setMode('free'); play('wake', { loop: false, seconds: 1.2 }); return; }
  S.goX = W * (i + 0.5) / 3; S.swarm = { x: S.goX, y: GROUND - 40, until: now() + 3 };
  document.querySelectorAll('.key')[i]?.classList.add('down'); setTimeout(() => document.querySelectorAll('.key')[i]?.classList.remove('down'), 140);
}
document.querySelectorAll('.key').forEach((k, i) => k.addEventListener('pointerdown', e => { e.preventDefault(); goKey(i); }));
addEventListener('keydown', e => {
  if (e.key === 'ArrowRight' || e.key === 'ArrowUp') { turn(15); e.preventDefault(); }
  if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { turn(-15); e.preventDefault(); }
  if (e.key === ' ' && !e.repeat) { pressDown(); e.preventDefault(); }
  if (LAYOUT === 'keypad' && ['1', '2', '3'].includes(e.key)) goKey(+e.key - 1);
});
addEventListener('keyup', e => { if (e.key === ' ') pressUp(); });

// ---------------------------------------------------------------- actions
function dropBerry(x) {
  if (S.mode === 'sleep') return;
  S.berry = { x: Math.max(30, Math.min(W - 30, x)), y: 20, vy: 0 };
}
function pet() {
  if (S.mode === 'sleep') return;
  setMode('pet', 1.8); play('pet', { seconds: 1.8 });
  for (let i = 0; i < 4; i++) S.hearts.push({ x: S.x + (Math.random() - 0.5) * 30, y: S.y - 70, vy: -18 - Math.random() * 10, life: 1.4 });
  S.energy = Math.min(1, S.energy + 0.05);
}
function waterMoss() {
  S.moss = Math.min(1, S.moss + 0.35); persist();
  for (let i = 0; i < 14; i++) S.drops.push({ x: 40 + Math.random() * 44, y: 60 + Math.random() * 30, vy: 60 + Math.random() * 40 });
  setMode('play', 1.6); play('special', { seconds: 1.6 });
}
function choose(item) {
  S.menu = null;
  switch (item) {
    case 'Feed': dropBerry(S.x + S.facing * 26); break;
    case 'Water': waterMoss(); break;
    case 'Play': setMode('play', 3.2); play('dance', { seconds: 3.2 }); break;
    case 'Sleep': setMode('sleep'); play('yawn', { loop: false }); break;
    case 'Clock': S.clockUntil = now() + 4; break;
  }
}

// ---------------------------------------------------------------- adoption (scan a card)
async function adopt(id, first = false) {
  const sh = await loadSheet(id);
  if (!first && id !== S.id) {
    for (let i = 0; i < 18; i++) S.sparks.push({ x: S.x + (Math.random() - 0.5) * 50, y: S.y - 40 + (Math.random() - 0.5) * 50, vx: (Math.random() - 0.5) * 60, vy: -30 - Math.random() * 30, life: 0.9 });
  }
  S.id = id; S.sheet = sh; persist();
  S.x = CX; S.y = 20; S.vy = 0; S.falling = true;
  setMode('adopt'); play('fall');
  document.querySelectorAll('.card').forEach(c => c.classList.toggle('on', c.dataset.id === id));
}

async function buildCards() {
  let ids = [];
  try {
    const idx = await fetch('/Species/index.json').then(r => r.json());
    ids = idx.species.filter(s => s.family === 'versiontwo').map(s => [s.id, s.name]);
  } catch {}
  if (!ids.length) ids = [['nestkeeper2', 'Nestkeeper']];
  const wrap = document.getElementById('cards');
  for (const [id, name] of ids) {
    const card = document.createElement('div'); card.className = 'card'; card.dataset.id = id;
    const c = document.createElement('canvas'); c.width = 32; c.height = 32;
    card.append(c, Object.assign(document.createElement('div'), { textContent: name }));
    card.onclick = () => adopt(id);
    wrap.append(card);
    loadSheet(id).then(sh => { const x = c.getContext('2d'); x.imageSmoothingEnabled = false; x.drawImage(sh.img, 0, 0, 32, 32, 0, 0, 32, 32); });
  }
}

// ---------------------------------------------------------------- Claude (live from the Gremlets app, or the buttons)
let lastBusy = false;
async function pollClaude() {
  try {
    const r = await fetch('/api/status', { cache: 'no-store' });
    if (!r.ok) throw 0;
    const d = await r.json();
    const busy = (d.claude || []).length > 0;
    S.claudeLive = true;
    document.getElementById('claudeLive').innerHTML = busy ? '<b>Live:</b> Claude is working right now.' : '<b>Live:</b> connected to your Gremlets app. Claude is idle.';
    if (busy && !lastBusy) claudeEvent('working');
    if (!busy && lastBusy) claudeEvent('done');
    lastBusy = busy;
  } catch {
    S.claudeLive = false;
    document.getElementById('claudeLive').textContent = 'Gremlets app not reachable: use the buttons to simulate.';
  }
}
function claudeEvent(kind) {
  S.claude = kind;
  if (kind === 'done') { S.claudeUntil = now() + 5; setMode('celebrate', 3.5); play('dance', { seconds: 3.5 }); S.flash = 0.6; burst(); }
  if (kind === 'needs') { setMode('needs'); play('wave'); S.flash = 0.6; }
  if (kind === 'working') { S.claudeUntil = 0; }
}
function burst() { for (let i = 0; i < 24; i++) S.sparks.push({ x: CX + (Math.random() - 0.5) * 120, y: 60 + Math.random() * 60, vx: (Math.random() - 0.5) * 40, vy: -20 - Math.random() * 30, life: 1.2 }); }
document.querySelectorAll('[data-claude]').forEach(b => b.onclick = () => { if (b.dataset.claude === 'working') lastBusy = true; if (b.dataset.claude === 'done') lastBusy = false; claudeEvent(b.dataset.claude); });
document.getElementById('fast').onclick = () => { S.timeOffset += 3600; S.fullness = Math.max(0, S.fullness - 0.12); S.moss = Math.max(0, S.moss - 0.05); persist(); };
document.getElementById('night').onclick = () => { S.nightOverride = !isNight(); if (S.nightOverride && S.mode === 'free') { setMode('sleep'); play('yawn', { loop: false }); } };

// ---------------------------------------------------------------- update
function update(dt) {
  const t = now();
  // slow needs (real time: a full belly lasts ~8 h, moss ~24 h)
  S.fullness = Math.max(0, S.fullness - dt / (8 * 3600));
  S.moss = Math.max(0, S.moss - dt / (24 * 3600));

  // hold = menu
  if (S.pressDown && !S.holdFired && t - S.pressAt > 0.55 && !S.menu) {
    S.holdFired = true;
    S.menu = { items: ['Feed', 'Water', 'Play', 'Sleep', 'Clock'], sel: 0 };
  }

  // spin fast = dizzy
  S.knobVel *= Math.pow(0.02, dt);
  if (Math.abs(S.knobVel) > 700 && S.mode === 'free') { S.spinHot += dt; if (S.spinHot > 0.35) { setMode('dizzy', 2.2); play('dizzy', { seconds: 2.2 }); S.spinHot = 0; } }
  else S.spinHot = Math.max(0, S.spinHot - dt);

  if (S.modeUntil && t > S.modeUntil) { setMode('free'); if (S.claude === 'done' && t > S.claudeUntil) S.claude = 'idle'; }
  if (S.claude === 'done' && t > S.claudeUntil) S.claude = 'idle';

  // falling in (adoption)
  if (S.falling) {
    S.vy += 420 * dt; S.y += S.vy * dt;
    if (S.y >= GROUND) { S.y = GROUND; S.falling = false; play('land', { loop: false, seconds: 0.5 }); setMode('free', 0); S.mode = 'free'; setTimeout(() => { if (S.mode === 'free') { play('wave', { seconds: 1.5 }); } }, 500); }
    return;
  }

  // berry falls, then it walks over and eats
  if (S.berry) {
    const b = S.berry;
    if (b.y < GROUND - 4) { b.vy += 300 * dt; b.y = Math.min(GROUND - 4, b.y + b.vy * dt); }
    else if (S.mode === 'free' || S.mode === 'eat') {
      const dx = b.x - S.x;
      if (Math.abs(dx) > 14) { S.facing = Math.sign(dx); S.x += Math.sign(dx) * 55 * dt; play('run'); setMode('eat'); }
      else if (S.mode !== 'eat' || !S.modeUntil) {
        setMode('eat', 1.6); play('special', { seconds: 1.6 });
        S.fullness = Math.min(1, S.fullness + 0.3); persist();
        setTimeout(() => { S.berry = null; }, 900);
      }
    }
  }

  // night: dozes off when left alone
  if (isNight() && S.mode === 'free' && !S.berry && t - S.lastKnobAt > 6 && t - S.lastPress > 6) { setMode('sleep'); play('yawn', { loop: false }); }

  // free: follow the firefly like a koi follows a finger
  if (S.mode === 'free' && !S.berry) {
    const tx = LAYOUT === 'keypad' ? (S.goX ?? S.x) : Math.max(44, Math.min(196, firefly().x));
    const dx = tx - S.x;
    const active = LAYOUT === 'keypad' ? S.goX != null : t - S.lastKnobAt < 2.5;
    if (LAYOUT === 'keypad' && S.goX != null && Math.abs(dx) <= 8) { S.goX = null; play('wave', { seconds: 0.9 }); }
    if (active && Math.abs(dx) > 8) {
      S.facing = Math.sign(dx);
      const fast = Math.abs(dx) > 50;
      S.x += Math.sign(dx) * (fast ? 70 : 38) * dt;
      play(fast ? 'run' : 'walk');
    } else if (!S.animUntil || t > S.animUntil) {
      play(S.fullness < 0.2 ? 'look' : 'idle');
    }
  }
  if (S.mode === 'sleep' && S.anim === 'yawn' && S.frame >= (S.sheet.tags.yawn.to - S.sheet.tags.yawn.from)) play('sleep');
  if (S.mode === 'needs') play('wave');

  // fireflies: swarm to a pressed key, circle while the knob turns, otherwise drift
  const turning = t - S.lastKnobAt < 1.2 && !S.menu;
  if (S.swarm && t > S.swarm.until) S.swarm = null;
  for (const b of S.bugs) {
    let ax = Math.sin(t * 0.7 + b.ph) * 10, ay = Math.cos(t * 0.9 + b.ph * 1.3) * 8;
    if (S.swarm) { ax += (S.swarm.x - b.x) * b.desire * 1.2; ay += (S.swarm.y - b.y) * b.desire * 1.2; }
    else if (turning) {
      const dx = b.x - CX, dy = b.y - (GROUND - 50), r = Math.hypot(dx, dy) || 1, dir = Math.sign(S.knobVel) || 1;
      ax += (-dy / r) * dir * 80 * b.desire + (55 - r) * dx / r * 0.8; ay += (dx / r) * dir * 80 * b.desire + (55 - r) * dy / r * 0.8;
    } else { ax += (CX - b.x) * 0.02; ay += (GROUND - 70 - b.y) * 0.05; }
    b.vx = (b.vx + ax * dt) * Math.pow(0.4, dt); b.vy = (b.vy + ay * dt) * Math.pow(0.4, dt);
    const sp = Math.hypot(b.vx, b.vy), mx = b.speed * (S.swarm || turning ? 2.2 : 1);
    if (sp > mx) { b.vx *= mx / sp; b.vy *= mx / sp; }
    b.x = Math.max(8, Math.min(W - 8, b.x + b.vx * dt)); b.y = Math.max(12, Math.min(GROUND - 6, b.y + b.vy * dt));
  }

  // particles
  for (const h of S.hearts) { h.y += h.vy * dt; h.life -= dt; }
  S.hearts = S.hearts.filter(h => h.life > 0);
  for (const p of S.sparks) { p.x += p.vx * dt; p.y += p.vy * dt; p.vy += 40 * dt; p.life -= dt; }
  S.sparks = S.sparks.filter(p => p.life > 0);
  for (const d of S.drops) { d.y += d.vy * dt; }
  S.drops = S.drops.filter(d => d.y < GROUND);
  S.flash = Math.max(0, S.flash - dt);

  // animation frames
  if (S.sheet) {
    const tg = S.sheet.tags[S.anim]; const n = tg.to - tg.from + 1;
    S.ft += dt * 1000;
    const d = S.sheet.dur[tg.from + S.frame] || 120;
    if (S.ft >= d) { S.ft -= d; S.frame = S.loopAnim ? (S.frame + 1) % n : Math.min(n - 1, S.frame + 1); }
    if (S.animUntil && t > S.animUntil && S.mode === 'free') { S.animUntil = 0; play('idle'); }
  }
}

// ---------------------------------------------------------------- draw
function px(x, y, w, h, c) { g.fillStyle = c; g.fillRect(Math.round(x), Math.round(y), w, h); }
function heart(x, y, c) { const p = [[1,0],[3,0],[0,1],[1,1],[2,1],[3,1],[4,1],[1,2],[2,2],[3,2],[2,3]]; for (const [a, b] of p) px(x + a * 2, y + b * 2, 2, 2, c); }

function draw() {
  const night = isNight();
  // sky
  const sky = g.createLinearGradient(0, 0, 0, GROUND);
  if (night) { sky.addColorStop(0, '#141a33'); sky.addColorStop(1, '#3a3560'); } else { sky.addColorStop(0, '#bfe1ef'); sky.addColorStop(1, '#f3ecd6'); }
  g.fillStyle = sky; g.fillRect(0, 0, W, H);
  if (night) { for (let i = 0; i < 26; i++) { const sx = (i * 73) % 220 + 10, sy = (i * 37) % (GROUND - 40) + 14; px(sx, sy, 2, 2, (i + Math.floor(now() * 2)) % 7 ? '#cfd6ff' : '#fff6c0'); } px(W - 60, 18, 14, 14, '#f4ecc8'); px(W - 55, 18, 9, 10, '#3a3560'); }
  else { g.fillStyle = '#ffe9a8'; g.beginPath(); g.arc(W - 50, LAYOUT === 'keypad' ? 26 : 58, 11, 0, 7); g.fill(); }
  // hills
  g.fillStyle = night ? '#2c3a3a' : '#a9cf8c'; g.beginPath(); g.ellipse(70, GROUND + 6, 110, 34, 0, Math.PI, 0); g.fill();
  g.fillStyle = night ? '#253232' : '#93c27a'; g.beginPath(); g.ellipse(190, GROUND + 6, 100, 26, 0, Math.PI, 0); g.fill();
  // ground
  px(0, GROUND, W, H - GROUND, night ? '#3b4a32' : '#7fb35a');
  for (let x = 0; x < W; x += 6) px(x + ((x * 7) % 3), GROUND - 2, 2, 2, night ? '#4e6040' : '#9ccc6c');
  px(0, GROUND + 18, W, H, night ? '#2d2a24' : '#8a6a48');
  // moss patch (left), brighter when watered
  const m = S.moss, mossC = m > 0.6 ? '#7cc46a' : m > 0.3 ? '#9cb85a' : '#b8a35a';
  for (let i = 0; i < 9; i++) px(36 + i * 6, GROUND - 6 - (i % 3) * 2 - m * 4, 6, 8 + (i % 3) * 2 + m * 4, mossC);
  if (m > 0.5) { px(48, GROUND - 16, 2, 6, '#5a9a3a'); px(46, GROUND - 18, 6, 3, '#f2f2f2'); }
  for (const d of S.drops) px(d.x, d.y, 2, 4, '#7ec8f0');

  // fireflies
  for (const b of S.bugs) { const gl = 0.5 + 0.5 * Math.sin(now() * 4 + b.ph); g.fillStyle = `rgba(255,236,140,${(night ? 0.45 : 0.22) * gl})`; g.beginPath(); g.arc(b.x, b.y, 5, 0, 7); g.fill(); px(b.x - 1, b.y - 1, 2, 2, night ? '#fff6b0' : '#e8c84a'); }
  // the rim firefly (dial only)
  const f = firefly(), glow = 0.6 + 0.4 * Math.sin(now() * 6);
  if (!S.menu && LAYOUT === 'dial') { g.fillStyle = `rgba(255,240,150,${0.25 * glow})`; g.beginPath(); g.arc(f.x, f.y, 9, 0, 7); g.fill(); px(f.x - 2, f.y - 2, 4, 4, '#fff6b0'); }

  // berry
  if (S.berry) { px(S.berry.x - 4, S.berry.y - 6, 8, 8, '#d8344a'); px(S.berry.x - 2, S.berry.y - 5, 2, 2, '#ff9aa8'); px(S.berry.x, S.berry.y - 9, 2, 3, '#4a8a3a'); }

  // gremlet
  if (S.sheet) {
    const tg = S.sheet.tags[S.anim]; const idx = tg.from + S.frame;
    const dw = 32 * SCALE, dx = Math.round(S.x - dw / 2), dy = Math.round(S.y - dw + 6);
    g.save();
    if (S.facing < 0) { g.translate(dx + dw, dy); g.scale(-1, 1); g.drawImage(S.sheet.img, idx * 32, 0, 32, 32, 0, 0, dw, dw); }
    else g.drawImage(S.sheet.img, idx * 32, 0, 32, 32, dx, dy, dw, dw);
    g.restore();
    if (S.mode === 'sleep' && S.anim === 'sleep') { const z = (now() % 2) / 2; g.fillStyle = night ? '#cfd6ff' : '#5a6a8a'; g.font = 'bold 12px ui-monospace, monospace'; g.fillText('z', S.x + 22, S.y - 70 - z * 16); g.fillText('Z', S.x + 30, S.y - 82 - z * 16); }
  }
  for (const h of S.hearts) heart(h.x, h.y, '#ff6f91');
  for (const p of S.sparks) px(p.x, p.y, 2, 2, p.life > 0.5 ? '#fff3a0' : '#ffd24d');

  // status pips (top): belly + moss
  const PY = LAYOUT === 'keypad' ? 8 : 30; const pip = (x, v, c) => { px(x, PY, 26, 5, 'rgba(0,0,0,.25)'); px(x, PY, Math.round(26 * v), 5, c); };
  pip(CX - 36, S.fullness, '#e2513f'); pip(CX + 10, S.moss, '#7cc46a');

  // Claude badge
  g.font = 'bold 11px ui-monospace, monospace'; g.textAlign = 'center';
  if (S.claude === 'working') { const d = '.'.repeat(1 + Math.floor(now() * 2) % 3); g.fillStyle = night ? '#e7e2ff' : '#3a3550'; g.fillText('Claude is working' + d, CX, LAYOUT === 'keypad' ? 26 : 52); }
  if (S.claude === 'done') { g.fillStyle = '#2e7d32'; g.fillText('Claude is done!', CX, LAYOUT === 'keypad' ? 26 : 52); }
  if (S.claude === 'needs') { g.fillStyle = (Math.floor(now() * 3) % 2) ? '#c0392b' : '#7a2a1f'; g.fillText('Claude needs you', CX, LAYOUT === 'keypad' ? 26 : 52); g.strokeStyle = 'rgba(220,60,40,.7)'; g.lineWidth = 4; g.beginPath(); if (LAYOUT === 'keypad') g.strokeRect(2, 2, W - 4, H - 4); else g.arc(CX, CY, 114, 0, 7); g.stroke(); }

  // clock
  if (now() < S.clockUntil) {
    const d = simDate(); px(CX - 70, CY - 36, 140, 40, 'rgba(20,18,16,.75)');
    g.fillStyle = '#fff'; g.font = 'bold 26px ui-monospace, monospace';
    g.fillText(d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }), CX, CY - 6);
  }

  // menu: a ring of choices, the ring selects
  if (S.menu) {
    g.fillStyle = 'rgba(20,18,16,.55)'; g.fillRect(0, 0, W, H);
    const items = S.menu.items, n = items.length;
    items.forEach((it, i) => {
      const a = (i / n) * Math.PI * 2 - Math.PI / 2;
      const x = LAYOUT === 'keypad' ? 28 + i * 46 : CX + Math.cos(a) * 72, y = LAYOUT === 'keypad' ? CY : CY + Math.sin(a) * 72;
      const on = i === S.menu.sel;
      g.fillStyle = on ? '#7cc46a' : 'rgba(255,255,255,.18)'; g.beginPath(); g.arc(x, y, on ? 24 : 20, 0, 7); g.fill();
      g.fillStyle = on ? '#1b1a18' : '#f3ecd6'; g.font = `bold ${on ? 11 : 10}px ui-monospace, monospace`; g.fillText(it, x, y + 4);
    });
    g.fillStyle = '#f3ecd6'; g.font = 'bold 12px ui-monospace, monospace'; g.fillText(LAYOUT === 'keypad' ? 'turn, then press the knob' : 'press to pick', CX, LAYOUT === 'keypad' ? CY + 44 : CY + 4);
  }
  g.textAlign = 'left';
  if (S.flash > 0) { g.fillStyle = `rgba(255,255,255,${S.flash * 0.6})`; g.fillRect(0, 0, W, H); }
}

// ---------------------------------------------------------------- loop
let last = now();
function frame() {
  const t = now(), dt = Math.min(0.05, t - last); last = t;
  update(dt); draw();
  requestAnimationFrame(frame);
}

(async () => {
  await buildCards();
  await adopt(S.id, true);
  pollClaude(); setInterval(pollClaude, 3000);
  requestAnimationFrame(frame);
})();
