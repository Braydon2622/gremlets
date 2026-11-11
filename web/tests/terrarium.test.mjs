// The Terrarium's clock and status-note handling (web/js/terrarium.js), in a plain JS shell (no DOM, no WebCrypto:
// the sealing round trip runs in the browser test, web/tests/terrarium_spec.py).
import { Terrarium, phaseAt, shiftAt } from '../js/terrarium.js';

let passed = 0, failed = 0;
const test = (name, fn) => { try { fn(); passed++; } catch (e) { failed++; print(`✘ ${name}: ${e.message}`); } };
const ok = (c, m) => { if (!c) throw new Error(m || 'expected true'); };
globalThis.location ??= { search: '' };

test('day, dusk and night by the hour; up at 7', () => {
  ok(phaseAt(12) === 'day' && phaseAt(7) === 'day');
  ok(phaseAt(18) === 'dusk' && phaseAt(20) === 'dusk');
  ok(phaseAt(21) === 'night' && phaseAt(3) === 'night' && phaseAt(6) === 'night');
});

test('the burn-in shift stays within a few pixels and moves each hour', () => {
  const seen = new Set();
  for (let h = 0; h < 24; h++) { const s = shiftAt(h); ok(Math.abs(s.x) <= 6 && Math.abs(s.y) <= 4); seen.add(`${s.x},${s.y}`); }
  ok(seen.size >= 12);
});

test('a status note is cleaned up: unknown states dropped, names trimmed, five recent', () => {
  const t = new Terrarium({ world: { creatures: [] } });
  t.status({
    sessions: [{ id: 's1', project: 'Project 1', state: 'thinking' }, { id: 's2', project: 'x'.repeat(80), state: 'waiting' }, { id: 's3', project: 'P', state: 'hacked' }, null],
    recent: Array.from({ length: 9 }, (_, i) => ({ project: 'P' + i, state: 'done', at: 100 + i })),
  });
  ok(t.sessions.length === 2, 'two sessions');
  ok(t.sessions[1].project.length === 32, 'trimmed');
  ok(t.recent.length === 5 && t.recent[4].project === 'P8', 'last five');
  t.status({ sessions: [], recent: [] });
  ok(t.sessions.length === 0 && t.helpers.size === 0, 'cleared');
});

print(`${passed} passed, ${failed} failed`);
if (failed) throw new Error('terrarium tests failed');
