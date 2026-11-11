"""The Terrarium in a real browser at iPad size (docs/plans/TERRARIUM.md, Phase 1).

Runs the web habitat with ?terrarium=1 in Google Chrome (Playwright, channel "chrome") against a tiny local stand-in
for the ntfy relay, and checks: the sealing matches the Mac's test vector, night mode (asleep, dimmed), the lantern /
thought cloud / flag states from sealed status notes, that plain notes on a sealed room are ignored, and that the
bridge reconnects after the relay drops. Screenshots go to $TERRARIUM_SHOTS (default: /tmp/terrarium-shots).

    python3 web/tests/terrarium_spec.py
"""
import http.server, json, os, queue, socketserver, sys, threading, time, functools
from playwright.sync_api import sync_playwright

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')   # the repo (the habitat finds ../Species from web/)
SHOTS = os.environ.get('TERRARIUM_SHOTS', '/tmp/terrarium-shots')
IPAD = {'width': 1180, 'height': 820}   # iPad Air, landscape
VECTOR = '{"c":"NyCt06mnt07Px1XuJui3cYzyyKYkKpwfWg921+7zsHKC","n":"AAECAwQFBgcICQoL","v":2}'   # = TerrariumTests.vector
ROOM, SECRET = 'testroom1234', 'testsecretabcdefghijk23'


class Relay:
    """Enough of ntfy for the bridge: POST /<topic> publishes, GET /<topic>/sse streams. `down` drops everyone."""
    def __init__(self):
        self.subs, self.down, self.posts = [], False, []
        relay = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def cors(self):
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Access-Control-Allow-Headers', '*')
            def do_OPTIONS(self):
                self.send_response(204); self.cors(); self.end_headers()
            def do_POST(self):
                body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
                relay.posts.append(body)
                for q in list(relay.subs): q.put(json.dumps({'event': 'message', 'message': body}))
                self.send_response(200); self.cors(); self.end_headers(); self.wfile.write(b'{}')
            def do_GET(self):
                if relay.down or not self.path.endswith('/sse'):
                    self.send_response(503); self.cors(); self.end_headers(); return
                self.send_response(200); self.cors()
                self.send_header('Content-Type', 'text/event-stream'); self.send_header('Cache-Control', 'no-cache'); self.end_headers()
                q = queue.Queue(); relay.subs.append(q)
                try:
                    self.wfile.write(b': hi\n\n'); self.wfile.flush()
                    while not relay.down:
                        try: self.wfile.write(f'data: {q.get(timeout=0.5)}\n\n'.encode()); self.wfile.flush()
                        except queue.Empty: self.wfile.write(b': .\n\n'); self.wfile.flush()
                except Exception: pass
                finally: relay.subs.remove(q)

        class S(socketserver.ThreadingMixIn, http.server.HTTPServer): daemon_threads = True
        self.server = S(('127.0.0.1', 0), H)
        self.url = f'http://127.0.0.1:{self.server.server_address[1]}'
        threading.Thread(target=self.server.serve_forever, daemon=True).start()


def static_server():
    class S(socketserver.ThreadingMixIn, http.server.HTTPServer): daemon_threads = True
    h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=ROOT)
    h.log_message = lambda *a: None
    s = S(('127.0.0.1', 0), h)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return f'http://127.0.0.1:{s.server_address[1]}/web'


passed = failed = 0
def check(name, cond, detail=''):
    global passed, failed
    if cond: passed += 1; print(f'✔ {name}')
    else: failed += 1; print(f'✘ {name} {detail}')


def wait_for(page, js, timeout=20):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if page.evaluate(js): return True
        except Exception: pass
        time.sleep(0.25)
    return False


# The "Mac": sends sealed notes into the room from a separate page, with the same seal.js.
MAC_SEND = """async ([relay, room, secret, note, sealed]) => {
  const { noteKey, seal } = await import('/web/js/seal.js');
  const text = JSON.stringify({ v: 1, from: 'mac', ...note });
  const body = sealed ? await seal(text, await noteKey(secret, room), room) : text;
  await fetch(`${relay}/gremlets-room-${room}`, { method: 'POST', body });
}"""


def status(sessions, recent=None):
    now = time.time()
    return {'type': 'status', 'sessions': sessions, 'recent': recent or [{'project': s['project'], 'state': s['state'], 'at': now} for s in sessions]}


