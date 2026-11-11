# The Terrarium: a permanent Gremlets home on the iPad (and updates on the iPhone)

Braydon's idea: an old iPad sits on the desk all day as a living Gremlets habitat. Gremlets walk over from the Mac,
live there, sleep there at night, and the iPad doubles as a calm status board for what Claude (and later the
Back Office, see BACK-OFFICE.md) is doing. Build it in phases; finish and test each phase before the next.

Reuse what exists: `web/` (habitat, bridge.js two screen protocol over ntfy, rain cloud, boss), `PhoneLink.swift`,
`ScreenBridge.swift`, `ClaudeBuddy.swift` (knows when Claude is thinking / waiting / done).

## Phase 1: Terrarium mode in the web habitat (no App Store needed)
- `web/?terrarium=1` (also offered in the Mac's "Link another screen" window as "Make this iPad a Terrarium").
- Installable: web app manifest + apple-mobile-web-app tags so "Add to Home Screen" opens full screen with no
  Safari bars. Pixel icon from the menu logo.
- Always on: Screen Wake Lock API (catch rejection); a first-run card tells Braydon to set Auto-Lock to Never
  while charging and how to use Guided Access.
- Lives by the real clock: day / dusk / night sky; at night Gremlets yawn, go to their nests and the screen dims
  to about 20%; they wake at 7am. Slowly shift the whole scene a few pixels each hour (burn-in protection).
- Permanent residents: the iPad keeps its own Gremlets and garden (localStorage), plus visitors from the Mac
  over the existing bridge. Reconnect forever (backoff), and reload itself once a night at 4am.
- Status from the Mac (new note type `status`): for each Claude Code session, project + state
  (thinking / waiting / done). On the Terrarium: thinking = thought cloud over a Gremlet, waiting = a Gremlet
  holds up a lantern by the screen edge with the project name on a small sign, done = a flag planted in the moss
  plus a sparkle. A small, quiet "recent" strip at the bottom shows the last 5 events as pixel cards.
- Privacy: the ntfy relay is public. Encrypt every note with AES-GCM (CryptoKit on the Mac, WebCrypto in the
  browser) using a key derived from the pairing code that travels only inside the QR / link. Project names are
  sent only if Braydon turns on "Show project names"; otherwise "Project 1", "Project 2".
- Tests: unit tests for the status note + encryption round trip (Swift and JS); a Playwright run of
  `?terrarium=1` at iPad size for night mode, reconnect and the lantern state.

## Phase 2: iPhone widget, Live Activity and Dynamic Island (native, needs Braydon's go-ahead)
- Add an iOS app target (SwiftUI) that shares GremletsCore and the sprites.
- Home Screen / Lock Screen widget (WidgetKit): a snapshot of the Terrarium (which Gremlets are home, Claude's
  state, flags planted today). Widgets refresh on a schedule iOS controls (roughly every 15 to 60 minutes), so
  they are a glanceable picture, not a live animation.
- Live Activity + Dynamic Island for real time: while a Claude session runs, a Gremlet sits in the Dynamic Island
  (thought cloud / lantern / flag). Updating it while the app is closed needs Apple push notifications from a
  small server (for example a Netlify Function holding the push key). Until that exists, ntfy's own iOS app can
  deliver "Claude needs you" as a normal notification.
- Apple Developer Program ($99/year) is needed to keep it installed past 7 days and to send push. Ask Braydon
  before signing up for anything or spending money; he signs in and enters any keys himself.

## Phase 3 (optional): native iPad Terrarium app
- Same scene as Phase 1 in SwiftUI/SpriteKit for smoother animation and real background refresh.

## Rules for this work
- Commit locally in small, readable commits. Do NOT push to GitHub or open pull requests, and never batch
  automated commits to any online account.
- No secrets in the repo; keys live in the macOS Keychain or iOS Keychain.
- Keep CPU low (target under 3% on the Mac side) and run all existing tests before calling a phase done.
- Update STATUS.md at the end of each phase with what works and how to try it.
