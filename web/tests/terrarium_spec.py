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

        # 2. It starts as an empty glass room, and they build it up (fast-forwarded).
        page = ctx.new_page()
        page.goto(f'{site}/terrarium.html?speed=200&clock=12:00&debug&relay={relay.url}')
        page.evaluate("localStorage.setItem('gremlets.terrarium.intro', '1')")
        page.reload()
        check('an empty room to start', wait_for(page, "terra.world.creatures.length === 3") and page.evaluate("terra.model.built().length <= 1"))
        check('they plant the first seed and the moss comes in', wait_for(page, "terra.model.done('seed') && terra.model.moss > 0", 30))
        check('they build the first ledge, plank by plank', wait_for(page, "terra.model.done('deck1')", 60))
        check('the ledge is somewhere to stand, with a vine ladder up', wait_for(page, "terra.world.surfaces.some(s => s.owner === 'deck1') && terra.ladders().some(l => l.id === 'deck1')", 5))
        page.screenshot(path=f'{SHOTS}/growing.png')
        # Touch: tapping the moss plants a flower; tapping a Gremlet pokes it.
        n = page.evaluate('terra.plants.length')
        x = page.evaluate("Math.round(terra.model.toJSON() && (window.innerWidth / 2))")
        page.mouse.click(page.evaluate("(() => { const m = terra.model; return Math.round(innerWidth / 2); })()"), IPAD['height'] - 52)
        check('tapping the moss plants a flower', wait_for(page, f'terra.plants.length > {n}', 5))
        c = page.evaluate("(() => { const c = terra.world.creatures.find(c => c.isGrounded && !c.hidden); return [c.id, c.pos.x, innerHeight - c.pos.y - c.size.y * 0.5]; })()")
        page.mouse.click(c[1], c[2])
        check('tapping a Gremlet pokes it', wait_for(page, f"['react','dizzy','wave','alert','pet'].includes(terra.world.byId({c[0]}).activity) || terra.world.byId({c[0]}).activity === 'react'", 3))
        page.close()

        # 3. Night: the Gremlets go to bed, the screen dims.
        page = ctx.new_page()
        page.goto(f'{site}/terrarium.html?preview=60&clock=22:30&debug&relay={relay.url}')
        check('night sky', wait_for(page, "document.body.classList.contains('night')"))
        check('the room dims', wait_for(page, "document.getElementById('tdim').style.opacity === '0.75'"))
        check('they go to bed (in the hanging home, or curled up on the moss)', wait_for(page, "terra.world.creatures.filter(c => c.hidden || c.activity === 'sleep').length >= 2", 60))
        check('installable: manifest and Home Screen tags', page.evaluate("!!document.querySelector('link[rel=manifest]') && !!document.querySelector('meta[name=apple-mobile-web-app-capable]')"))
        page.screenshot(path=f'{SHOTS}/night.png')
        page.close()

        # 4. Linked to the Mac over a sealed room, in the daytime.
        page = ctx.new_page()
        page.goto(f'{site}/terrarium.html?preview=60&clock=12:00&debug&relay={relay.url}&room={ROOM}&side=left#k={SECRET}')
        check('link secret kept out of the address bar', SECRET not in page.url and 'room=' not in page.url, page.url)
        check('connected to the relay', wait_for(page, 'terra.bridge.connected'))
        check('says hello as a Terrarium, sealed', any('"v":2' in p for p in relay.posts) and not any('terrarium' in p for p in relay.posts))
        check('not dimmed by day', page.evaluate("document.getElementById('tdim').style.opacity === '0'"))

        send(status([{'id': 's9', 'project': 'Sneaky', 'state': 'waiting'}]), sealed=False)
        time.sleep(1.5)
        check('ignores an unsealed note', page.evaluate('terra.sessions.length') == 0)

        send(status([{'id': 's1', 'project': 'Project 1', 'state': 'waiting'}]))
        check('a sealed status note arrives', wait_for(page, "terra.sessions[0]?.state === 'waiting'"))
        check('a Gremlet goes to the edge with the lantern', wait_for(page, """(() => { const c = terra.world.byId(terra.helpers.get('s1'));
            return c && c.task?.kind === 'lantern' && c.targetX == null && (c.pos.x < 140 || c.pos.x > innerWidth - 140); })()""", 40))
        check('the recent strip shows it', wait_for(page, "document.querySelector('#trecent .tcard.waiting')?.textContent.includes('needs you')"))
        page.screenshot(path=f'{SHOTS}/lantern.png')

        send(status([{'id': 's1', 'project': 'Project 1', 'state': 'thinking'}, {'id': 's2', 'project': 'Project 2', 'state': 'thinking'}]))
        check('thinking: two helpers with thought clouds', wait_for(page, 'terra.helpers.size === 2'))
        time.sleep(1); page.screenshot(path=f'{SHOTS}/thinking.png')
        before = page.evaluate('terra.model.points')
        send(status([{'id': 's1', 'project': 'Project 1', 'state': 'done'}]))
        check('done: a flag in the moss, a cheer, and a burst of growth', wait_for(page, f'terra.flags.length === 1 && terra.model.tasks === 1 && terra.model.points >= {before} + 5'))
        send(status([{'id': 's1', 'project': 'Project 1', 'state': 'done'}], recent=[{'project': 'Project 1', 'state': 'done', 'at': page.evaluate('terra.model.lastDoneAt')}]))
        time.sleep(1.2)
        check('the same task is not counted twice', page.evaluate('terra.model.tasks') == 1)
        time.sleep(0.6); page.screenshot(path=f'{SHOTS}/done.png')

        # 5. The relay drops; the bridge keeps trying and comes back.
        relay.down = True
        check('notices the relay went away', wait_for(page, '!terra.bridge.connected', 15))
        time.sleep(3)
        relay.down = False
        check('reconnects by itself', wait_for(page, 'terra.bridge.connected', 30))
        send(status([{'id': 's3', 'project': 'Project 3', 'state': 'thinking'}]))
        check('and hears the Mac again', wait_for(page, "terra.sessions[0]?.id === 's3'"))
        send({'type': 'office', 'events': [{'room': 'railroad', 'kind': 'sale', 'title': 'Pixel mug', 'severity': 'good', 'at': time.time()}]})
        check('Back Office events join the strip', wait_for(page, "[...document.querySelectorAll('#trecent .tcard.office')].some(c => c.textContent.includes('Pixel mug'))"))
        # 5b. The big Back Office view (🏢): the building, today's numbers, a lap, rain, fireworks.
        state = {'rooms': ['workshop', 'railroad', 'aquarium', 'postOffice', 'factory', 'board', 'farm'], 'workers': 2, 'lantern': True, 'flag': True,
                 'cargo': 3, 'signal': False, 'fish': [{'n': 'BTC', 'p': -5.5, 's': 1.5, 'z': False, 'e': False}, {'n': 'PEPE', 'p': 2, 's': 1, 'z': False, 'e': False}],
                 'letters': 3, 'unread': 1, 'notes': [True, False, True], 'reminders': ['Gremlets: publish the portfolio'], 'farmGreen': False, 'farmOk': False, 'rain': True, 'level': 5,
                 'report': {'sales': 1, 'salesTotal': 12.5, 'pnl': -3.5, 'bots': 2, 'messages': 3, 'claudeDone': 4, 'farmTrades': 1, 'farmPnl': -54, 'runs': 0, 'reminders': 1, 'updates': 2}}
        send({'type': 'office', 'state': state, 'events': [{'room': 'farm', 'kind': 'trade', 'title': 'Trade · long 1', 'severity': 'info', 'amount': -54, 'at': time.time() + 1}]})
        check('the office state arrives', wait_for(page, "terra.officeView.state?.report?.farmTrades === 1"))
        page.click('#tofficebtn')
        check('🏢 opens the Back Office view', wait_for(page, "!document.getElementById('toffice').hidden && terra.officeView.lap !== null"))
        check('it lists today and the reminders', wait_for(page, "document.querySelector('#toffice .nums').textContent.includes('Racetrack') && document.querySelector('#toffice .rem').textContent.includes('publish')"))
        time.sleep(1.2)
        page.screenshot(path=f'{SHOTS}/office-view.png')
        check('the building is drawn', page.evaluate("(() => { const c = document.querySelector('#toffice canvas'); const d = c.getContext('2d').getImageData(c.width / 2, c.height * 0.7, 1, 1).data; return d[3] > 0 && !(d[0] === 238 && d[1] === 243); })()"))
        page.click('#tofficebtn')
        check('🌿 goes back to the Terrarium', wait_for(page, "document.getElementById('toffice').hidden"))

        # 6. Old links (?terrarium=1 on the habitat) land on the new page with their room and secret.
        old = ctx.new_page()
        old.goto(f'{site}/?terrarium=1&clock=12:00&relay={relay.url}&room={ROOM}&side=left#k={SECRET}')
        check('old Terrarium links open the new page', wait_for(old, "location.pathname.endsWith('terrarium.html')", 10))
        # 7. No Mac: the Back Office demo shows what it does (made-up events).
        demo = ctx.new_page()
        demo.goto(f'{site}/terrarium.html?clock=12:00&debug&officeDemo&relay={relay.url}')
        check('the office demo plays without a Mac', wait_for(demo, "!document.getElementById('toffice').hidden && terra.officeView.events.length >= 2", 15))
        time.sleep(1.5)
        demo.screenshot(path=f'{SHOTS}/office-demo.png')
        browser.close()
    print(f'{passed} passed, {failed} failed  (screenshots in {SHOTS})')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
