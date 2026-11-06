// Phone <-> Mac link for the web habitat.
//
// The Mac app shows a QR code with ?pair=<code>. Both sides then pass tiny JSON notes ("Kindlet is jumping to the
// phone", "Kindlet is going home with a tulip") through ntfy.sh, a free public relay that needs no account, on a channel
// named after that private code. Only Gremlet names and plant kinds are sent.
const RELAY = 'https://ntfy.sh';
const CODE_KEY = 'gremlets.pair', SEEN_KEY = 'gremlets.pair.seen', LAST_KEY = 'gremlets.pair.last';

const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* private mode */ } },
  del(k) { try { localStorage.removeItem(k); } catch { /* private mode */ } },
};

export class Link {
  constructor() {
    const params = new URLSearchParams(location.search);
    const fromUrl = params.get('pair');
    if (fromUrl && /^[a-z0-9]{12,64}$/.test(fromUrl)) {
      store.set(CODE_KEY, fromUrl);
      store.del(LAST_KEY);
      // Keep the code out of the address bar (and out of screenshots).
      params.delete('pair');
      history.replaceState(null, '', location.pathname + (params.toString() ? '?' + params : ''));
    }
    this.code = store.get(CODE_KEY, null);
    this.seen = new Set(store.get(SEEN_KEY, []));
    this.onArrive = () => {};
    this.onStatus = () => {};
    this.connected = false;
  }

  get paired() { return !!this.code; }
  get topic() { return `gremlets-${this.code}`; }

  start() {
    if (!this.paired || this.es) return;
    const since = store.get(LAST_KEY, null) || '12h';
    this.es = new EventSource(`${RELAY}/${this.topic}/sse?since=${encodeURIComponent(since)}`);
    this.es.onopen = () => { this.connected = true; this.onStatus(); };
    this.es.onerror = () => { this.connected = false; this.onStatus(); };
    this.es.onmessage = (e) => this.handle(e.data);
  }

  handle(raw) {
    let msg, note;
    try { msg = JSON.parse(raw); } catch { return; }
    if (msg.event !== 'message' || !msg.id || this.seen.has(msg.id)) return;
    this.seen.add(msg.id);
    store.set(SEEN_KEY, [...this.seen].slice(-60));
    store.set(LAST_KEY, msg.id);
    try { note = JSON.parse(msg.message); } catch { return; }
    if (note?.type === 'jump' && note.to === 'phone' && typeof note.species === 'string' && note.species.length < 40) {
      this.onArrive({ species: note.species });
    }
  }

  /** Sends a visiting Gremlet home to the Mac, with what it grew here. */
  async sendHome(species, harvest) {
    const body = JSON.stringify({ v: 1, type: 'jump', to: 'mac', from: 'phone', species, harvest: harvest.slice(0, 30) });
    const r = await fetch(`${RELAY}/${this.topic}`, { method: 'POST', body });
    if (!r.ok) throw new Error(`relay said ${r.status}`);
  }

  unpair() {
    this.es?.close(); this.es = null;
    store.del(CODE_KEY); store.del(LAST_KEY);
    this.code = null; this.connected = false; this.onStatus();
  }
}
