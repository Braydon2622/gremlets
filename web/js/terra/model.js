// The Terrarium's story (web/terrarium.html): the Gremlets start in an empty white glass room and build everything up
// from there, a little at a time, faster while you (and Claude) are working.
//
// Growth comes in as points: a trickle just for being open, more while Claude thinks on the Mac, a burst each time a
// task finishes, and a little for playing with them. Points unlock the next project on the PLAN; the Gremlets then
// actually build it (their work moves its progress from 0 to 1), so you watch it come together. Moss spreads on its
// own as points add up: a tuft, the floor, up the glass, over the ceiling, until it's everywhere.
//
// No DOM here, so it runs in the plain JS test shell (web/tests/terra.test.mjs).

/**
 * The projects, in order. `at`: points needed before they start on it; `work`: Gremlet-seconds of building.
 * `kind` decides how it's drawn and what it adds (main.js). Positions are fractions of the room (x across, y up).
 */
export const PLAN = [
  { id: 'seed', kind: 'seed', at: 0, work: 6, x: 0.5, label: 'the first seed' },
  { id: 'sprig', kind: 'plants', at: 3, work: 6, n: 3, label: 'a few sprigs' },
  { id: 'deck1', kind: 'platform', at: 6, work: 26, x0: 0.05, x1: 0.30, y: 0.2, label: 'a twig ledge' },
  { id: 'tree', kind: 'tree', at: 10, work: 14, x: 0.5, label: 'a sapling' },
  { id: 'flowers', kind: 'plants', at: 14, work: 10, n: 5, label: 'flowers in the moss' },
  { id: 'deck2', kind: 'platform', at: 19, work: 28, x0: 0.70, x1: 0.95, y: 0.27, label: 'a second ledge' },
  { id: 'bugs', kind: 'critters', at: 24, work: 6, kinds: ['ladybug', 'snail'], label: 'the first critters' },
  { id: 'lanterns', kind: 'lanterns', at: 30, work: 12, label: 'little lanterns' },
  { id: 'deck3', kind: 'platform', at: 36, work: 30, x0: 0.08, x1: 0.36, y: 0.45, label: 'a high ledge' },
  { id: 'vines', kind: 'vines', at: 42, work: 10, label: 'vines from the ceiling' },
  { id: 'home1', kind: 'home', at: 48, work: 40, x: 0.22, y: 0.68, label: 'a hanging home' },
  { id: 'pond', kind: 'pond', at: 56, work: 24, x0: 0.62, x1: 0.86, label: 'a little pond' },
  { id: 'deck4', kind: 'platform', at: 63, work: 30, x0: 0.62, x1: 0.92, y: 0.45, label: 'the far ledge' },
  { id: 'flyers', kind: 'critters', at: 70, work: 6, kinds: ['bee', 'butterfly'], label: 'bees and butterflies' },
  { id: 'bridge', kind: 'bridge', at: 78, work: 32, from: 'deck3', to: 'deck4', label: 'a rope bridge' },
  { id: 'mushrooms', kind: 'plants', at: 86, work: 10, n: 6, glow: true, label: 'glowing mushrooms' },
  { id: 'home2', kind: 'home', at: 95, work: 44, x: 0.78, y: 0.7, label: 'a second home' },
  { id: 'falls', kind: 'waterfall', at: 106, work: 22, from: 'deck4', label: 'a waterfall' },
  { id: 'shroomhouse', kind: 'shroomhouse', at: 118, work: 40, x: 0.16, label: 'a mushroom house' },
  { id: 'fireflies', kind: 'critters', at: 130, work: 6, kinds: ['firefly', 'firefly', 'firefly'], label: 'fireflies' },
  { id: 'deck5', kind: 'platform', at: 142, work: 34, x0: 0.40, x1: 0.60, y: 0.62, label: 'a lookout' },
  { id: 'wheel', kind: 'waterwheel', at: 156, work: 30, label: 'a waterwheel' },
  { id: 'bloom', kind: 'lanternbloom', at: 172, work: 20, x: 0.5, label: 'a lanternbloom' },
  { id: 'garden', kind: 'plants', at: 190, work: 14, n: 8, label: 'a wild garden' },
  { id: 'crystal', kind: 'crystal', at: 210, work: 24, x: 0.88, label: 'a crystal' },
  { id: 'overgrown', kind: 'overgrown', at: 235, work: 20, label: 'moss everywhere' },
];

