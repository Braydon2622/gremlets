// Gremlets engine: JavaScript port of the Swift `GremletsCore` module.
// Same rules, same tuning, same behaviors, so a Gremlet acts the same on the desktop and on the web.
// World coordinates are points with y pointing UP (like macOS screen space); renderers flip as needed.
// No DOM access in this file, so it runs in browsers and in a plain JS shell (see web/tests).

// ---------------------------------------------------------------- math helpers
export const V = (x, y) => ({ x, y });
const add = (a, b) => V(a.x + b.x, a.y + b.y);
const sub = (a, b) => V(a.x - b.x, a.y - b.y);
const mul = (a, s) => V(a.x * s, a.y * s);
const len = (a) => Math.hypot(a.x, a.y);
const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

/** Small seedable RNG (mulberry32) so behavior is reproducible in tests. */
export class RNG {
  constructor(seed = (Math.random() * 2 ** 32) >>> 0) { this.s = seed >>> 0 || 1; }
  next() {
    let t = (this.s = (this.s + 0x6d2b79f5) >>> 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  range(a, b) { return a + (b - a) * this.next(); }
  chance(p) { return this.next() < p; }
  pick(arr) { return arr[Math.floor(this.next() * arr.length)]; }
}

// ---------------------------------------------------------------- surfaces
// A surface is a one-way horizontal platform: { owner, kind: 'floor'|'top'|'creature', y, minX, maxX }.
// Screens and "windows" are rects { x, y, w, h } (y = bottom edge).

const MIN_SEGMENT = 24;

function subtractSpan(spans, lo, hi) {
  const out = [];
  for (const s of spans) {
    if (hi <= s.lo || lo >= s.hi) { out.push(s); continue; }
    if (lo > s.lo) out.push({ lo: s.lo, hi: lo });
    if (hi < s.hi) out.push({ lo: hi, hi: s.hi });
  }
  return out;
}

/** Floors for every screen plus the visible (un-occluded) top edge of every window, front-most first. */
export function buildSurfaces(screens, windowsFrontToBack, headroom = 40) {
  const out = screens.map((s, i) => ({ owner: -(i + 1), kind: 'floor', y: s.y, minX: s.x, maxX: s.x + s.w }));
  windowsFrontToBack.forEach((win, i) => {
    const y = win.y + win.h;
    const scr = screens.find((s) => y > s.y + 1 && y <= s.y + s.h - headroom && win.x + win.w > s.x && win.x < s.x + s.w);
    if (!scr) return;
    let spans = [{ lo: Math.max(win.x, scr.x), hi: Math.min(win.x + win.w, scr.x + scr.w) }];
    for (const front of windowsFrontToBack.slice(0, i)) {
      if (front.y < y + 2 && front.y + front.h > y - 2) spans = subtractSpan(spans, front.x, front.x + front.w);
      if (!spans.length) break;
    }
    for (const sp of spans) {
      if (sp.hi - sp.lo >= MIN_SEGMENT) out.push({ owner: win.id, kind: 'top', y, minX: sp.lo, maxX: sp.hi });
    }
  });
  return out;
}

const supports = (s, x) => x >= s.minX && x <= s.maxX;

// ---------------------------------------------------------------- species

const FALLBACKS = {
  land: ['react', 'idle'], react: ['idle'], drag: ['fall', 'jump', 'idle'], fall: ['jump', 'idle'], jump: ['fall', 'idle'],
  sleep: ['idle'], walk: ['idle'], look: ['idle'], crouch: ['land', 'idle'], pet: ['react', 'idle'], yawn: ['sleep', 'idle'],
  wake: ['react', 'idle'], dizzy: ['land', 'idle'], alert: ['react', 'idle'], fly: ['jump', 'idle'], special: ['react', 'idle'],
  dance: ['react', 'idle'], wave: ['react', 'idle'], run: ['walk', 'idle'],
};

export class Species {
  /**
   * @param {object} o  id, name, element, family, description, frameWidth, frameHeight, scale,
   *                    animations {name: {frames, durations}}, masks [[bool]], walkSpeed, jumpPower, sleepiness, flies, special
   */
  constructor(o) {
    Object.assign(this, { walkSpeed: 70, jumpPower: 1, sleepiness: 1, flies: false, special: 'sparkle', scale: 3, family: '', element: '', description: '' }, o);
    // Height of the solid top of the head above the feet (where a friend can stand).
    let top = this.frameHeight * 0.6;
    const idle = this.animations.idle?.frames[0];
    if (idle != null && this.masks[idle]) {
      const m = this.masks[idle];
      for (let row = 0; row < this.frameHeight; row++) {
        let filled = 0;
        for (let x = 0; x < this.frameWidth; x++) if (m[row * this.frameWidth + x]) filled++;
        if (filled >= this.frameWidth / 4) { top = this.frameHeight - row; break; }
      }
    }
    this.headTop = top * this.scale;
  }
  get size() { return V(this.frameWidth * this.scale, this.frameHeight * this.scale); }
  animation(name) {
    if (this.animations[name]) return this.animations[name];
    for (const alt of FALLBACKS[name] || []) if (this.animations[alt]) return this.animations[alt];
    return this.animations.idle || Object.values(this.animations)[0] || { frames: [0], durations: [1] };
  }
  total(name) { return this.animation(name).durations.reduce((a, b) => a + b, 0); }
  frame(name, t, loop = true) {
    const a = this.animation(name);
    if (a.frames.length <= 1) return a.frames[0] ?? 0;
    const tot = a.durations.reduce((x, y) => x + y, 0);
    let local = loop ? t % tot : Math.min(t, tot - 0.0001);
    for (let i = 0; i < a.durations.length; i++) {
      if (local < a.durations[i]) return a.frames[i];
      local -= a.durations[i];
    }
    return a.frames[a.frames.length - 1];
  }
}

// ---------------------------------------------------------------- creature

const ONE_SHOT = new Set(['yawn', 'wake', 'react', 'land', 'alert', 'crouch', 'special']);
const ANIM_FOR = {
  walk: 'walk', chase: 'walk', follow: 'walk', peek: 'walk', crouch: 'crouch', land: 'land', sleep: 'sleep', react: 'react',
  pet: 'pet', yawn: 'yawn', wake: 'wake', dizzy: 'dizzy', alert: 'alert', dragged: 'drag', fly: 'fly', special: 'special',
  dance: 'dance', wave: 'wave', run: 'run',
};

export class Creature {
  constructor(id, species, pos) {
    Object.assign(this, {
      id, species, pos, vel: V(0, 0), facing: 1, activity: 'airborne', timer: 0, animTime: 0, ground: null, energy: 1,
      pendingLaunch: V(0, 0), targetX: null, petAmount: 0, edgeDecided: false, grabOffset: V(0, 0), idleVariant: 'idle',
      prevPos: pos, friend: null, social: 'none', flyTarget: null, peekX: null, lastGreet: {}, bumpCd: 0, startleCd: 0,
      tagImmunity: 0, beatTimer: 0, animSpeed: 1,
      // A sprout errand (water it, or pick / eat / blow it, then maybe hand it to a friend) and what's held overhead.
      task: null, carrying: null,
    });
  }
  get size() { return this.species.size; }
  get carrierOwner() { return World.creatureOwner(this.id); }
  get isGrounded() { return this.ground != null && !['airborne', 'dragged', 'fly'].includes(this.activity); }
  get isAsleep() { return this.activity === 'sleep' || this.activity === 'yawn'; }
  get animationName() {
    if (this.activity === 'idle') return this.idleVariant;
    if (this.activity === 'airborne') return this.vel.y > -600 ? 'jump' : 'fall';
    return ANIM_FOR[this.activity] || 'idle';
  }
  get currentFrame() { return this.species.frame(this.animationName, this.animTime, !ONE_SHOT.has(this.activity)); }
  get bounds() { return { x: this.pos.x - this.size.x / 2, y: this.pos.y, w: this.size.x, h: this.size.y }; }

  /** Per-pixel hit test against the current frame's alpha mask, with 1px of slack. */
  hitTest(p) {
    const b = this.bounds;
    if (p.x < b.x || p.x >= b.x + b.w || p.y < b.y || p.y >= b.y + b.h) return false;
    const sp = this.species, fw = sp.frameWidth, fh = sp.frameHeight;
    let col = Math.floor((p.x - b.x) / sp.scale);
    const row = Math.floor((b.y + b.h - p.y) / sp.scale);
    if (this.facing < 0) col = fw - 1 - col;
    const mask = sp.masks[this.currentFrame];
    if (!mask) return true;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const c = col + dx, r = row + dy;
      if (c >= 0 && c < fw && r >= 0 && r < fh && mask[r * fw + c]) return true;
    }
    return false;
  }
  animationLength(a) {
    const saved = this.activity;
    this.activity = a;
    const n = this.animationName;
    this.activity = saved;
    return this.species.total(n);
  }
  set(a, duration = 0) {
    if (a !== this.activity) this.animTime = 0;
    this.activity = a;
    this.timer = duration;
  }
}

// ---------------------------------------------------------------- world

export class World {
  static creatureOwner(id) { return -1000 - id; }
  static carrierId(owner) { return owner != null && owner <= -1000 ? -1000 - owner : null; }