def main():
    os.makedirs(SHOTS, exist_ok=True)
    relay, site = Relay(), static_server()
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel='chrome', headless=True)
        ctx = browser.new_context(viewport=IPAD, device_scale_factor=2, has_touch=True, is_mobile=False)
        mac = ctx.new_page(); mac.goto(site + '/manifest.webmanifest')
        def send(note, sealed=True): mac.evaluate(MAC_SEND, [relay.url, ROOM, SECRET, note, sealed])

        # 1. WebCrypto seals exactly as the Mac's CryptoKit does.
        got = mac.evaluate("""async () => {
          const { noteKey, seal, open } = await import('/web/js/seal.js');
          const k = await noteKey('testsecret123', 'abcdefgh1234');
          const s = await seal('{"type":"status"}', k, 'abcdefgh1234', new Uint8Array([0,1,2,3,4,5,6,7,8,9,10,11]));
          return { s, back: await open(s, k, 'abcdefgh1234'), wrong: await open(s, k, 'otherroom') };
        }""")
        check('sealing matches the Mac (Swift test vector)', got['s'] == VECTOR, got['s'])
        check('opens with the right room, not another', got['back'] == '{"type":"status"}' and got['wrong'] is None)

        # 2. Night: the Gremlets go to bed, the screen dims.
        page = ctx.new_page()
        page.goto(f'{site}/?terrarium=1&clock=22:30&debug&relay={relay.url}')
        page.evaluate("localStorage.setItem('gremlets.terrarium.intro', '1')")
        page.reload()
        check('night sky', wait_for(page, "document.body.classList.contains('night')"))
        check('screen dims to about a fifth', wait_for(page, "document.getElementById('tdim').style.opacity === '0.8'"))
        STATES = "gremlets.world.creatures.map(c => c.activity + '/' + c.task).join(' ')"
        check('they go to sleep', wait_for(page, "gremlets.world.creatures.filter(c => c.activity === 'sleep').length >= 2", 45), page.evaluate(STATES))
        check('the bar and hints are hidden', page.evaluate("getComputedStyle(document.getElementById('bar')).display === 'none'"))
        check('installable: manifest and Home Screen tags', page.evaluate("!!document.querySelector('link[rel=manifest]') && !!document.querySelector('meta[name=apple-mobile-web-app-capable]')"))
        page.screenshot(path=f'{SHOTS}/night.png')
        page.close()

        # 3. Linked to the Mac over a sealed room, in the daytime.
        page = ctx.new_page()
        page.goto(f'{site}/?terrarium=1&clock=12:00&debug&relay={relay.url}&room={ROOM}&side=left#k={SECRET}')
        page.evaluate("document.getElementById('tintro')?.remove()")
        time.sleep(0.8)
        check('no link dialog over the Terrarium', page.evaluate("document.getElementById('linker').hidden"))
        check('link secret kept out of the address bar', SECRET not in page.url and 'room=' not in page.url, page.url)
        check('connected to the relay', wait_for(page, 'gremlets.bridge.connected'))
        check('says hello as a Terrarium, sealed', wait_for(page, 'true') and any('"v":2' in p for p in relay.posts) and not any('terrarium' in p for p in relay.posts))
        check('not dimmed by day', page.evaluate("document.getElementById('tdim').style.opacity === '0'"))

        # Plain notes on a sealed room are ignored.
        send(status([{'id': 's9', 'project': 'Sneaky', 'state': 'waiting'}]), sealed=False)
        time.sleep(1.5)
        check('ignores an unsealed note', page.evaluate('gremlets.terra.sessions.length') == 0)

        send(status([{'id': 's1', 'project': 'Project 1', 'state': 'waiting'}]))
        check('a sealed status note arrives', wait_for(page, "gremlets.terra.sessions[0]?.state === 'waiting'"))
        check('a Gremlet goes to the edge with the lantern', wait_for(page, """(() => { const t = gremlets.terra, c = gremlets.world.creatures.find(o => o.id === t.helpers.get('s1'));
            return c && c.task === 'lantern' && c.targetX == null && (c.pos.x < 140 || c.pos.x > innerWidth - 140); })()""", 40))
        check('the recent strip shows it', wait_for(page, "document.querySelector('#trecent .tcard.waiting')?.textContent.includes('needs you')"))
        page.screenshot(path=f'{SHOTS}/lantern.png')

        send(status([{'id': 's1', 'project': 'Project 1', 'state': 'thinking'}, {'id': 's2', 'project': 'Project 2', 'state': 'thinking'}]))
        check('thinking: two helpers', wait_for(page, 'gremlets.terra.helpers.size === 2'), page.evaluate("JSON.stringify([gremlets.terra.sessions, [...gremlets.terra.helpers], gremlets.world.creatures.length])"))
        time.sleep(1); page.screenshot(path=f'{SHOTS}/thinking.png')
        send(status([{'id': 's1', 'project': 'Project 1', 'state': 'done'}]))
        check('done: a flag in the moss', wait_for(page, 'gremlets.terra.flags.size === 1'))
        time.sleep(0.6); page.screenshot(path=f'{SHOTS}/done.png')

        # 4. The relay drops; the bridge keeps trying and comes back.
        relay.down = True
        check('notices the relay went away', wait_for(page, '!gremlets.bridge.connected', 15))
        time.sleep(3)
        relay.down = False
        check('reconnects by itself', wait_for(page, 'gremlets.bridge.connected', 30))
        send(status([{'id': 's3', 'project': 'Project 3', 'state': 'thinking'}]))
        check('and hears the Mac again', wait_for(page, "gremlets.terra.sessions[0]?.id === 's3'"))
        browser.close()
    print(f'{passed} passed, {failed} failed  (screenshots in {SHOTS})')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