/** How points come in. */
export const RATES = {
  ambient: 1 / 240,      // a point every 4 minutes, just for being open
  thinking: 1 / 60,      // a point a minute per Claude session thinking
  done: 5,               // each finished task
  play: 0.05,            // a pet or a poke (capped below)
  playCap: 3,            // most points from play per hour
};

export class TerraModel {
  constructor(saved = null) {
    const s = saved && typeof saved === 'object' ? saved : {};
    this.points = Number.isFinite(s.points) ? Math.max(0, s.points) : 0;
    this.progress = {};
    for (const p of PLAN) {
      const v = s.progress?.[p.id];
      if (Number.isFinite(v)) this.progress[p.id] = Math.min(1, Math.max(0, v));
    }
    this.moss = Number.isFinite(s.moss) ? Math.min(1, Math.max(0, s.moss)) : 0;
    this.tasks = Number.isFinite(s.tasks) ? s.tasks : 0;
    this.lastDoneAt = Number.isFinite(s.lastDoneAt) ? s.lastDoneAt : 0;
    this.play = { hour: 0, got: 0 };
    this.events = [];   // { type: 'started'|'built'|'points', id?, n? } for the renderer
  }

  toJSON() { return { points: Math.round(this.points * 1000) / 1000, progress: this.progress, moss: Math.round(this.moss * 1000) / 1000, tasks: this.tasks, lastDoneAt: this.lastDoneAt }; }

  /** Seconds pass: the trickle, Claude thinking, and the moss creeping towards where it should be. */
  tick(dt, { thinking = 0 } = {}) {
    this.add(dt * (RATES.ambient + thinking * RATES.thinking));
    const target = this.mossTarget();
    if (this.moss < target) this.moss = Math.min(target, this.moss + dt / 900);   // creeps (15 minutes from bare to full)
  }

  add(n) {
    const before = this.next()?.id;
    this.points += n;
    const now = this.next()?.id;
    if (now && now !== before && !(now in this.progress)) this.events.push({ type: 'unlocked', id: now });
  }

  /** A Claude task finished on the Mac (`at`: when, so the same one isn't counted twice). */
  taskDone(at) {
    if (at && at <= this.lastDoneAt) return false;
    if (at) this.lastDoneAt = at;
    this.tasks += 1;
    this.add(RATES.done);
    this.events.push({ type: 'points', n: RATES.done, why: 'done' });
    return true;
  }

  /** Playing with them (a little, capped per hour). */
  played(nowSec) {
    const hour = Math.floor(nowSec / 3600);
    if (this.play.hour !== hour) this.play = { hour, got: 0 };
    if (this.play.got + RATES.play > RATES.playCap + 1e-9) return;
    this.play.got += RATES.play;
    this.add(RATES.play);
  }

  /** Moss follows the seed: nothing before it, then up with the points (floor, walls, ceiling, everywhere). */
  mossTarget() {
    if (!this.done('seed')) return 0;
    return Math.min(1, 0.06 + this.points / 240);
  }

  done(id) { return (this.progress[id] ?? 0) >= 1; }
  started(id) { return id in this.progress; }
  built() { return PLAN.filter((p) => this.done(p.id)); }

  /** The project being worked on: the first unlocked one that isn't finished (in plan order). */
  next() { return PLAN.find((p) => this.points >= p.at && !this.done(p.id)) ?? null; }

  /** What comes after that, and how far the points are towards it (for the little progress leaf). */
  upcoming() {
    const p = PLAN.find((q) => this.points < q.at);
    if (!p) return null;
    const prev = [...PLAN].reverse().find((q) => q.at <= this.points)?.at ?? 0;
    return { project: p, frac: Math.min(1, (this.points - prev) / Math.max(1, p.at - prev)) };
  }

  /** Building: `amount` Gremlet-seconds on project `id`. True when that finished it. */
  work(id, amount) {
    const p = PLAN.find((q) => q.id === id);
    if (!p || this.done(id) || this.points < p.at) return false;
    if (!(id in this.progress)) { this.progress[id] = 0; this.events.push({ type: 'started', id }); }
    this.progress[id] = Math.min(1, this.progress[id] + amount / p.work);
    if (this.progress[id] >= 1) { this.events.push({ type: 'built', id }); return true; }
    return false;
  }

  drain() { const e = this.events; this.events = []; return e; }

  /** A name for how far along it is. */
  stage() {
    const n = this.built().length;
    if (n === 0) return 'An empty glass room';
    if (this.done('overgrown')) return 'Overgrown';
    if (n < 4) return 'First green';
    if (n < 9) return 'Taking root';
    if (n < 15) return 'A little village';
    if (n < 21) return 'Thriving';
    return 'Lush';
  }
}
