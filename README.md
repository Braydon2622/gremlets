# Gremlets

Fifty one-of-a-kind pixel creatures that live on your Mac desktop: gentle animals, a few bugs, a tiny
dragon, a couple of friendly mythical beasts, gentle nature spirits (a stack of river stones, a lake moss ball, a
mote of evening light) and old guardian machines that nature reclaimed (one has a meadow growing on its head). They walk along the Dock line, hop and fly up onto
your app windows, ride along when you drag a window, tumble off when you close it, play tag with each other,
nap in piles, stand on each other's heads, throw dance parties, and show off a signature move.

> 🎥 _Demo GIF coming soon (recorded on a real desktop)._

![The 50 Gremlets](Species/lineup.png)

| Family | Count | Some of them |
|---|---|---|
| Animals | 15 | Flurrie the frost bunny, Dandelet the dandelion lion cub, Capyzen the hot-spring capybara, Calicat the calico kitten |
| Spirits | 15 | Glowmote, Pebblin the stone stack, Marimoss the lake moss ball, Sakurin the cherry blossom, Puffcloud |
| Guardians | 13 | Mosswarden with a meadow on its head, Pondhead with a rain pond on its head, Ivybolt, Beaconbit, Slumberbolt |
| Insects & Bugs | 4 | Silkwing the butterfly, Zipwing the dragonfly, Prismite the jewel beetle, Snipleaf the leafcutter ant |
| Mythical | 2 | Kindlet the candle spirit, Inklet the baby kraken |
| Dragons | 1 | Mintwyrm the jasmine dragon |

Full catalog with personalities and signature moves: [docs/SPECIES.md](docs/SPECIES.md).

Every creature has 20 animations (83 frames): idle, look-around, walk, run, crouch, jump, fly, a panicked fall,
a squash landing, dizzy, a big yawn, sleep with a snot bubble, a startled wake-up, a happy jump, petting bliss,
dance, wave, dangling when dragged, an "!" alert, and its signature move.

![Mosswarden's key poses](Species/mosswarden/preview.png)

All creatures, names and art are original. The design approach borrows *principles* from classic
creature-collecting games and gentle folk-tale nature spirits (a readable silhouette, one strong
signature feature, 2–3 soft colours, and a touch of nature magic: frost ears, a petal mane, a boulder
that wakes up) without copying any existing character. No Gremlet wears clothing or carries props.

## Features

- **Click-through overlay.** Transparent, borderless, always-on-top panels on every screen. Clicks pass straight
  through to your apps except on a creature's opaque pixels (per-pixel hit testing).
- **Window surfaces.** Creatures stand and walk on the top edges of real app windows, ride along when a
  window moves, and fall when it closes, minimizes or gets covered.
- **Physics.** Gravity, one-way platforms, wall bounces, and drag-and-throw using the cursor's release velocity.
  Hard landings kick up dust, and really hard ones leave a creature dizzy with stars circling its head.
- **Flight.** Winged species (butterflies, bats, dragons, the griffin...) take off and flutter to other windows.
- **Social life.** Creatures notice each other: they walk over and wave hello, play tag (and swap roles when
  tagged), follow a friend around, curl up next to a sleeping friend, hop onto a friend's head and ride along,
  bonk into each other, and join in when someone starts dancing.
- **Signature moves.** Each species has one: fire breath, steam puffs, a fiddle tune, a rainbow fan display, ink
  clouds, a dino stomp, a three-headed bark...
- **Cursor play.** They turn to look at your cursor, wave at it, chase it (with an "!" first), get startled by a
  fast swipe (fliers take off), and melt into a happy wiggle when you rub the cursor over them.
- **Behavior AI.** A utility-scored brain picks what to do next from energy, species traits and surroundings.
- **Multi-monitor and Spaces.** One overlay per screen, creatures can walk across touching monitors, and the
  overlay follows you onto every Space and over full-screen apps. They also sneak to screen edges to peek around them.
- **Menu bar app.** Add any of the 50 (grouped by family) or a random party of 5, send them home, pause,
  launch at login, and open the custom sprites folder.
- **Bring your own art.** The app loads Aseprite JSON exports directly (see below).
- **Low CPU.** About 1–3% CPU with eight creatures on an Apple Silicon MacBook (see Performance).

## Companion features

**Safe to keep running at work.** Gremlets slip off screen whenever any app is using your camera or microphone
(Zoom, Meet, FaceTime...), so they never show up in a screen share, and come back a few seconds after the call (macOS's own "Hey Siri" and dictation listeners don't count as a call)
ends. *Hide During Calls* turns this off. **⌃⌥G** hides or shows them from anywhere (or `gremlet hide` / `gremlet show`
in a presentation script). Hidden panels are removed from the screen entirely, not just made transparent, and the
app drops to about 0% CPU. No permissions are needed: macOS reports whether a camera or mic is in use without
giving out any audio or video.

**They notice when you're away.** After 5 minutes without keyboard or mouse input they settle down for a nap (and
the loop slows down). When you come back they wake up and one waves hello. On Low Power Mode the animation loop is capped
at 30 Hz.

