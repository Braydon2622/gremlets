// Screen bridge: links this habitat to another screen (your iPad, your phone, a friend's laptop) so Gremlets can walk
// off one edge and in from the other side, and so travelling visitors can cross between screens.
//
// Both screens join a "room" named after a random code and pass tiny JSON notes through ntfy.sh (the same free relay
// the Mac phone link uses). Only Gremlet names, which side they left from and how fast they were going are sent.
//
//   { v: 1, type: 'walk', from: <device id>, to: 'left'|'right', species, y, vx, vy, air, name? }
//   { v: 1, type: 'visitor', from, to, kind, y }
//   { v: 1, type: 'hello', from, side, terrarium? }   // a screen joined (lets the other one show "Linked")
//   { v: 1, type: 'status', from, sessions: [{ id, project, state }], recent: [{ project, state, at }] }   // Mac → Terrarium
//
// Rooms with a pairing secret (the link's #k=…) are sealed: every note travels AES-GCM encrypted (seal.js), and plain
// notes on a sealed room are ignored. The connection retries forever, backing off up to a minute.
import { noteKey, seal, open, newSecret } from './seal.js';
const DEFAULT_RELAY = 'https://ntfy.sh';
const ROOM_KEY = 'gremlets.room', SIDE_KEY = 'gremlets.room.side', SECRET_KEY = 'gremlets.room.key';

const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* private mode */ } },
  del(k) { try { localStorage.removeItem(k); } catch { /* private mode */ } },
};

const randomCode = () => {
  const a = new Uint8Array(12);
  crypto.getRandomValues(a);
  return [...a].map((b) => 'abcdefghijkmnpqrstuvwxyz23456789'[b % 32]).join('');
};

export class Bridge {
  constructor() {
    const params = new URLSearchParams(location.search);
    this.relay = params.get('relay') || DEFAULT_RELAY;          // tests point this at a local relay
    this.device = randomCode().slice(0, 8);
    const room = params.get('room'), side = params.get('side');
    const k = new URLSearchParams(location.hash.slice(1)).get('k');
    if (room && /^[a-z0-9]{8,40}$/.test(room) && (side === 'left' || side === 'right')) {
      store.set(ROOM_KEY, room); store.set(SIDE_KEY, side);
      if (k && /^[a-z0-9]{16,64}$/.test(k)) store.set(SECRET_KEY, k); else store.del(SECRET_KEY);
      params.delete('room'); params.delete('side');
      // Keep the code and the secret out of the address bar (and out of screenshots).
      history.replaceState(null, '', location.pathname + (params.toString() ? '?' + params : ''));
      this.justJoined = true;
    }
    this.room = store.get(ROOM_KEY, null);
    this.side = store.get(SIDE_KEY, null);       // which edge of THIS screen leads to the other screen
    this.secret = store.get(SECRET_KEY, null);
    this.key = null;                             // the note key, once made (async)
    this.terrarium = false;                      // this screen is a Terrarium (says so in its hello)
    this.backoff = 2;
    this.connected = false;
    this.peerSeen = 0;                           // when we last heard from the other screen
    this.onWalk = () => {};
    this.onVisitor = () => {};
    this.onKeys = () => {};
    this.onStatus = () => {};
    this.onClaude = () => {};                    // a status note from the Mac
  }

  get sealed() { return !!this.secret; }

  get linked() { return !!(this.room && this.side); }
  get topic() { return `gremlets-room-${this.room}`; }
  get peerOnline() { return Date.now() - this.peerSeen < 90_000; }

  /** Starts a new room. `side` is the edge of this screen that leads to the other one. */
  create(side) {
    this.stop();
    this.room = randomCode();
    this.side = side;
    this.secret = newSecret(); this.key = null;
    store.set(ROOM_KEY, this.room); store.set(SIDE_KEY, side); store.set(SECRET_KEY, this.secret);
    this.start();
  }