  constructor(seed) {
    Object.assign(this, {
      gravity: 2200, maxFallSpeed: 2600, maxJumpHeight: 320, maxJumpDistance: 420, energyDrain: 0.0045,
      dizzyImpact: 1700, flySpeed: 210, bumpChance: 0.35,
      screens: [], windows: new Map(), surfaces: [], creatures: [], cursor: null, events: [],
      rng: new RNG(seed), nextId: 1, dragSamples: [], clock: 0, lastCursor: null, cursorSpeed: 0,
      // Sprouts in the moss on mossy windows (the web's branches). The renderer sets the moss and the hooks.
      sprouts: [], sproutEvents: [], nextSproutID: 0, nextSproutAt: 0, sproutWatered: {}, pendingSeeds: [], seedSpots: [],
      mossMinutes: 0, mossCare: 0.5, mossThirsty: false, claudeWorking: false,
      sproutSpotOK: null,   // (windowID, x) => false keeps sprouts off a spot (under the bonsai's pot, say)
      canTend: null,        // (creature) => false keeps one out of sprout errands (the one you're driving, visitors)
    });
  }

  // ---- environment
  setEnvironment(screens, windowsFrontToBack) {
    const next = new Map(windowsFrontToBack.map((w) => [w.id, w]));
    for (const c of this.creatures) {
      if (!c.isGrounded || c.ground == null || c.ground < 0) continue;
      const old = this.windows.get(c.ground), now = next.get(c.ground);
      if (!old || !now) continue;
      const d = V(now.x - old.x, now.y + now.h - (old.y + old.h));
      c.pos = add(c.pos, d);
      for (const r of this.creatures) if (r.ground === c.carrierOwner) r.pos = add(r.pos, d);
    }
    this.screens = screens;
    this.windows = next;
    this.surfaces = buildSurfaces(screens, windowsFrontToBack);
  }

  // ---- creatures
  spawn(species, at) {
    const s = this.screens[0];
    const start = at || (s ? V(this.rng.range(s.x + 80, Math.max(s.x + 81, s.x + s.w - 80)), s.y + s.h - species.size.y - 10) : V(0, 0));
    const c = new Creature(this.nextId++, species, start);
    c.facing = this.rng.chance(0.5) ? 1 : -1;
    this.creatures.push(c);
    return c;
  }
  remove(id) {
    this.creatures = this.creatures.filter((c) => c.id !== id);
    for (const c of this.creatures) if (c.friend === id) this.endSocial(c);
  }
  creatureAt(p) { for (let i = this.creatures.length - 1; i >= 0; i--) if (this.creatures[i].hitTest(p)) return this.creatures[i]; return null; }
  byId(id) { return id == null ? null : this.creatures.find((c) => c.id === id) || null; }
  emit(type, data = {}) { this.events.push({ type, ...data }); }
  drainEvents() { const e = this.events; this.events = []; return e; }

  // ---- input
  poke(c) {
    if (!c.isGrounded) return;
    if (c.isAsleep) { c.set('wake', c.animationLength('wake')); this.emit('wokeUp', { id: c.id }); return; }
    c.energy = Math.min(1, c.energy + 0.1);
    this.endSocial(c);
    c.set('react', c.animationLength('react') + 0.15);
    this.emit('poked', { id: c.id });
  }
  pet(c, distance) {
    if (!c.isGrounded || ['react', 'wake', 'dizzy', 'run'].includes(c.activity)) return;
    c.petAmount += distance;
    if (c.petAmount > 220) {
      c.petAmount = 0;
      if (c.activity === 'sleep') return;
      c.energy = Math.min(1, c.energy + 0.05);
      this.endSocial(c);
      c.set('pet', 1.4);
      this.emit('petted', { id: c.id });
    }
  }
  beginDrag(c, p, t) {
    c.grabOffset = sub(c.pos, p); c.ground = null; c.vel = V(0, 0);
    this.endSocial(c); c.set('dragged'); this.dragSamples = [{ t, p }];
  }
  drag(c, p, t) {
    if (c.activity !== 'dragged') return;
    const np = add(p, c.grabOffset);
    if (np.x !== c.pos.x) c.facing = np.x > c.pos.x ? 1 : -1;
    c.pos = np;
    this.dragSamples.push({ t, p });
    this.dragSamples = this.dragSamples.filter((s) => t - s.t <= 0.1);
  }
  endDrag(c, t) {
    if (c.activity !== 'dragged') return;
    let v = V(0, 0);
    const f = this.dragSamples[0], l = this.dragSamples[this.dragSamples.length - 1];
    if (f && l && l.t - f.t > 0.01 && t - l.t < 0.08) v = mul(sub(l.p, f.p), 1 / (l.t - f.t));
    const n = len(v);
    if (n > 2400) v = mul(v, 2400 / n);
    c.vel = v; c.set('airborne'); this.dragSamples = [];
  }

