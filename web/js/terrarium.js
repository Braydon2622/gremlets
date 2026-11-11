// The Terrarium (docs/plans/TERRARIUM.md, Phase 1): the web habitat as an always-on Gremlets home on an iPad on the
// desk. Opened with ?terrarium=1 (remembered, so the Home Screen icon opens straight into it; ?terrarium=0 turns it
// off). It
//   - keeps the screen awake (Screen Wake Lock) and shows a one-time card about Auto-Lock and Guided Access,
//   - lives by the real clock: day, dusk, night; at bedtime the Gremlets walk to their nests and sleep, the screen
//     dims to about a fifth, and they're up at 7; the whole scene shifts a few pixels each hour (burn-in),
//   - reloads itself once a night at 4am, and the bridge reconnects forever,
//   - shows what Claude is doing on the Mac (the bridge's sealed `status` notes): thinking = a thought cloud over a
//     Gremlet, waiting = a Gremlet at the screen edge holding up a lantern beside a little sign with the project, done
//     = a flag planted in the moss with a sparkle; and a quiet strip of the last five changes along the bottom.
import { PixelCanvas } from './pixelart.js';
import { V } from './engine.js';

const KEY = 'gremlets.terrarium', INTRO = 'gremlets.terrarium.intro', RELOADED = 'gremlets.terrarium.reloaded';
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
  del(k) { try { localStorage.removeItem(k); } catch { /* private mode */ } },
};

/** Whether this page is a Terrarium (?terrarium=1 turns it on for good, ?terrarium=0 off). */
export function terrariumMode(params) {
  if (params.get('terrarium') === '1') store.set(KEY, '1');
  if (params.get('terrarium') === '0') store.del(KEY);
  return store.get(KEY) === '1';
}

/** day | dusk | night by the hour: night from 9pm, up at 7am; dusk from 6pm. */
export function phaseAt(h) { return h >= 21 || h < 7 ? 'night' : h >= 18 ? 'dusk' : 'day'; }

/** The scene's burn-in shift for an hour: a few pixels, a different way each hour. */
export function shiftAt(h) { return { x: ((h * 7) % 13) - 6, y: ((h * 5) % 9) - 4 }; }

/** Pixel icons for the recent strip (and the lantern a Gremlet holds). */
function icon(state) {
  const cv = new PixelCanvas(9, 9);
  if (state === 'thinking') {
    cv.blob(4.5, 5, 4, 2.6, 0xF4F6FB, 0xFFFFFF, 0xC9D2E2);
    cv.set(2, 1, 0xF4F6FB); cv.set(1, 0, 0xF4F6FB);
    for (const x of [2, 4, 6]) cv.set(x, 5, 0x6A7390);
  } else if (state === 'waiting') {
    cv.rect(3, 7, 3, 1, 0x553620); cv.set(4, 8, 0x3A2A1C);
    cv.rect(2, 2, 5, 5, 0xFFC845); cv.rect(3, 3, 3, 3, 0xFFF0B8);
    cv.rect(2, 1, 5, 1, 0x553620);
  } else {
    cv.rect(1, 0, 1, 9, 0x6B4428);
    cv.rect(2, 4, 5, 4, 0xE8574A); cv.rect(2, 6, 3, 1, 0xF58A7A); cv.set(7, 6, 0xE8574A);
    cv.rect(0, 0, 4, 1, 0x5FAF4A);
  }
  return cv;
}

export class Terrarium {
  /**
   * env: { world, bridge, particles, FX, isResident(c), toScreen(x, y), px(), size(), ground(), say(id, text, secs),
   *        onPhase(phase), save(), load() }
   */
  constructor(env) {
    this.env = env;
    this.sessions = [];                 // from the Mac: [{ id, project, state }]
    this.recent = [];
    this.helpers = new Map();           // session id → creature id
    this.flags = new Map();             // session id → { x, y, t }
    this.nests = new Map();             // creature id → x
    this.phase = null;
    this.lastSweep = 0;
    // ?clock=22:30 pretends it's that time (for testing night mode).
    const clk = /[?&]clock=(\d{1,2})(?::|%3A)(\d{2})/.exec(globalThis.location?.search || '');
    this.offset = 0;
    if (clk) { const d = new Date(); d.setHours(+clk[1], +clk[2], 0, 0); this.offset = d.getTime() - Date.now(); }
  }

  now() { return new Date(Date.now() + this.offset); }
  phaseNow() { return phaseAt(this.now().getHours()); }

