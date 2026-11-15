// The Terrarium's progression (web/js/terra/model.js).
import { TerraModel, PLAN, RATES } from '../js/terra/model.js';

let passed = 0, failed = 0;
const test = (name, fn) => { try { fn(); passed++; } catch (e) { failed++; print(`✘ ${name}: ${e.message}`); } };
const ok = (c, m) => { if (!c) throw new Error(m || 'expected true'); };

test('starts as an empty glass room: the seed first, no moss', () => {
  const m = new TerraModel();
  ok(m.next().id === 'seed' && m.moss === 0 && m.stage() === 'An empty glass room');
  m.tick(600); ok(m.moss === 0, 'no moss before the seed');
});

test('building takes Gremlet work, then the moss starts', () => {
  const m = new TerraModel();
  ok(!m.work('seed', 3)); ok(m.work('seed', 3), 'six seconds of work plants it');
  ok(m.done('seed'));
  m.tick(60); ok(m.moss > 0, 'moss creeps in');
  ok(m.drain().some((e) => e.type === 'built' && e.id === 'seed'));
});

test('points unlock projects in order; locked ones cannot be built', () => {
  const m = new TerraModel();
  m.work('seed', 6);
  ok(!m.work('deck1', 100), 'not unlocked yet');
  m.add(6);
  ok(m.next().id === 'sprig', 'earlier unlocked project first');
  m.work('sprig', 6);
  ok(m.next().id === 'deck1');
  ok(m.upcoming().project.id === 'tree');
});

test('a finished task is a burst, counted once', () => {
  const m = new TerraModel();
  ok(m.taskDone(1000) && !m.taskDone(1000) && !m.taskDone(999));
  ok(m.points === RATES.done && m.tasks === 1);
});

test('Claude thinking speeds things up; play is capped', () => {
  const a = new TerraModel(), b = new TerraModel();
  a.tick(3600); b.tick(3600, { thinking: 2 });
  ok(b.points > a.points * 5, `${a.points} vs ${b.points}`);
  const c = new TerraModel();
  for (let i = 0; i < 500; i++) c.played(10);
  ok(c.points <= RATES.playCap + 1e-9);
});

test('saves and restores; the whole plan can be finished; moss ends up everywhere', () => {
  const m = new TerraModel();
  m.add(1000);
  for (const p of PLAN) while (!m.done(p.id)) m.work(p.id, 5);
  ok(m.stage() === 'Overgrown' && m.next() === null);
  m.tick(3600); ok(m.moss === 1);
  const back = new TerraModel(JSON.parse(JSON.stringify(m)));
  ok(back.built().length === PLAN.length && back.points === m.points);
  ok(new TerraModel({ points: 'x', progress: { seed: 9 } }).progress.seed === 1, 'bad saves are cleaned');
});

print(`${passed} passed, ${failed} failed`);
if (failed) throw new Error('terra tests failed');