  // ---- simulation
  step(rawDt) {
    const dt = Math.min(Math.max(rawDt, 0), 1 / 20);
    this.clock += dt;
    if (this.cursor) {
      if (this.lastCursor && dt > 0) this.cursorSpeed = this.cursorSpeed * 0.5 + (len(sub(this.cursor, this.lastCursor)) / dt) * 0.5;
      this.lastCursor = this.cursor;
    }
    for (const c of this.creatures) c.prevPos = c.pos;
    for (const c of [...this.creatures].sort((a, b) => a.pos.y - b.pos.y)) this.update(c, dt);
    this.resolveBumps();
    this.checkStartle();
    this.updateSprouts(dt);
  }

  update(c, dt) {
    c.animTime += dt * c.animSpeed;
    c.bumpCd = Math.max(0, c.bumpCd - dt);
    c.startleCd = Math.max(0, c.startleCd - dt);
    c.tagImmunity = Math.max(0, c.tagImmunity - dt);
    if (c.activity === 'sleep') c.energy = Math.min(1, c.energy + dt * 0.06);
    else if (c.activity !== 'dragged') {
      const busy = ['walk', 'chase', 'run', 'fly', 'dance'].includes(c.activity);
      c.energy = Math.max(0, c.energy - dt * this.energyDrain * (busy ? 1.6 : 1));
    }
    if (c.activity === 'dragged') return;
    if (c.activity === 'airborne') { this.integrateAirborne(c, dt); return; }
    if (c.activity === 'fly') { c.timer -= dt; this.updateFlight(c, dt); return; }

    const carrier = this.byId(World.carrierId(c.ground));
    if (carrier) c.pos = add(c.pos, sub(carrier.pos, carrier.prevPos));

    const support = this.supportingSurface(c);
    if (!support) {
      const walking = ['walk', 'chase', 'run', 'follow', 'peek'].includes(c.activity);
      c.ground = null;
      c.vel = V(walking ? c.facing * c.species.walkSpeed * 0.6 : 0, 0);
      if (c.isAsleep) this.emit('wokeUp', { id: c.id });
      this.endSocial(c);
      c.set('airborne');
      return;
    }
    c.pos = V(c.pos.x, support.y);
    c.ground = support.owner;

    c.timer -= dt;
    switch (c.activity) {
      case 'idle': this.faceCursorIfNear(c); break;
      case 'walk': case 'chase': this.walk(c, dt, support); break;
      case 'follow': this.updateFollow(c, dt, support); break;
      case 'run': this.updateTag(c, dt, support); break;
      case 'peek': this.updatePeek(c, dt); break;
      case 'dance':
        c.beatTimer -= dt;
        if (c.beatTimer <= 0) { c.beatTimer = 0.55; this.emit('danceBeat', { id: c.id }); }
        break;
      case 'crouch':
        if (c.timer <= 0) {
          c.vel = c.pendingLaunch;
          if (Math.abs(c.vel.x) > 1) c.facing = c.vel.x > 0 ? 1 : -1;
          c.ground = null; c.pos = V(c.pos.x, c.pos.y + 1); c.set('airborne');
        }
        return;
      case 'yawn':
        if (c.timer <= 0) { c.set('sleep', this.rng.range(12, 28) * clamp(c.species.sleepiness, 0.6, 1.6)); this.emit('fellAsleep', { id: c.id }); }
        return;
      case 'sleep':
        if (c.timer <= 0 || c.energy >= 1) { c.set('wake', c.animationLength('wake')); this.emit('wokeUp', { id: c.id }); }
        return;
      case 'alert':
        if (c.timer <= 0) c.set('chase', 6);
        return;
    }
    if (c.timer <= 0) {
      if (c.activity === 'run') this.endTag(c);
      this.endSocial(c);
      if (c.task == null) c.carrying = null;
      if (c.task) this.taskDecide(c); else this.decide(c);
    }
  }

  /** Horizontal move with walls and ledges; returns false if it turned around. */
  move(c, dt, speed, support, ledgeTurnChance = 0.65) {
    const nx = c.pos.x + c.facing * speed * dt;
    const [lo, hi] = this.horizontalLimits(c, c.pos.y + 1);
    if (nx < lo || nx > hi) { c.facing *= -1; return false; }
    if (!supports(support, nx) && !c.edgeDecided) {
      c.edgeDecided = true;
      if (this.rng.chance(ledgeTurnChance)) { c.facing *= -1; return false; }
    }
    if (supports(support, nx)) c.edgeDecided = false;
    c.pos = V(nx, c.pos.y);
    return true;
  }

  walk(c, dt, support) {
    if (c.activity === 'walk' && c.task && c.targetX != null) {
      // On an errand: straight to the spot, no dithering at ledges.
      if (Math.abs(c.targetX - c.pos.x) < 5) { c.targetX = null; c.set('idle', 0.05); return; }
      c.facing = c.targetX > c.pos.x ? 1 : -1;
      if (!this.move(c, dt, c.species.walkSpeed * 1.15, support, 0)) { c.targetX = null; c.set('idle', 0.3); }
      return;
    }
    if (c.activity === 'chase') {
      if (this.cursor && Math.abs(this.cursor.y - c.pos.y) < 260) c.targetX = this.cursor.x;
      if (c.targetX != null) {
        if (Math.abs(c.targetX - c.pos.x) < 14) { c.set('react', c.animationLength('react') + 0.15); this.emit('poked', { id: c.id }); return; }
        c.facing = c.targetX > c.pos.x ? 1 : -1;
      }
    }
    const chase = c.activity === 'chase';
    if (!this.move(c, dt, c.species.walkSpeed * (chase ? 1.6 : 1) * (c.speedBoost || 1), support, chase ? 1 : 0.65) && chase) c.set('idle', 1);
  }

  faceCursorIfNear(c) {
    const cur = this.cursor;
    if (!cur) return;
    const dx = cur.x - c.pos.x;
    if (Math.abs(dx) > 14 && Math.abs(dx) < 260 && Math.abs(cur.y - (c.pos.y + c.size.y / 2)) < 180) c.facing = dx > 0 ? 1 : -1;
  }