  start() {
    const { bridge } = this.env;
    document.body.classList.add('terrarium');
    this.iconUrls = Object.fromEntries(['thinking', 'waiting', 'done'].map((s) => [s, icon(s).toCanvas().toDataURL()]));
    this.lanternImg = icon('waiting').toCanvas();
    this.flagImg = icon('done').toCanvas();
    this.dim = Object.assign(document.createElement('div'), { id: 'tdim' });
    this.strip = Object.assign(document.createElement('div'), { id: 'trecent' });
    this.strip.setAttribute('aria-live', 'polite');
    document.body.append(this.dim, this.strip);
    if (bridge) {
      bridge.terrarium = true;
      bridge.onClaude = (n) => this.status(n);
    }
    this.wake();
    document.addEventListener('visibilitychange', () => { if (!document.hidden) this.wake(); });
    if (!store.get(INTRO)) this.intro();
    this.tick();
    this.clock = setInterval(() => this.tick(), 30_000);
  }

  /** Keeps the screen on (where the browser allows it; an installed web app on iPadOS 16.4+ does). */
  async wake() {
    try { this.lock = await navigator.wakeLock?.request('screen'); } catch { this.lock = null; }
  }

  intro() {
    const card = document.createElement('div');
    card.id = 'tintro';
    card.innerHTML = `<div class="sheet" role="dialog" aria-label="Welcome to the Terrarium">
      <h2>🌿 Your Terrarium</h2>
      <p>This iPad is now a home for Gremlets. They live here all day, sleep at night, and show what Claude is doing on your Mac.</p>
      <ol>
        <li><b>Add to Home Screen</b> (Share → Add to Home Screen) and open it from there: full screen, no Safari bars.</li>
        <li>Keep it on its charger and set <b>Settings → Display &amp; Brightness → Auto-Lock → Never</b>.</li>
        <li>To keep it on just this page: <b>Settings → Accessibility → Guided Access</b> on, then triple-click the top (or Home) button here.</li>
      </ol>
      <button class="btn" id="tintro-ok">Got it</button>
    </div>`;
    document.body.append(card);
    card.querySelector('#tintro-ok').addEventListener('click', () => { store.set(INTRO, '1'); card.remove(); });
  }

  /** Every 30 seconds: the sky, the dimming, the burn-in shift, and the 4am reload. */
  tick() {
    const d = this.now(), h = d.getHours();
    const phase = phaseAt(h);
    if (phase !== this.phase) {
      const was = this.phase;
      this.phase = phase;
      this.env.onPhase(phase);
      if (was === 'night' && phase !== 'night') this.morning();
    }
    this.applyDim();
    const s = shiftAt(h);
    document.body.style.transform = `translate(${s.x}px, ${s.y}px)`;
    this.renderStrip();
    this.env.save?.();
    // Once a night at 4am, a fresh start (a long-running page slowly gathers cruft).
    const day = d.toDateString();
    if (h === 4 && store.get(RELOADED) !== day) { store.set(RELOADED, day); location.reload(); }
  }

  get night() { return this.phase === 'night'; }

  applyDim() {
    if (!this.dim) return;
    const waiting = this.sessions.some((s) => s.state === 'waiting');
    this.dim.style.opacity = this.night ? (waiting ? '0.55' : '0.8') : '0';
  }

  morning() {
    for (const c of this.env.world.creatures) if (c.isAsleep && this.env.isResident(c)) { c.timer = 0; c.set('wake', c.animationLength('wake')); }
    this.nests.clear();
  }

  // ---------------------------------------------------------------- Claude's status from the Mac

  status(n) {
    const ok = (s) => ['thinking', 'waiting', 'done'].includes(s);
    const clean = (p) => String(p ?? '').slice(0, 32);
    this.sessions = n.sessions.filter((s) => s && typeof s.id === 'string' && ok(s.state)).slice(0, 8).map((s) => ({ id: s.id.slice(0, 12), project: clean(s.project), state: s.state }));
    this.recent = (Array.isArray(n.recent) ? n.recent : []).filter((e) => e && ok(e.state)).slice(-5).map((e) => ({ project: clean(e.project), state: e.state, at: +e.at || 0 }));
    const live = new Set(this.sessions.map((s) => s.id));
    for (const id of [...this.helpers.keys()]) if (!live.has(id)) this.release(id);
    for (const id of [...this.flags.keys()]) if (!live.has(id)) this.flags.delete(id);
    this.applyDim();
    this.renderStrip();
  }

  release(id) {
    const c = this.env.world.creatures.find((o) => o.id === this.helpers.get(id));
    if (c && c.task === 'lantern') { c.task = null; c.targetX = null; }
    this.helpers.delete(id);
  }

