// Screen bridge: links this habitat to another screen (your iPad, your phone, a friend's laptop) so Gremlets can walk
// off one edge and in from the other side, and so travelling visitors can cross between screens.
//
// Both screens join a "room" named after a random code and pass tiny JSON notes through ntfy.sh (the same free relay
// the Mac phone link uses). Only Gremlet names, which side they left from and how fast they were going are sent.
//
//   { v: 1, type: 'walk', from: <device id>, to: 'left'|'right', species, y, vx, vy, air, name? }
//   { v: 1, type: 'visitor', from, to, kind, y }
//   { v: 1, type: 'hello', from, side }       // a screen joined (lets the other one show "Linked")
const DEFAULT_RELAY = 'https://ntfy.sh';
const ROOM_KEY = 'gremlets.room', SIDE_KEY = 'gremlets.room.side';

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
    if (room && /^[a-z0-9]{8,40}$/.test(room) && (side === 'left' || side === 'right')) {
      store.set(ROOM_KEY, room); store.set(SIDE_KEY, side);
      params.delete('room'); params.delete('side');
      history.replaceState(null, '', location.pathname + (params.toString() ? '?' + params : ''));
      this.justJoined = true;
    }
    this.room = store.get(ROOM_KEY, null);
    this.side = store.get(SIDE_KEY, null);       // which edge of THIS screen leads to the other screen
    this.connected = false;
    this.peerSeen = 0;                           // when we last heard from the other screen
    this.onWalk = () => {};
    this.onVisitor = () => {};
    this.onKeys = () => {};
    this.onStatus = () => {};
  }

  get linked() { return !!(this.room && this.side); }
  get topic() { return `gremlets-room-${this.room}`; }
  get peerOnline() { return Date.now() - this.peerSeen < 90_000; }

  /** Starts a new room. `side` is the edge of this screen that leads to the other one. */
  create(side) {
    this.stop();
    this.room = randomCode();
    this.side = side;
    store.set(ROOM_KEY, this.room); store.set(SIDE_KEY, side);
    this.start();
  }

  /** The link the other screen opens: its doorway is on the opposite edge. */
  inviteUrl() {
    const u = new URL(location.href);
    u.search = '';
    u.searchParams.set('room', this.room);
    u.searchParams.set('side', this.side === 'right' ? 'left' : 'right');
    if (this.relay !== DEFAULT_RELAY) u.searchParams.set('relay', this.relay);
    return u.toString();
  }

  start() {
    if (!this.linked || this.es) return;
    this.es = new EventSource(`${this.relay}/${this.topic}/sse`);
    this.es.onopen = () => { this.connected = true; this.onStatus(); this.send({ type: 'hello', side: this.side }); };
    this.es.onerror = () => { this.connected = false; this.onStatus(); };
    this.es.onmessage = (e) => this.handle(e.data);
    // A light heartbeat so each screen can show whether the other one is open.
    this.beat = setInterval(() => this.send({ type: 'hello', side: this.side }), 45_000);
  }

  stop() {
    this.es?.close(); this.es = null;
    clearInterval(this.beat);
    this.connected = false;
  }

  unlink() {
    this.stop();
    store.del(ROOM_KEY); store.del(SIDE_KEY);
    this.room = null; this.side = null; this.peerSeen = 0;
    this.onStatus();
  }

  handle(raw) {
    let msg, note;
    try { msg = JSON.parse(raw); } catch { return; }
    if (msg.event !== 'message') return;
    try { note = JSON.parse(msg.message); } catch { return; }
    if (!note || note.v !== 1 || note.from === this.device) return;
    this.peerSeen = Date.now();
    // The Mac says how mossy it is: this screen's branches grow to match.
    if (typeof note.moss === 'number' && note.moss !== this.peerMoss) { this.peerMoss = note.moss; this.onMoss?.(); }
    if (note.type === 'hello') { this.onStatus(); if (!note.reply) this.send({ type: 'hello', side: this.side, reply: true }); return; }
    // Notes are addressed to the edge they arrive through, which is our doorway.
    if (note.to !== this.side) return;
    if (note.type === 'walk' && typeof note.species === 'string' && note.species.length < 40) this.onWalk(note);
    if (note.type === 'visitor' && typeof note.kind === 'string') this.onVisitor(note);
    if (note.type === 'keys') this.onKeys(note);
    this.onStatus();
  }

  async send(note) {
    if (!this.linked) return false;
    try {
      const r = await fetch(`${this.relay}/${this.topic}`, { method: 'POST', body: JSON.stringify({ v: 1, from: this.device, ...note }) });
      return r.ok;
    } catch { return false; }
  }

  /** Something leaves through our doorway; on the other screen it arrives through the opposite edge. */
  cross(note) {
    return this.send({ ...note, to: this.side === 'right' ? 'left' : 'right' });
  }
}