  integrateAirborne(c, dt) {
    const prev = c.pos;
    c.vel = V(c.vel.x, Math.max(c.vel.y - this.gravity * dt, -this.maxFallSpeed));
    let next = add(prev, mul(c.vel, dt));
    const [lo, hi] = this.horizontalLimits(c, next.y);
    if (next.x < lo || next.x > hi) {
      next = V(clamp(next.x, lo, hi), next.y);
      c.vel = V(-c.vel.x * 0.45, c.vel.y);
      c.facing = c.vel.x >= 0 ? 1 : -1;
    }
    const scr = this.screenAt(next.x, prev.y);
    if (scr && next.y + c.size.y > scr.y + scr.h) { next = V(next.x, scr.y + scr.h - c.size.y); c.vel = V(c.vel.x, Math.min(c.vel.y, 0) * 0.3); }

    if (c.vel.y <= 0) {
      let landing = null;
      for (const s of this.allSurfaces(c)) {
        if (prev.y >= s.y - 0.5 && next.y <= s.y && supports(s, next.x) && (!landing || s.y > landing.y)) landing = s;
      }
      if (landing) {
        const impact = -c.vel.y;
        c.pos = V(next.x, landing.y); c.vel = V(0, 0); c.ground = landing.owner; c.edgeDecided = false;
        this.emit('landed', { id: c.id, impact });
        const carrier = World.carrierId(landing.owner);
        if (carrier != null) { this.emit('stacked', { rider: c.id, carrier }); c.set('react', c.animationLength('react') + 0.1); }
        else if (impact > this.dizzyImpact) { c.set('dizzy', 1.9); this.emit('dizzy', { id: c.id }); }
        else c.set('land', impact > 900 ? Math.max(0.3, c.animationLength('land')) : 0.14);
        return;
      }
    }
    c.pos = next;
    if (this.screens.length) {
      const lowest = Math.min(...this.screens.map((s) => s.y));
      if (c.pos.y < lowest - 200) { const m = this.screens[0]; c.pos = V(m.x + m.w / 2, m.y + m.h - c.size.y - 10); c.vel = V(0, 0); }
    }
  }

  // ---- flight
  startFlight(c, awayFrom = null) {
    const opts = this.surfaces.filter((s) => {
      if (s.maxX - s.minX < 40) return false;
      const x = clamp(c.pos.x, s.minX + 20, s.maxX - 20);
      if (awayFrom && (x - awayFrom.x) * (c.pos.x - awayFrom.x) < 0) return false;
      return Math.abs(x - c.pos.x) < 800 && Math.abs(s.y - c.pos.y) > 20;
    });
    if (!opts.length) { this.launch(c, V(c.facing * 80, 500)); return; }
    const s = this.rng.pick(opts);
    const inset = Math.min(40, (s.maxX - s.minX) / 2 - 1);
    let tx = this.rng.range(s.minX + inset, s.maxX - inset);
    if (Math.abs(tx - c.pos.x) > 800) tx = clamp(c.pos.x, s.minX + inset, s.maxX - inset);
    c.flyTarget = V(tx, s.y); c.ground = null; c.vel = V(c.facing * 40, 220);
    c.facing = tx > c.pos.x ? 1 : -1;
    this.endSocial(c); c.set('fly', 7); this.emit('tookOff', { id: c.id });
  }

  updateFlight(c, dt) {
    const t = c.flyTarget;
    if (!t) { c.set('airborne'); return; }
    const to = sub(V(t.x, t.y + 34), c.pos), dist = len(to);
    const speed = Math.min(this.flySpeed, dist * 2.5 + 30);
    let desired = dist > 0.1 ? mul(to, speed / dist) : V(0, 0);
    desired = V(desired.x, desired.y + Math.sin(this.clock * 7 + c.id) * 45);
    const k = Math.min(1, 3.2 * dt);
    c.vel = add(c.vel, mul(sub(desired, c.vel), k));
    let next = add(c.pos, mul(c.vel, dt));
    const [lo, hi] = this.horizontalLimits(c, next.y);
    next = V(clamp(next.x, lo, hi), next.y);
    const scr = this.screenAt(next.x, next.y);
    if (scr && next.y + c.size.y > scr.y + scr.h) next = V(next.x, scr.y + scr.h - c.size.y);
    c.pos = next;
    if (Math.abs(c.vel.x) > 12) c.facing = c.vel.x > 0 ? 1 : -1;
    if (dist < 16 || c.timer <= 0) { c.flyTarget = null; c.vel = V(c.vel.x * 0.25, -60); c.set('airborne'); }
  }

  // ---- cursor startle & bumps
  checkStartle() {
    const cur = this.cursor;
    if (!cur || this.cursorSpeed < 2800) return;
    for (const c of this.creatures) {
      if (!c.isGrounded || c.isAsleep || c.startleCd > 0 || c.activity === 'dizzy') continue;
      if (len(sub(cur, V(c.pos.x, c.pos.y + c.size.y * 0.4))) >= 90) continue;
      c.startleCd = 6; this.emit('startled', { id: c.id }); this.endSocial(c);
      const away = cur.x < c.pos.x ? 1 : -1;
      c.facing = away;
      if (c.species.flies) this.startFlight(c, cur);
      else { c.ground = null; c.vel = V(away * 200, 460); c.set('airborne'); }
    }
  }

  resolveBumps() {
    const movers = this.creatures.filter((c) => ['walk', 'run', 'chase', 'follow', 'peek'].includes(c.activity) && c.isGrounded && c.bumpCd <= 0);
    for (let i = 0; i < movers.length; i++) for (let j = i + 1; j < movers.length; j++) {
      const a = movers[i], b = movers[j];
      if (a.bumpCd > 0 || b.bumpCd > 0 || Math.abs(a.pos.y - b.pos.y) >= 3) continue;
      const dx = b.pos.x - a.pos.x;
      if (Math.abs(dx) >= (a.size.x + b.size.x) * 0.2) continue;
      if (!(a.facing * dx > 0 && b.facing * -dx > 0)) continue;
      if ((a.social === 'chaser' && a.friend === b.id) || (b.social === 'chaser' && b.friend === a.id)) continue;
      a.bumpCd = 2; b.bumpCd = 2;
      if (!this.rng.chance(this.bumpChance)) continue;
      for (const [c, dir] of [[a, dx > 0 ? -1 : 1], [b, dx > 0 ? 1 : -1]]) {
        this.endSocial(c); c.bumpCd = 4; c.ground = null; c.vel = V(dir * 150, 340); c.set('airborne');
      }
      this.emit('bump', { a: a.id, b: b.id });
    }
  }