  /** The Gremlet standing in for a session (a resident, one each, kept while it's around). */
  helper(s) {
    const { world, isResident } = this.env;
    let c = world.creatures.find((o) => o.id === this.helpers.get(s.id));
    if (c && isResident(c)) return c;
    const taken = new Set(this.helpers.values());
    c = world.creatures.find((o) => isResident(o) && !taken.has(o.id));
    if (c) this.helpers.set(s.id, c.id); else this.helpers.delete(s.id);
    return c;
  }

  renderStrip() {
    if (!this.strip) return;
    const now = Date.now() / 1000;
    const ago = (t) => { const s = Math.max(0, now - t); return s < 90 ? 'now' : s < 3600 ? `${Math.round(s / 60)}m` : `${Math.round(s / 3600)}h`; };
    const words = { thinking: 'thinking', waiting: 'needs you', done: 'done' };
    this.strip.replaceChildren(...this.recent.map((e) => {
      const el = document.createElement('div');
      el.className = 'tcard ' + e.state;
      const img = Object.assign(document.createElement('img'), { src: this.iconUrls[e.state], alt: '' });
      const t = document.createElement('span');
      t.textContent = `${e.project} · ${words[e.state]}`;
      const a = Object.assign(document.createElement('small'), { textContent: ago(e.at) });
      el.append(img, t, a);
      return el;
    }));
  }

  // ---------------------------------------------------------------- each frame

  update(dt, t) {
    const { world, isResident, particles, FX, size, ground } = this.env;
    const { w: W } = size();
    // Claude's sessions: who's thinking, who's holding up the lantern, where the flags are.
    for (const s of this.sessions) {
      const c = this.helper(s);
      if (!c) continue;
      if (s.state === 'waiting') {
        if (c.isAsleep) { c.timer = 0; c.set('wake', c.animationLength('wake')); continue; }
        const i = this.sessions.filter((o) => o.state === 'waiting').indexOf(s);
        const x = i % 2 === 0 ? 46 + (i >> 1) * 70 : W - 46 - (i >> 1) * 70;
        if (!c.isGrounded) continue;
        if (Math.abs(c.pos.x - x) > 8) {
          if (c.activity !== 'walk' || c.task !== 'lantern') { c.task = 'lantern'; c.targetX = x; c.set('walk', 30); }
        } else if (c.activity !== 'idle' || c.timer < 0.5) {
          c.task = 'lantern'; c.targetX = null;
          c.facing = x < W / 2 ? 1 : -1;
          c.set('idle', 3);
        }
      } else if (c.task === 'lantern') { c.task = null; c.targetX = null; }
      if (s.state === 'done' && !this.flags.has(s.id)) {
        const y = c.isGrounded ? c.pos.y : ground();
        const x = c.pos.x + c.facing * 18;
        this.flags.set(s.id, { x, y, t });
        particles.burst(FX.sparkle, V(x, y + 20), { count: 6, dx: [-24, 24], dy: [10, 46], duration: 1.1, stagger: 0.06 });
        this.env.say?.(c.id, `${s.project}: done ✓`, 4);
      }
    }
    // Bedtime: off to their nests, then sleep till morning (a tap still wakes one for a bit).
    if (this.night && t - this.lastSweep > 2) {
      this.lastSweep = t;
      const res = world.creatures.filter((c) => isResident(c) && !this.busy(c));
      res.forEach((c, i) => {
        if (!this.nests.has(c.id)) this.nests.set(c.id, W * (0.12 + 0.76 * (i + 0.5) / Math.max(1, res.length)));
        const x = this.nests.get(c.id);
        if (c.activity === 'sleep') { c.timer = Math.max(c.timer, 60); c.energy = Math.min(c.energy, 0.4); return; }
        if (c.isAsleep || !c.isGrounded || ['dragged', 'wake', 'react'].includes(c.activity)) return;
        if (Math.abs(c.pos.x - x) > 10 && c.pos.y <= ground() + 2 && c.task !== 'nest-done') { c.task = 'nest'; c.targetX = x; c.set('walk', 30); return; }
        c.task = 'nest-done'; c.targetX = null;
        c.set('yawn', c.animationLength('yawn'));
      });
    }
    if (!this.night) for (const c of world.creatures) if (c.task === 'nest' || c.task === 'nest-done') { c.task = null; c.targetX = null; }
  }

  /** On Claude duty (thinking, or out with the lantern). */
  busy(c) {
    for (const [sid, cid] of this.helpers) if (cid === c.id) { const s = this.sessions.find((o) => o.id === sid); if (s && s.state !== 'done') return true; }
    return false;
  }