**Focus buddy.** Menu bar → *Focus for 25/50 min*. A countdown appears next to the menu bar icon; your Gremlets
settle down and doze while you work (no flying, no tag), then wake up and throw a dance party when your break
starts, and one waves when the break is over. The menu shows today's focused minutes and your
day streak, and every Gremlet that keeps you company through a session grows closer to you. Optional
*Water & Stretch Reminders* every 45 minutes. Late at night
they get sleepy faster, a gentle hint to log off.

**Coding companion.** A tiny local control channel lets scripts make your Gremlets react:

```bash
scripts/gremlet run npm test      # dance if the tests pass, fall over dizzy if they fail (exit code preserved)
make && scripts/gremlet pass || scripts/gremlet fail
scripts/gremlet done              # after any long job: the nearest Gremlet pops up and waves
scripts/gremlet focus 50          # start a focus session from the terminal
scripts/gremlet hide              # before presenting; `gremlet show` brings them back
scripts/gremlet say "Deploy finished" 10   # a Gremlet pops up with a speech bubble (plain text, max 120 chars)
source scripts/gremlet-shell-hook.zsh   # zsh: a Gremlet waves (or keels over) when any command takes over 30 s
```

**Hobbies.** While you're at your Mac, Gremlets now and then settle down to a hobby: they grow a flower in a pot,
paint a picture on an easel, build a block tower or knit a scarf. Sometimes they work right on the floor; sometimes one
floats up on a balloon to a little wooden shelf it puts up on the side of a nearby window and works up there (the shelf
rides along when you move the window and doesn't care if another window covers it). The creation grows as they work,
friends wander over to watch and clap, clicking a busy Gremlet cheers it on (a little burst of progress), and when you
step away they doze off beside their work until you're back. Finished flowers get planted along the bottom of the
screen and finished paintings lean there too, so a busy week leaves a little garden (menu → *Clear Garden*). Rest the cursor
on a busy Gremlet and it tells you what it's making ("Painting a starry night · 40%"); click the creation itself to
help (water the plant, add a dab of paint). Gremlets also wander over to water the planted garden, and in the evening
shelves get a little glowing lantern. At most two hobbies run at once, with a few minutes' rest in between. `gremlet hobby [garden|paint|build|knit] [shelf]` starts one now.

**Claude buddy.** Send Claude Code a prompt and a Gremlet floats up to a shelf on the side of that Claude window (or
flies, if it has wings) and works there for as long as Claude does; the creation is finished the moment Claude is. Then
it shows it off and says "SalesCheatCodeLive: Claude is done ✓" (or "PhotoToPart: Claude needs your OK" when Claude is
waiting on you), and floats back down a little later. Each Claude session gets its own Gremlet, the menu counts what
they made today, and *Claude Buddy* in the menu turns it off.

`scripts/gremlet-claude-hook` connects Claude Code's `UserPromptSubmit`, `Stop`, `Notification` and `SessionEnd` hooks
(setup is in the script's header). It sends only the event, the session id, the project folder's name and a process id.
The app finds the window by walking up from that process to the terminal or editor that owns it (process ids and
window bounds only, never titles or contents). A window with no room beside it (full width) gets a Gremlet working on
the floor below it. The engine side (`GremletsCore/Work.swift`) is pure Swift with its own tests.

It listens on `127.0.0.1:47920` only, every request needs an `X-Gremlets` header (so a web page can't trigger it
cross-site without a CORS preflight, which it never approves), and it can only trigger animations and the timer.

**Bond.** Each Gremlet remembers days and hours together, pets, pokes and focus sessions, and levels up from *New friend* to
*Kindred spirit*. Closer friends wave at your cursor and follow it more, and from *Friend* up they show off their
signature move when you pet them. A level-up sets off a shower of hearts. See *Your Gremlets* in the menu.

## Run it

Requires macOS 13+ and Swift 5.9+ (Xcode or just the Command Line Tools).

```bash
swift run Gremlets                                      # dev run
swift run Gremlets --spawn flurrie,kindlet,mosswarden       # pick who shows up
scripts/bundle.sh && open build/Gremlets.app            # real app bundle (needed for Launch at Login)
swift test                                              # engine tests, including a 10-minute simulated soak test
swift run spritegen                                     # regenerate all 50 sprite sheets
```

No permissions are required: window *positions* are readable without Screen Recording access (only window
titles need it, and Gremlets never reads them).

## Web habitat (phones, tablets, any browser)

`web/` is the same world in a browser tab: a JavaScript port of the engine (`web/js/engine.js`, same rules
and tuning as the Swift core) plus a canvas renderer that uses the exact same sprite sheets. Since a browser
has no app windows, Gremlets climb floating shelves, mossy ledges and clouds instead. The sky follows your
local time (day, dusk, night with stars).

- **Touch & mouse:** tap to poke, hold to pet, drag to throw, and they chase your finger.
- **Picker:** add any of the 50 (grouped by family), or Shuffle for a random group. Up to 12 at once.
- **Showcase mode:** `index.html?showcase=kindlet` shows one Gremlet with its nameplate, sized for an NFT's live preview.
- **No build step:** plain ES modules, so it can be hosted anywhere static.

```bash
python3 -m http.server 8765        # from the repo root, then open http://localhost:8765/web/
open http://localhost:8765/web/dev-preview.html   # phone-size + NFT-preview frames side by side
scripts/test-web.sh                # engine tests (incl. soak test) in macOS's built-in JavaScriptCore, no Node needed
```

## NFTs (testnet)

Each of the 50 Gremlets is a one-of-a-kind collectible; owning Gremlet #N unlocks it in the desktop app.
- `contracts/`: minimal ERC-721 on OpenZeppelin 5.1.0, Foundry tests (incl. fuzz), 100% coverage. No payment
  logic, no upgrades, max supply fixed at 50, optional permanent metadata freeze. See [contracts/README.md](contracts/README.md).
- `nft/console.html`: dependency-free creator console that deploys and mints from your own browser wallet
  (keys never leave the wallet; Base Sepolia testnet only). Verified end-to-end against a local `anvil` chain.
- `nft/metadata`, `nft/images`: ERC-721 metadata with portraits, traits and a live `animation_url` into the web habitat.

### Wallet-verified unlocks in the desktop app

Gremlets you hold stay on your desktop as long as you like. Everyone can try any other Gremlet in a **demo**
(3 at a time, 15-minute sessions; when time's up they wave goodbye and head home). Your own drop-in sprites are
never gated.

1. Menu bar → **Connect Wallet…** opens a small page served by the app on `127.0.0.1`.
2. Your browser wallet signs a plain text message with a one-time nonce. That's free: no transaction, no
   permissions, and the app never sees a private key or seed phrase.
3. The app recovers the signer by calling the chain's `ecrecover` precompile (so no elliptic-curve code ships in
   the app), checks it matches the wallet, then reads `ownerOf(1…50)` in one batched JSON-RPC call.
4. Only the public address and the owned token ids are stored. Ownership is re-read every few hours, so a sold
   Gremlet goes back to demo mode.

Safety details: the app refuses any network that isn't Base Sepolia (chain id 84532). Nonces are single-use and
expire after 10 minutes. High-s (malleable) signatures are rejected. The local server checks the `Host` header
(blocking DNS rebinding) and sends a strict CSP on the page. Keccak-256, EIP-191 hashing and EIP-55 checksums are
implemented in `GremletsCore` and tested against Foundry's `cast`. Verified end-to-end against a local `anvil`
chain: a real owner proof, an impersonation attempt, nonce replay, a transferred token, and a wrong-chain node.

Gating switches on once `nft/deployment.json` (chain + contract address, written by the console after deploying)
is present. Until then the build is a preview with everything unlocked. `--visitor` previews demo mode;
`--unlock-all` turns gating off.

## Drawing your own Gremlets

1. In Aseprite, draw your frames (any size; 32×32 matches the built-ins) and add **tags** named
   `idle`, `walk`, `jump`, `fall`, `land`, `sleep`, `react`, `drag`, and optionally `look`, `run`, `crouch`, `fly`,
   `dizzy`, `yawn`, `wake`, `pet`, `dance`, `wave`, `alert`, `special`. Only `idle` is required; missing ones fall
   back sensibly. Draw the creature **facing right** with its feet on the bottom row.
2. **File → Export Sprite Sheet**: Layout *Horizontal Strip*, Output ✔ JSON Data (Array or Hash), ✔ Tags.
   Name them `sheet.png` and `sheet.json`.
3. Put both in `~/Library/Application Support/Gremlets/Species/<your-id>/` (menu bar → *Open Custom Sprites Folder…*).
4. Optional `species.json`:
   ```json
   { "name": "Glimmet", "element": "spark", "family": "insect", "scale": 3, "walkSpeed": 70,
     "jumpPower": 1.0, "sleepiness": 1.0, "flies": true, "special": "sparkle" }
   ```
5. Restart Gremlets. A folder with the same id as a built-in species replaces it.

The built-in species come from `swift run spritegen` (`Sources/spritegen/`), a small part-based pixel-art
renderer. Each species is a data recipe (body shape, ears, horns, wings, tail, markings, held item, palette)
built from a library of ~70 parametric parts. Shared poses drive squash and stretch, arms, legs, wing flaps
and facial expressions, so all 50 creatures animate consistently. Rounded parts get spherical shading from a
top-left light, with hue-shifted colour ramps and a selective outline, so bodies read as volumes even at 32 px.

## Architecture

```
Sources/
  GremletsCore/     platform-agnostic engine (no AppKit), unit tested
    World.swift       simulation: physics, grounding, window riding, flight, bumps, stacking, input
    Social.swift      greet, follow, nap together, tag, stack, dance parties, signature moves, peeking
    Companion.swift   focus mode, signals (pass/fail/done...), bond levels
    Presence.swift    hide on calls / boss key, away + welcome back, Low Power cap, focus log + streaks
    Ownership.swift   owned / custom / demo rules, demo session clock, Ethereum encoding (EIP-191, ABI, EIP-55)
    Keccak.swift      dependency-free Keccak-256
    Brain.swift       utility AI: scores candidate actions and picks one by weighted random choice
    Surfaces.swift    turns screens + windows into one-way platforms, with occlusion
    Creature.swift    state (activity, energy, facing, social role), per-pixel hit testing
    Species.swift     animation timing, alpha masks, traits, decoupled from any image type
  Gremlets/         macOS front end
    Overlay.swift     click-through NSPanels, CALayer rendering, mouse input, particle effects
    WindowTracker.swift  CGWindowList → window frames (y-flipped into Cocoa space)
    SpriteLibrary.swift  Aseprite JSON loader + alpha masks
    App.swift         adaptive game loop, menu bar, roster persistence, perf monitor
    Companion.swift   focus timer, bond storage, local control channel (127.0.0.1)
    SystemSignals.swift  camera/mic-in-use (CoreMediaIO/CoreAudio), idle time, Low Power, Carbon global hotkey
    Wallet.swift      wallet-link page + signature check, read-only JSON-RPC ownership reads (Base Sepolia)
  spritegen/        part-based pixel-art generator for the 50 built-in species
web/
  js/engine.js      JavaScript port of GremletsCore (tested headlessly with JavaScriptCore)
  js/habitat.js     canvas renderer, scenery, touch/mouse input, picker, showcase mode
  js/sprites.js     Aseprite sheet loader + alpha masks;  js/effects.js  pixel particles
```

Details and design decisions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Performance

Measured with `GREMLETS_PERF=1` (prints process CPU% every 10 s from `getrusage`), release build,
MacBook (Apple Silicon), macOS 15:

| Scenario | CPU |
|---|---|
| 3 creatures walking/jumping (30 Hz loop, 10 Hz window polling) | 1.6–2.0% |
| 6 creatures (15 animations each, particles) | 2.0–2.4% |
| 8 creatures (v3: flight, tag, dance parties, mostly at 60 Hz) | 1.0–3.2% |
| 3 creatures with call/idle detection running once a second | 1.0–2.1% |
| Hidden (on a call or ⌃⌥G) | ~0% (2 Hz housekeeping only) |

How it stays cheap:
- The loop rate adapts: 60 Hz only while something is flying, running, airborne or being dragged, 30 Hz while walking, 12 Hz when everyone is idle or asleep.
- Window polling (the most expensive call) runs at about 3 Hz when nobody stands on a window, 10 Hz when someone does, and 60 Hz only while that window is moving.
- Sprite layers only get new `contents` when the animation frame actually changes. All particles (hearts, notes, fire, stars) are fire-and-forget Core Animation, so they cost no per-frame CPU.
- Timer tolerance lets macOS coalesce wakeups.

## Roadmap

- [x] Creatures notice each other (greet, tag, follow, nap, stack, bump, dance)
- [x] Peek around screen edges
- [x] Web habitat (phones + live NFT view)
- [x] NFT contract: 50 one-of-a-kind ERC-721 tokens (OpenZeppelin, 18 tests, 100% coverage), creator console, metadata + portraits. Testnet only.
- [x] Focus buddy, coding companion (`gremlet` command), bond levels
- [x] Wallet-verified unlocks in the desktop app (+ demo mode for visitors)
- [ ] Host web habitat + metadata (GitHub Pages)
- [ ] Demo GIF + signed/notarized download
- [ ] Windows port of the platform layer (the engine is already platform-independent)