  // ---- queries
  allSurfaces(c) {
    const out = this.surfaces.slice();
    for (const o of this.creatures) {
      if (o === c || o.ground === c.carrierOwner || World.carrierId(o.ground) != null) continue;
      if (['airborne', 'fly', 'dragged'].includes(o.activity)) continue;
      const half = o.size.x * 0.17;
      out.push({ owner: o.carrierOwner, kind: 'creature', y: o.pos.y + o.species.headTop, minX: o.pos.x - half, maxX: o.pos.x + half });
    }
    return out;
  }
  supportingSurface(c) {
    const cands = this.allSurfaces(c).filter((s) => Math.abs(s.y - c.pos.y) <= 2 && supports(s, c.pos.x));
    return cands.find((s) => s.owner === c.ground) || cands.reduce((best, s) => (!best || s.y > best.y ? s : best), null);
  }
  screenAt(x, y) {
    return this.screens.find((s) => x >= s.x && x < s.x + s.w && y >= s.y - 2 && y < s.y + s.h) || this.screens.find((s) => x >= s.x && x < s.x + s.w) || null;
  }
  horizontalLimits(c, y, inset = true) {
    const half = inset ? c.size.x * 0.3 : 0;
    const scr = this.screenAt(c.pos.x, y) || this.screens[0];
    if (!scr) return [-Infinity, Infinity];
    let lo = scr.x, hi = scr.x + scr.w, changed = true;
    while (changed) {
      changed = false;
      for (const s of this.screens) {
        if (!(y >= s.y - 2 && y < s.y + s.h)) continue;
        if (Math.abs(s.x + s.w - lo) < 1 && s.x < lo) { lo = s.x; changed = true; }
        if (Math.abs(s.x - hi) < 1 && s.x + s.w > hi) { hi = s.x + s.w; changed = true; }
      }
    }
    return [lo + half, hi - half];
  }
  ballistic(p, tx, y, apexExtra = 40) {
    const dh = y - p.y, apex = Math.max(dh, 0) + apexExtra;
    const vy = Math.sqrt(2 * this.gravity * apex);
    const t = (vy + Math.sqrt(Math.max(0, vy * vy - 2 * this.gravity * dh))) / this.gravity;
    return V((tx - p.x) / t, vy);
  }
  jumpTarget(c) {
    const maxH = this.maxJumpHeight * c.species.jumpPower;
    const opts = this.surfaces.filter((s) => {
      const dh = s.y - c.pos.y;
      if (!(dh > 25 && dh < maxH && s.maxX - s.minX >= 40)) return false;
      return Math.abs(clamp(c.pos.x, s.minX + 16, s.maxX - 16) - c.pos.x) < this.maxJumpDistance;
    });
    if (!opts.length) return null;
    const s = this.rng.pick(opts);
    const inset = Math.min(60, (s.maxX - s.minX) / 2 - 1);
    let tx = clamp(c.pos.x, s.minX + inset, s.maxX - inset) + this.rng.range(-20, 20);
    tx = clamp(tx, s.minX + 12, s.maxX - 12);
    return this.ballistic(c.pos, tx, s.y);
  }
  launch(c, v) { c.pendingLaunch = v; c.set('crouch', 0.16); }

  // ---------------------------------------------------------------- social
  nearbyFriends(c, range = 360) {
    return this.creatures.filter((o) => o !== c && o.isGrounded && Math.abs(o.pos.y - c.pos.y) < 40 && Math.abs(o.pos.x - c.pos.x) < range);
  }
  endSocial(c) { c.social = 'none'; c.friend = null; c.animSpeed = 1; c.peekX = null; }

  startGreet(c, f) { c.social = 'greet'; c.friend = f.id; c.lastGreet[f.id] = this.clock; f.lastGreet[c.id] = this.clock; c.set('follow', 6); }
  startFollow(c, f) { c.social = 'follow'; c.friend = f.id; c.set('follow', this.rng.range(5, 9)); }
  startNap(c, f) { c.social = 'nap'; c.friend = f.id; c.set('follow', 8); }
  startTag(c, f) {
    const d = this.rng.range(7, 11);
    c.social = 'chaser'; c.friend = f.id; f.social = 'runner'; f.friend = c.id;
    c.set('run', d); f.set('run', d); f.tagImmunity = 0.8;
    this.emit('alert', { id: f.id });
  }
  startStack(c, f) { c.friend = f.id; this.launch(c, this.ballistic(c.pos, f.pos.x, f.pos.y + f.species.headTop, 30)); }
  startDance(c, duration = null, invite = true) {
    const d = duration ?? this.rng.range(3, 5);
    c.beatTimer = 0; c.set('dance', d);
    if (!invite) return;
    for (const f of this.nearbyFriends(c, 420)) {
      if (['idle', 'walk', 'follow'].includes(f.activity) && this.rng.chance(0.6)) {
        this.endSocial(f); f.facing = c.pos.x > f.pos.x ? 1 : -1; this.startDance(f, d, false);
      }
    }
  }
  startSpecial(c) { c.set('special', c.animationLength('special')); this.emit('special', { id: c.id, effect: c.species.special }); }
  startPeek(c) {
    if (c.ground == null || !(c.ground < 0 && c.ground > -1000)) return false;
    const [lo, hi] = this.horizontalLimits(c, c.pos.y + 1, false);
    const toLo = c.pos.x - lo, toHi = hi - c.pos.x;
    if (Math.min(toLo, toHi) >= 500) return false;
    c.peekX = toLo < toHi ? lo + c.size.x * 0.05 : hi - c.size.x * 0.05;
    c.facing = toLo < toHi ? -1 : 1;
    c.set('peek', 12);
    return true;
  }