  /** The link the other screen opens: its doorway is on the opposite edge. */
  inviteUrl() {
    const u = new URL(location.href);
    u.search = '';
    u.searchParams.set('room', this.room);
    u.searchParams.set('side', this.side === 'right' ? 'left' : 'right');
    if (this.relay !== DEFAULT_RELAY) u.searchParams.set('relay', this.relay);
    if (this.secret) u.hash = 'k=' + this.secret;
    return u.toString();
  }

  hello(extra = {}) { return { type: 'hello', side: this.side, ...(this.terrarium ? { terrarium: true } : {}), ...extra }; }

  async start() {
    if (!this.linked || this.es) return;
    if (this.secret && !this.key) {
      try { this.key = await noteKey(this.secret, this.room); } catch { this.key = null; }
      if (!this.key) return;   // no WebCrypto here (not https): a sealed room can't be read
    }
    this.open();
    // A light heartbeat so each screen can show whether the other one is open.
    clearInterval(this.beat);
    this.beat = setInterval(() => this.send(this.hello()), 45_000);
  }

  /** (Re)connects; on any error it closes and tries again later, backing off to a minute, forever. */
  open() {
    clearTimeout(this.retry);
    this.es?.close();
    const es = this.es = new EventSource(`${this.relay}/${this.topic}/sse`);
    es.onopen = () => { this.connected = true; this.backoff = 2; this.onStatus(); this.send(this.hello()); };
    es.onerror = () => {
      if (this.es !== es) return;
      this.connected = false; this.onStatus();
      es.close();
      this.retry = setTimeout(() => { if (this.es === es) this.open(); }, this.backoff * 1000);
      this.backoff = Math.min(60, this.backoff * 2);
    };
    es.onmessage = (e) => this.handle(e.data);
  }

  stop() {
    this.es?.close(); this.es = null;
    clearInterval(this.beat); clearTimeout(this.retry);
    this.connected = false;
  }

  unlink() {
    this.stop();
    store.del(ROOM_KEY); store.del(SIDE_KEY); store.del(SECRET_KEY);
    this.room = null; this.side = null; this.peerSeen = 0; this.secret = null; this.key = null;
    this.onStatus();
  }

  async handle(raw) {
    let msg, note;
    try { msg = JSON.parse(raw); } catch { return; }
    if (msg.event !== 'message' || typeof msg.message !== 'string') return;
    // A sealed room only takes sealed notes.
    const text = this.key ? await open(msg.message, this.key, this.room) : msg.message;
    if (text == null) return;
    try { note = JSON.parse(text); } catch { return; }
    if (!note || note.v !== 1 || note.from === this.device) return;
    this.peerSeen = Date.now();
    // The Mac says how mossy it is: this screen's branches grow to match.
    if (typeof note.moss === 'number' && note.moss !== this.peerMoss) { this.peerMoss = note.moss; this.onMoss?.(); }
    if (note.type === 'hello') { this.onStatus(); if (!note.reply) this.send(this.hello({ reply: true })); return; }
    // What Claude is up to on the Mac (not addressed to an edge).
    if (note.type === 'status' && Array.isArray(note.sessions)) { this.onClaude(note); this.onStatus(); return; }
    // Notes are addressed to the edge they arrive through, which is our doorway.
    if (note.to !== this.side) return;
    if (note.type === 'walk' && typeof note.species === 'string' && note.species.length < 40) this.onWalk(note);
    if (note.type === 'visitor' && typeof note.kind === 'string') this.onVisitor(note);
    if (note.type === 'keys') this.onKeys(note);
    this.onStatus();
  }

  async send(note) {
    if (!this.linked || (this.secret && !this.key)) return false;
    try {
      const plain = JSON.stringify({ v: 1, from: this.device, ...note });
      const body = this.key ? await seal(plain, this.key, this.room) : plain;
      const r = await fetch(`${this.relay}/${this.topic}`, { method: 'POST', body });
      return r.ok;
    } catch { return false; }
  }

  /** Something leaves through our doorway; on the other screen it arrives through the opposite edge. */
  cross(note) {
    return this.send({ ...note, to: this.side === 'right' ? 'left' : 'right' });
  }
}