  /** Behind the Gremlets: the nests and the flags. */
  drawBack(ctx, t) {
    const { toScreen, px, world } = this.env;
    const P = px();
    if (this.night) {
      for (const c of world.creatures) {
        if (c.activity !== 'sleep' || !c.isGrounded) continue;
        const s = toScreen(c.pos.x, c.pos.y);
        ctx.fillStyle = '#6b4428';
        ctx.fillRect(Math.round(s.x - 7 * P), Math.round(s.y - P), 14 * P, 2 * P);
        ctx.fillStyle = '#8a5a35';
        ctx.fillRect(Math.round(s.x - 8 * P), Math.round(s.y - 3 * P), 3 * P, 2 * P);
        ctx.fillRect(Math.round(s.x + 5 * P), Math.round(s.y - 3 * P), 3 * P, 2 * P);
      }
    }
    if (!this.flagImg) return;
    for (const [, f] of this.flags) {
      const s = toScreen(f.x, f.y);
      const sway = Math.round(Math.sin(t * 2 + f.x) * 0.6) * P;
      ctx.drawImage(this.flagImg, Math.round(s.x - P) + sway, Math.round(s.y - 9 * P * 1.4), 9 * P * 1.4, 9 * P * 1.4);
    }
  }

  /** In front: thought clouds, lanterns and their signs. */
  drawFront(ctx, t) {
    if (!this.lanternImg) return;
    const { world, toScreen, px } = this.env;
    const P = px();
    for (const s of this.sessions) {
      const c = world.creatures.find((o) => o.id === this.helpers.get(s.id));
      if (!c) continue;
      const head = toScreen(c.pos.x, c.pos.y + c.size.y * 0.95);
      if (s.state === 'thinking') {
        const bob = Math.sin(t * 2.2 + c.id) * P;
        const cx = Math.round(head.x + c.facing * 10 * P / 3), cy = Math.round(head.y - 10 * P + bob);
        ctx.fillStyle = 'rgba(255,255,255,0.95)';
        ctx.fillRect(cx - 7 * P, cy - 3 * P, 14 * P, 6 * P);
        ctx.fillRect(cx - 5 * P, cy - 5 * P, 10 * P, 10 * P);
        ctx.fillRect(Math.round(head.x) - P, Math.round(head.y - 2 * P), 2 * P, 2 * P);
        ctx.fillRect(Math.round(head.x + c.facing * 3 * P) - P, Math.round(head.y - 5 * P + bob), 2 * P, 2 * P);
        ctx.fillStyle = '#6a7390';
        for (let i = 0; i < 3; i++) if (Math.floor(t * 3) % 4 > i) ctx.fillRect(cx + (i - 1) * 3 * P - P / 2, cy - P / 2, P, P);
      } else if (s.state === 'waiting' && c.task === 'lantern' && c.targetX == null) {
        const hand = toScreen(c.pos.x + c.facing * c.size.x * 0.28, c.pos.y + c.size.y * 0.62);
        const L = 9 * P * 1.2, swing = Math.sin(t * 2.4) * P;
        const g = ctx.createRadialGradient(hand.x, hand.y + L * 0.4, 2, hand.x, hand.y + L * 0.4, 46);
        g.addColorStop(0, `rgba(255,210,110,${0.45 + 0.1 * Math.sin(t * 6)})`); g.addColorStop(1, 'rgba(255,200,90,0)');
        ctx.fillStyle = g; ctx.fillRect(hand.x - 46, hand.y + L * 0.4 - 46, 92, 92);
        ctx.drawImage(this.lanternImg, Math.round(hand.x - L / 2 + swing), Math.round(hand.y), L, L);
        // The little sign on a stake beside it, with the project.
        const foot = toScreen(c.pos.x - c.facing * c.size.x * 0.45, c.pos.y);
        ctx.font = `700 ${Math.max(11, Math.round(P * 4))}px ui-rounded, system-ui, sans-serif`;
        const tw = Math.ceil(ctx.measureText(s.project).width), bw = tw + 4 * P, bh = 6 * P;
        const bx = Math.round(Math.min(Math.max(4, foot.x - bw / 2), this.env.size().w - bw - 4)), by = Math.round(foot.y - 14 * P);
        ctx.fillStyle = '#6b4428'; ctx.fillRect(Math.round(foot.x) - P / 2, by + bh, P, 14 * P - bh);
        ctx.fillStyle = '#c9a15a'; ctx.fillRect(bx, by, bw, bh);
        ctx.fillStyle = '#9c7840'; ctx.fillRect(bx, by + bh - P, bw, P);
        ctx.fillStyle = '#3a2614'; ctx.textBaseline = 'middle'; ctx.fillText(s.project, bx + 2 * P, by + bh / 2);
      }
    }
  }
}