  updateFollow(c, dt, support) {
    const f = this.byId(c.friend);
    if (!f || Math.abs(f.pos.y - c.pos.y) >= 50) { this.endSocial(c); this.decide(c); return; }
    const dx = f.pos.x - c.pos.x;
    const gap = c.social === 'follow' ? 80 : (c.size.x + f.size.x) * 0.3;
    if (Math.abs(dx) > gap + 4) {
      c.facing = dx > 0 ? 1 : -1;
      this.move(c, dt, c.species.walkSpeed * (Math.abs(dx) > 200 ? 1.3 : 1), support, 1);
      return;
    }
    c.facing = dx > 0 ? 1 : -1;
    if (c.social === 'greet') {
      c.set('wave', 1.4);
      if (['idle', 'walk', 'follow', 'wave'].includes(f.activity)) { this.endSocial(f); f.facing = -c.facing; f.set('wave', 1.4); }
      this.emit('greet', { a: c.id, b: f.id });
      this.endSocial(c);
    } else if (c.social === 'nap') {
      this.endSocial(c); c.set('yawn', c.animationLength('yawn'));
    }
  }
  updateTag(c, dt, support) {
    const f = this.byId(c.friend);
    if (!f || Math.abs(f.pos.y - c.pos.y) >= 80 || !['run', 'airborne'].includes(f.activity)) { this.endTag(c); return; }
    const dx = f.pos.x - c.pos.x;
    if (c.social === 'chaser') {
      c.facing = dx > 0 ? 1 : -1;
      this.move(c, dt, c.species.walkSpeed * 1.9 + 20, support, 0.3);
      if (Math.abs(dx) < (c.size.x + f.size.x) * 0.22 && f.tagImmunity <= 0 && f.isGrounded) {
        this.emit('tagged', { id: f.id });
        c.social = 'runner'; f.social = 'chaser'; c.tagImmunity = 0.9; c.facing = -c.facing;
      }
    } else {
      if (Math.abs(dx) < 220) c.facing = dx > 0 ? -1 : 1;
      if (!this.move(c, dt, c.species.walkSpeed * 1.7 + 15, support, 0.4) && Math.abs(dx) < 120) {
        c.ground = null; c.vel = V(c.facing * 160, 520); c.set('airborne');
      }
    }
  }
  endTag(c) {
    const f = this.byId(c.friend);
    if (f && f.friend === c.id && f.activity === 'run') { this.endSocial(f); f.set('react', f.animationLength('react')); }
    this.endSocial(c);
    if (c.isGrounded) c.set('react', c.animationLength('react'));
  }
  updatePeek(c, dt) {
    if (c.peekX == null) { this.endSocial(c); return; }
    const dx = c.peekX - c.pos.x;
    if (Math.abs(dx) > 3) {
      c.facing = dx > 0 ? 1 : -1;
      c.pos = V(c.pos.x + c.facing * Math.min(Math.abs(dx), c.species.walkSpeed * 0.7 * dt), c.pos.y);
      return;
    }
    c.facing = -c.facing; this.endSocial(c); c.idleVariant = 'look'; c.set('idle', 2.6);
  }

  // ---------------------------------------------------------------- brain (utility AI)
  decide(c) {
    const rng = this.rng, e = c.energy, choices = [];
    const add_ = (w, f) => { if (w > 0) choices.push([w, f]); };

    add_(1.0, () => { c.idleVariant = rng.chance(0.35) ? 'look' : 'idle'; c.set('idle', rng.range(1.2, 3.5)); });
    add_(1.3 * (0.4 + e), () => { c.facing = rng.chance(0.5) ? 1 : -1; c.edgeDecided = false; c.set('walk', rng.range(1.5, 4.5)); });
    add_(0.3 * e, () => { const h = rng.range(30, 60) * c.species.jumpPower; this.launch(c, V(c.facing * rng.range(40, 110), Math.sqrt(2 * this.gravity * h))); });
    const jt = this.jumpTarget(c);
    if (jt) add_(1.1 * (0.3 + e), () => this.launch(c, jt));
    if (c.species.flies) add_(0.8 * (0.3 + e), () => this.startFlight(c));
    add_(0.3 * (0.3 + e), () => this.startSpecial(c));
    add_(0.1 * e, () => this.startDance(c));
    if (e < 0.55) add_((0.55 - e) * 6 * c.species.sleepiness, () => c.set('yawn', c.animationLength('yawn')));
    {
      const [lo, hi] = this.horizontalLimits(c, c.pos.y + 1, false);
      if (Math.min(c.pos.x - lo, hi - c.pos.x) < 500 && (c.ground ?? 0) < 0) add_(0.18, () => { if (!this.startPeek(c)) c.set('idle', 1); });
    }
    const cur = this.cursor;
    if (cur && Math.abs(cur.y - c.pos.y) < 220) {
      const dx = Math.abs(cur.x - c.pos.x);
      if (dx > 40 && dx < 700) add_(0.4 * e, () => {
        c.targetX = cur.x; c.facing = cur.x > c.pos.x ? 1 : -1;
        c.set('alert', Math.max(0.3, c.animationLength('alert'))); this.emit('alert', { id: c.id });
      });
      if (dx < 240) add_(0.5, () => { c.facing = cur.x > c.pos.x ? 1 : -1; c.set('wave', 1.3); });
    }
    const friends = this.nearbyFriends(c);
    if (friends.length) {
      const awake = friends.filter((f) => !f.isAsleep && f.activity !== 'dizzy');
      const dancer = friends.find((f) => f.activity === 'dance');
      if (dancer) add_(1.4, () => { c.facing = dancer.pos.x > c.pos.x ? 1 : -1; this.startDance(c, Math.max(1.5, dancer.timer), false); });
      const greetable = awake.find((f) => this.clock - (c.lastGreet[f.id] ?? -999) > 90);
      if (greetable) add_(1.2, () => this.startGreet(c, greetable));
      if (awake.length) {
        add_(0.55 * e, () => {
          const f = rng.pick(awake);
          if (['idle', 'walk', 'follow', 'wave'].includes(f.activity)) this.startTag(c, f); else this.startFollow(c, f);
        });
        add_(0.4, () => this.startFollow(c, rng.pick(awake)));
      }
      const sleeper = friends.find((f) => f.activity === 'sleep');
      if (e < 0.75 && sleeper) add_(1.6, () => this.startNap(c, sleeper));
      const canStack = World.carrierId(c.ground) == null && !this.creatures.some((o) => o.ground === c.carrierOwner);
      if (canStack) {
        const bases = friends.filter((f) => ['idle', 'sleep'].includes(f.activity) && World.carrierId(f.ground) == null
          && !this.creatures.some((o) => o.ground === f.carrierOwner) && Math.abs(f.pos.x - c.pos.x) < 260);
        if (bases.length) add_(0.45 * (0.3 + e), () => this.startStack(c, rng.pick(bases)));
      }
    }
    this.sproutChoices(c, add_);
    const total = choices.reduce((s, [w]) => s + w, 0);
    let roll = rng.range(0, total);
    for (const [w, f] of choices) { roll -= w; if (roll <= 0) { f(); return; } }
    choices[choices.length - 1]?.[1]();
  }

  // ---------------------------------------------------------------- sprouts (port of the Mac's Sprouts.swift)
  // Little things come up in the moss on mossy windows: daisies, mushrooms, berry sprigs and dandelions. They sprout,
  // grow over a few minutes, and the Gremlets look after them: water the young ones, then pick the daisies and
  // mushrooms (and hand them to a friend), eat the berries, and blow the dandelion clocks. Ripe ones left too long wilt
  // or blow away by themselves. A sprout is { id, kind, windowID, offset (from the window's left edge), growth 0...1,
  // ripeAt }. Events go to `sproutEvents` (drained by the renderer), like the Mac's.

