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

**Focus buddy.** Menu bar → *Focus for 25/50 min*. A countdown appears next to the menu bar icon; your Gremlets
settle down and doze while you work (no flying, no tag), then wake up and throw a dance party when your break
starts, and one waves when the break is over. Optional *Water & Stretch Reminders* every 45 minutes. Late at night
they get sleepy faster, a gentle hint to log off.

**Coding companion.** A tiny local control channel lets scripts make your Gremlets react:

```bash
scripts/gremlet run npm test      # dance if the tests pass, fall over dizzy if they fail (exit code preserved)
make && scripts/gremlet pass || scripts/gremlet fail
scripts/gremlet done              # after any long job: the nearest Gremlet pops up and waves
scripts/gremlet focus 50          # start a focus session from the terminal
source scripts/gremlet-shell-hook.zsh   # zsh: a Gremlet waves (or keels over) when any command takes over 30 s
```

It listens on `127.0.0.1:47920` only, every request needs an `X-Gremlets` header (so a web page can't trigger it
cross-site without a CORS preflight, which it never approves), and it can only trigger animations and the timer.

**Bond.** Each Gremlet remembers days and hours together, pets and pokes, and levels up from *New friend* to
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
- [ ] Wallet-verified unlocks in the desktop app (+ demo mode for visitors)
- [ ] Host web habitat + metadata (GitHub Pages)
- [ ] Demo GIF + signed/notarized download
- [ ] Windows port of the platform layer (the engine is already platform-independent)
