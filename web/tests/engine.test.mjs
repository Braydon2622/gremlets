// Headless tests for web/js/engine.js. Run with:  scripts/test-web.sh
// (uses macOS's built-in JavaScriptCore shell, so no Node install is needed)
import { World, Species, V, buildSurfaces } from '../js/engine.js';

const log = typeof print === 'function' ? print : console.log;
let failures = 0, passed = 0;
function test(name, fn) {
  try { fn(); passed++; log(`✔ ${name}`); }
  catch (e) { failures++; log(`✘ ${name}: ${e.message}`); }
}
function expect(cond, msg) { if (!cond) throw new Error(msg || 'expectation failed'); }

function testSpecies(extra = {}) {
  const mask = Array(16).fill(true); mask[0] = false;
  return new Species({ id: 't', name: 'T', frameWidth: 4, frameHeight: 4, scale: 10,
    animations: { idle: { frames: [0], durations: [1] } }, masks: [mask], ...extra });
}
const screen = { x: 0, y: 0, w: 1000, h: 800 };
const steps = (w, n, dt = 1 / 60) => { for (let i = 0; i < n; i++) w.step(dt); };
function grounded(w, xs) {
  const cs = xs.map((x) => w.spawn(testSpecies(), V(x, 0)));
  steps(w, 5);
  cs.forEach((c) => c.set('idle', 30));
  return cs;
}

test('occluded window edge is split', () => {
  const s = buildSurfaces([screen], [{ id: 1, x: 200, y: 300, w: 100, h: 300 }, { id: 2, x: 100, y: 200, w: 400, h: 200 }]).filter((s) => s.owner === 2);
  expect(JSON.stringify(s.map((x) => [x.minX, x.maxX])) === '[[100,200],[300,500]]', JSON.stringify(s));
});

test('falls and lands on floor', () => {
  const w = new World(1); w.setEnvironment([screen], []);
  const c = w.spawn(testSpecies(), V(500, 600));
  steps(w, 90);
  expect(c.pos.y === 0 && c.ground === -1, `pos ${c.pos.y} ground ${c.ground}`);
});

test('rides a moving window and falls when it closes', () => {
  const w = new World(3);
  const win = { id: 9, x: 300, y: 100, w: 400, h: 300 };
  w.setEnvironment([screen], [win]);
  const c = w.spawn(testSpecies(), V(500, 700));
  steps(w, 40);
  expect(c.ground === 9, 'should land on window');
  const x0 = c.pos.x;
  w.setEnvironment([screen], [{ ...win, x: 350, y: 180 }]);
  expect(c.pos.y === 480 && c.pos.x === x0 + 50, `rode to ${c.pos.x},${c.pos.y}`);
  w.setEnvironment([screen], []);
  steps(w, 90);
  expect(c.pos.y === 0, 'fell to floor');
});

test('jump target reaches a surface above', () => {
  const w = new World(5);
  w.setEnvironment([screen], [{ id: 4, x: 550, y: 0, w: 300, h: 200 }]);
  const c = w.spawn(testSpecies(), V(400, 0));
  steps(w, 12);
  w.launch(c, w.jumpTarget(c));
  for (let i = 0; i < 240 && c.activity !== 'land'; i++) w.step(1 / 60);
  expect(c.ground === 4 && c.pos.y === 200, `ground ${c.ground} y ${c.pos.y}`);
});

test('per-pixel hit test', () => {
  const w = new World(7); w.setEnvironment([screen], []);
  const c = w.spawn(testSpecies(), V(100, 0)); steps(w, 30);
  expect(w.creatureAt(V(105, 15)) === c && w.creatureAt(V(150, 15)) === null);
});

test('hard landing makes dizzy', () => {
  const w = new World(11); w.setEnvironment([screen], []);
  const c = w.spawn(testSpecies(), V(500, 300)); c.vel = V(0, -2500);
  steps(w, 30);
  expect(c.activity === 'dizzy', c.activity);
});

test('rider moves with carrier', () => {
  const w = new World(21); w.setEnvironment([screen], []);
  const [base, rider] = grounded(w, [500, 600]);
  w.startStack(rider, base);
  for (let i = 0; i < 120 && rider.ground !== base.carrierOwner; i++) w.step(1 / 60);
  expect(rider.ground === base.carrierOwner, 'did not land on head');
  rider.set('idle', 30); base.facing = 1; base.set('walk', 30);
  const bx = base.pos.x, rx = rider.pos.x;
  steps(w, 30);
  expect(Math.abs((rider.pos.x - rx) - (base.pos.x - bx)) < 1e-6 && base.pos.x > bx + 10, 'rider did not follow');
});

test('greeting makes both wave', () => {
  const w = new World(22); w.setEnvironment([screen], []);
  const [a, b] = grounded(w, [400, 560]);
  w.startGreet(a, b);
  let greeted = false;
  for (let i = 0; i < 300 && !greeted; i++) { w.step(1 / 60); greeted = w.drainEvents().some((e) => e.type === 'greet'); }
  expect(greeted && a.activity === 'wave' && b.activity === 'wave');
});

test('flight lands on a window', () => {
  const w = new World(24);
  w.setEnvironment([screen], [{ id: 5, x: 300, y: 0, w: 400, h: 450 }]);
  const c = w.spawn(testSpecies({ flies: true }), V(150, 0)); steps(w, 5);
  w.startFlight(c);
  for (let i = 0; i < 600 && !(c.isGrounded && c.activity !== 'fly'); i++) w.step(1 / 60);
  expect(c.ground === 5 && c.pos.y === 450, `ground ${c.ground} y ${c.pos.y}`);
});

test('soak: 8 creatures, 10 simulated minutes', () => {
  const w = new World(99);
  const scr = { x: 0, y: 0, w: 1440, h: 860 };
  const win1 = { id: 1, x: 200, y: 100, w: 500, h: 380 }, win2 = { id: 2, x: 800, y: 50, w: 450, h: 520 };
  w.setEnvironment([scr], [win1, win2]);
  for (let i = 0; i < 8; i++) {
    const s = testSpecies({ flies: i % 3 === 0 }); s.scale = 12; s.headTop = 48;
    w.spawn(s, V(150 + i * 150, 700));
  }
  const counts = {};
  const dt = 1 / 30;
  for (let f = 0; f < 60 * 10 * 30; f++) {
    const t = f * dt;
    w.cursor = V(720 + 600 * Math.sin(t * 0.3), 300 + 200 * Math.sin(t * 0.17));
    if (f % 3 === 0) {
      win1.x = 200 + 150 * Math.sin(t * 0.2);
      const closed = Math.floor(t / 40) % 3 === 2;
      w.setEnvironment([scr], closed ? [{ ...win1 }] : [{ ...win1 }, win2]);
    }
    w.step(dt);
    for (const e of w.drainEvents()) counts[e.type] = (counts[e.type] || 0) + 1;
    for (const c of w.creatures) {
      if (!Number.isFinite(c.pos.x) || !Number.isFinite(c.pos.y)) throw new Error('NaN position');
      if (c.pos.x < -1 || c.pos.x > scr.w + 1 || c.pos.y < -1 || c.pos.y > scr.h + 1) throw new Error(`left screen ${JSON.stringify(c.pos)}`);
    }
  }
  log('  soak counts: ' + JSON.stringify(counts));
  for (const k of ['greet', 'special', 'tookOff', 'danceBeat', 'fellAsleep', 'landed']) expect(counts[k] > 0, `never saw ${k}`);
});

log(`\n${passed} passed, ${failures} failed`);
if (failures) throw new Error(`${failures} test(s) failed`);