  static sproutLimit = 7;
  static sproutKinds = ['daisy', 'mushroom', 'berries', 'dandelion'];
  static sproutStage(sp) { return sp.growth >= 1 ? 2 : sp.growth >= 0.35 ? 1 : 0; }

  drainSproutEvents() { const e = this.sproutEvents; this.sproutEvents = []; return e; }
  sproutX(sp) { return (this.windows.get(sp.windowID)?.x ?? 0) + sp.offset; }
  /** A window sprouts can grow on: only mossy ones (the branches), never a bonsai pad or the house. */
  sproutHost(id) { const w = this.windows.get(id); return w && w.mossy ? w : null; }
  sproutTops(minWidth = 100) { return this.surfaces.filter((s) => s.kind === 'top' && this.sproutHost(s.owner) && s.maxX - s.minX >= minWidth); }
  sproutSpotFine(wid, x) {
    const w = this.sproutHost(wid);
    return !!w && x > w.x + 26 && x < w.x + w.w - 26 && (!this.sproutSpotOK || this.sproutSpotOK(wid, x));
  }
  /** A clear spot on a visible stretch of that window's top, not crowding another sprout. */
  sproutSpotFree(wid, x) {
    return this.sproutSpotFine(wid, x)
      && this.surfaces.some((s) => s.owner === wid && s.kind === 'top' && supports(s, x - 10) && supports(s, x + 10))
      && !this.sprouts.some((o) => o.windowID === wid && Math.abs(this.sproutX(o) - x) < 40);
  }
  isFree(c) { return !c.isAsleep && c.task == null && World.carrierId(c.ground) == null && (!this.canTend || this.canTend(c)); }
  tended(id) { return this.creatures.some((c) => c.task?.kind === 'sprout' && c.task.id === id); }

  updateSprouts(dt) {
    // Gone with its branch (mined, or the page resized under it).
    this.sprouts = this.sprouts.filter((sp) => this.sproutSpotFine(sp.windowID, this.sproutX(sp)));
    // Seeds drifting down onto another branch: the next sprouts tend to come up where they land.
    for (let i = this.pendingSeeds.length - 1; i >= 0; i--) {
      const seed = this.pendingSeeds[i];
      if (this.clock < seed.at) continue;
      this.pendingSeeds.splice(i, 1);
      const w = this.sproutHost(seed.window);
      if (!w) continue;
      this.seedSpots = [...this.seedSpots.filter((p) => !(p.window === seed.window && Math.abs(p.offset - seed.offset) < 60)), { window: seed.window, offset: seed.offset }].slice(-5);
      this.sproutEvents.push({ type: 'seedLanded', at: V(w.x + seed.offset, w.y + w.h) });
    }
    // Growing (not while the moss is parched).
    if (!this.mossThirsty) {
      const rate = dt / (this.claudeWorking ? 70 : 160) * (0.6 + this.mossCare * 0.6);
      for (const sp of this.sprouts) {
        if (sp.growth >= 1) continue;
        sp.growth = Math.min(1, sp.growth + rate);
        if (sp.growth >= 1) sp.ripeAt = this.clock;
      }
    }
    // Left too long: they look after themselves.
    for (let i = this.sprouts.length - 1; i >= 0; i--) {
      const sp = this.sprouts[i];
      if (sp.ripeAt == null || this.clock - sp.ripeAt <= 480 || this.tended(sp.id)) continue;
      this.sprouts.splice(i, 1);
      const w = this.windows.get(sp.windowID), p = V(this.sproutX(sp), w.y + w.h);
      if (sp.kind === 'dandelion') this.blowSeeds(p, null); else this.sproutEvents.push({ type: 'wilted', at: p });
    }
    // Something new comes up in the moss now and then (more often while Claude works).
    const limit = Math.min(World.sproutLimit, 2 + Math.floor(this.mossMinutes / 40));
    if (this.clock < this.nextSproutAt || this.mossMinutes < 12 || this.mossThirsty || this.sprouts.length >= limit) return;
    this.nextSproutAt = this.clock + (this.claudeWorking ? this.rng.range(15, 35) : this.rng.range(40, 90));
    // Mostly where a dandelion seed came down; otherwise anywhere along a mossy branch.
    const tops = this.sproutTops();
    let spot = null;
    for (let k = 0; k < 6 && !spot; k++) {
      let wid, x;
      const seed = this.seedSpots.length ? this.rng.pick(this.seedSpots) : null;
      if (seed && this.rng.chance(0.7) && this.sproutHost(seed.window)) {
        wid = seed.window; x = this.sproutHost(wid).x + seed.offset + this.rng.range(-30, 30);
      } else if (tops.length) {
        const t = this.rng.pick(tops);
        wid = t.owner; x = this.rng.range(t.minX + 30, t.maxX - 30);
      } else break;
      if (this.sproutSpotFree(wid, x)) spot = { wid, x };
    }
    if (!spot) return;
    const kinds = [['daisy', 1], ['mushroom', 0.8], ['berries', 0.8], ['dandelion', 1]];
    let r = this.rng.range(0, kinds.reduce((a, k) => a + k[1], 0));
    const kind = (kinds.find((k) => (r -= k[1]) <= 0) ?? kinds[0])[0];
    this.addSprout(kind, spot.wid, spot.x, 0.02);
  }

  addSprout(kind, wid, x, growth) {
    const w = this.windows.get(wid);
    const sp = { id: ++this.nextSproutID, kind, windowID: wid, offset: x - w.x, growth, ripeAt: growth >= 1 ? this.clock : null };
    this.sprouts.push(sp);
    this.sproutEvents.push({ type: 'sprouted', at: V(x, w.y + w.h) });
    return sp;
  }

  /** The clock comes apart: seeds off on the breeze, and a seed or two comes down on a branch a few seconds later. */
  blowSeeds(p, by) {
    const dir = this.rng.chance(0.5) ? 1 : -1;
    this.sproutEvents.push({ type: 'seedsBlown', at: p, dir, id: by });
    const tops = this.sproutTops();
    for (let k = this.rng.chance(0.5) ? 2 : 1; k > 0 && tops.length; k--) {
      const t = this.rng.pick(tops), w = this.windows.get(t.owner);
      if (t.maxX - t.minX < 80) continue;
      this.pendingSeeds.push({ at: this.clock + this.rng.range(3, 6), window: t.owner, offset: this.rng.range(t.minX + 40, t.maxX - 40) - w.x });
    }
  }

  /** Not on any chore timer: something ready in the moss is always worth a look. Weights as on the Mac. */
  sproutChoices(c, add_) {
    if (!this.sprouts.length || !this.isFree(c) || !c.isGrounded) return;
    const s = this.supportingSurface(c);
    if (!s || s.kind !== 'top' || !this.sproutHost(s.owner)) return;
    for (const sp of this.sprouts) {
      if (sp.windowID !== s.owner || this.tended(sp.id)) continue;
      const x = this.sproutX(sp);
      if (!supports(s, x) || Math.abs(x - c.pos.x) >= 700) continue;
      const near = Math.abs(x - c.pos.x) < 250 ? 1 : 0.6;
      if (sp.growth >= 1) {
        const w = sp.kind === 'dandelion' ? 3.2 : sp.kind === 'berries' ? 2.6 : 2.8;
        add_(w * near, () => this.startSproutTask(c, sp.id, x - c.facing * 10));
      } else if (sp.growth > 0.08 && this.clock - (this.sproutWatered[sp.id] ?? -999) > 40) {
        add_(1.0 * near, () => { this.startSproutTask(c, sp.id, x - c.facing * 10); c.carrying = 'can'; });
      }
    }
  }

  startSproutTask(c, id, x) {
    this.endSocial(c);
    c.task = { kind: 'sprout', id, started: this.clock, acting: false };
    c.carrying = null;
    c.targetX = x; c.facing = x > c.pos.x ? 1 : -1;
    c.set('walk', 30);
  }

  /** The next step of an errand, when the current activity ends. */
  taskDecide(c) {
    const t = c.task, s = this.supportingSurface(c);
    if (!s || this.clock - t.started > 60) { c.task = null; c.carrying = null; c.set('idle', 0.3); return; }
    if (t.kind === 'sprout') this.sproutDecide(c, t, s); else this.giftDecide(c, t, s);
    if (c.task == null) c.carrying = null;
  }

  /** Walk over, then water it, or pick / eat / blow it. */
  sproutDecide(c, t, s) {
    const i = this.sprouts.findIndex((sp) => sp.id === t.id);
    if (i < 0 || s.owner !== this.sprouts[i].windowID) { c.task = null; c.set('idle', 0.3); return; }
    const sp = this.sprouts[i], x = this.sproutX(sp), p = V(x, s.y), ripe = sp.growth >= 1;
    if (!t.acting) {
      const stand = x + (c.pos.x < x ? -12 : 12);
      if (Math.abs(c.pos.x - stand) > 6) { c.targetX = stand; c.set('walk', 20); return; }
      t.acting = true;
      c.facing = x > c.pos.x ? 1 : -1;
      // Crouched over it (the web's 'crouch' activity is a jump wind-up, so this is the idle pose).
      c.idleVariant = 'crouch';
      c.set('idle', ripe ? (sp.kind === 'berries' ? 2.2 : 1.4) : 2.0);
      if (!ripe) { c.carrying = 'can'; this.sproutEvents.push({ type: 'watered', at: p, id: c.id }); }
      return;
    }
    c.task = null;
    c.idleVariant = 'idle';
    if (!ripe) {
      sp.growth = Math.min(1, sp.growth + 0.2);
      if (sp.growth >= 1) sp.ripeAt = this.clock;
      this.sproutWatered[sp.id] = this.clock;
      c.carrying = null;
      c.idleVariant = 'look'; c.set('idle', 1.2);
      return;
    }
    this.sprouts.splice(i, 1);
    if (sp.kind === 'berries') {
      c.energy = Math.min(1, c.energy + 0.25);
      this.sproutEvents.push({ type: 'ate', at: p, id: c.id });
      c.set('react', c.animationLength('react'));
    } else if (sp.kind === 'dandelion') {
      this.blowSeeds(p, c.id);
      c.set('react', c.animationLength('react'));
    } else {
      this.sproutEvents.push({ type: 'picked', kind: sp.kind, at: p, id: c.id });
      c.carrying = sp.kind;
      // Off to give it to a friend on this branch, if there's one about; otherwise, a happy little hop.
      const f = this.creatures.filter((o) => o !== c && o.isGrounded && o.ground === s.owner && !o.isAsleep && Math.abs(o.pos.x - c.pos.x) < 500 && supports(s, o.pos.x))
        .sort((a, b) => Math.abs(a.pos.x - c.pos.x) - Math.abs(b.pos.x - c.pos.x))[0];
      if (f) {
        c.task = { kind: 'gift', to: f.id, what: sp.kind, started: this.clock };
        c.targetX = f.pos.x + (c.pos.x < f.pos.x ? -22 : 22);
        c.set('walk', 15);
      } else {
        c.task = { kind: 'gift', to: -1, what: sp.kind, started: this.clock };
        c.set('react', c.animationLength('react'));
      }
    }
  }

  /** Carrying a daisy or mushroom over to a friend (or, with nobody about, just admiring it). */
  giftDecide(c, t, s) {
    c.task = null;
    const f = t.to >= 0 ? this.byId(t.to) : null;
    if (!f || f.ground !== s.owner || !supports(s, f.pos.x)) { c.idleVariant = 'look'; c.set('idle', 1.0); return; }
    const stand = f.pos.x + (c.pos.x < f.pos.x ? -22 : 22);
    if (Math.abs(c.pos.x - stand) > 10 && this.clock - t.started < 20) { c.task = t; c.targetX = stand; c.set('walk', 10); return; }
    c.facing = f.pos.x > c.pos.x ? 1 : -1;
    this.sproutEvents.push({ type: 'gave', kind: t.what, id: c.id, to: f.id });
    c.set('wave', 1.2);
    if (f.task == null && f.isGrounded && ['idle', 'walk', 'follow', 'wave', 'land'].includes(f.activity)) {
      this.endSocial(f);
      f.facing = -c.facing;
      f.set('react', f.animationLength('react'));
    }
  }

  /** Something comes up now (already grown, unless `growth` says otherwise): the dev hook and the first few on load.
   *  Prefers a branch someone is standing on, so there's something to watch. Returns the sprout, or null. */
  sproutNow(kind = null, growth = 1) {
    const tops = this.sproutTops();
    if (!tops.length) return null;
    const busy = tops.filter((t) => this.creatures.some((c) => c.isGrounded && c.ground === t.owner));
    for (let k = 0; k < 10; k++) {
      const t = busy.length && this.rng.chance(0.75) ? this.rng.pick(busy) : this.rng.pick(tops);
      const x = this.rng.range(t.minX + 30, t.maxX - 30);
      if (!this.sproutSpotFree(t.owner, x)) continue;
      return this.addSprout(World.sproutKinds.includes(kind) ? kind : this.rng.pick(World.sproutKinds), t.owner, x, Math.min(1, growth));
    }
    return null;
  }
}
