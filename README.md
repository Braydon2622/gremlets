# Gremlets

Tiny elemental pixel creatures that live on your Mac desktop. They walk along the Dock line, hop up onto your
app windows, ride along when you drag a window, tumble off when you close it, nap when they're tired, and
show a heart when you pet them.

> 🎥 _Demo GIF coming soon (recorded on a real desktop)._

![The Gremlets lineup](Species/lineup.png)

| Species | Element | Personality |
|---|---|---|
| **Kindlet** | ember | A melting-candle sprite whose flame flares when it's happy and dims to an ember when it naps |
| **Mossling** | moss | A sleepy river pebble that grew a moss blanket and one stubborn sprout |
| **Dropple** | tide | A springy raindrop with a curling tip and the best jumper of the bunch |
| **Nimbit** | storm | A pocket-sized thundercloud whose little bolt crackles when it gets excited |
| **Glimmoth** | glow | A chubby night moth with a fluffy collar and lantern-tipped feelers |
| **Acornet** | grove | An acorn that refused to stay a seed and wears its cap like a beloved hat |
| **Flurrie** | frost | A snowball bunny with icicle ear-tips and a scarf it never takes off |
| **Fizzlet** | spark | A tiny lightbulb spirit whose filament glows brighter the happier it is |
| **Hushwisp** | spirit | A quiet lantern ghost that drifts instead of walking and carries a cool blue flame |
| **Bellcap** | spore | A shy mushroom with a bell-shaped cap whose spots glow in the dark |
| **Kilnby** | clay | A little clay pot that came alive after a hundred years on a shelf. Hollow eyes, warm heart |
| **Dandelet** | bloom | A dandelion cub with a petal mane and a seed-puff tail |
| **Snoozle** | dusk | A velvet mole in a nightcap with a moon on its tummy, who naps whenever it can |

Every creature has 15 animations (57 frames): idle, look-around, walk, crouch, jump, a panicked fall,
a squash landing, dizzy, a big yawn, sleep with a snot bubble, a startled wake-up, a happy jump, petting bliss,
dangling when dragged, and an "!" alert.

![Kindlet's key poses](Species/kindlet/preview.png)

All creatures, names and art are original. The design approach borrows *principles* from classic
creature-collecting games and Ghibli-style nature spirits (a readable silhouette, one strong signature feature,
2–3 main colours plus an accent, and everyday objects or bits of nature that come alive) without copying
any existing character.

## Features

- **Click-through overlay.** Transparent, borderless, always-on-top panels on every screen. Clicks pass straight
  through to your apps except on a creature's opaque pixels (per-pixel hit testing).
- **Window surfaces.** Creatures stand and walk on the top edges of real app windows, ride along when a
  window moves, and fall when it closes, minimizes or gets covered.
- **Physics.** Gravity, one-way platforms, wall bounces, and drag-and-throw using the cursor's release velocity.
- **Behavior AI.** A utility-scored brain picks between idle, look-around, walk, hop, jump-to-window,
  chase-the-cursor (with an "!" first) and sleep (with a yawn first), based on energy and surroundings.
- **Drama.** Hard landings kick up dust, and really hard ones leave a creature dizzy with stars circling its head.
  Poking a sleeper startles it awake, and rubbing the cursor over one makes it melt into a happy wiggle.
- **Multi-monitor and Spaces.** One overlay per screen, creatures can walk across touching monitors, and the
  overlay follows you onto every Space and over full-screen apps.
- **Menu bar app.** Add or send home gremlets, pause, launch at login, and open the custom sprites folder.
- **Bring your own art.** The app loads Aseprite JSON exports directly (see below).
- **Low CPU.** About 1.6–2% CPU with three creatures moving on an Apple Silicon MacBook (see Performance).

## Run it

Requires macOS 13+ and Swift 5.9+ (Xcode or just the Command Line Tools).

```bash
swift run Gremlets                                  # dev run
swift run Gremlets --spawn kindlet,mossling,dropple # pick who shows up
scripts/bundle.sh && open build/Gremlets.app        # real app bundle (needed for Launch at Login)
swift test                                          # engine tests
```

No permissions are required: window *positions* are readable without Screen Recording access (only window
titles need it, and Gremlets never reads them).

## Drawing your own Gremlets

1. In Aseprite, draw your frames (any size; 32×32 matches the built-ins) and add **tags** named
   `idle`, `walk`, `jump`, `fall`, `land`, `sleep`, `react`, `drag`, and optionally `look`, `crouch`, `dizzy`,
   `yawn`, `wake`, `pet`, `alert`. Only `idle` is required; missing ones fall back sensibly. Draw the creature **facing right** with its feet on the bottom row.
2. **File → Export Sprite Sheet**: Layout *Horizontal Strip*, Output ✔ JSON Data (Array or Hash), ✔ Tags.
   Name them `sheet.png` and `sheet.json`.
3. Put both in `~/Library/Application Support/Gremlets/Species/<your-id>/` (menu bar → *Open Custom Sprites Folder…*).
4. Optional `species.json`:
   ```json
   { "name": "Glimmet", "element": "spark", "scale": 3, "walkSpeed": 70, "jumpPower": 1.0, "sleepiness": 1.0 }
   ```
5. Restart Gremlets. A folder with the same id as a built-in species replaces it.

The built-in species are generated by `swift run spritegen` (`Sources/spritegen/main.swift`), which writes
this same format. It's a small part-based pixel-art renderer: each species is a data description (body
shape, ears, tail, accessories, palette), and shared poses drive squash/stretch, arms, legs and facial
expressions. Rounded parts get spherical shading from a top-left light, with hue-shifted colour ramps and a
selective outline, so the bodies read as volumes even at 32 px.

## Architecture

```
Sources/
  GremletsCore/     platform-agnostic engine (no AppKit), unit tested
    World.swift       simulation: physics, grounding, window riding, input (drag/throw/poke/pet)
    Brain.swift       utility AI: scores candidate actions and picks one by weighted random choice
    Surfaces.swift    turns screens + windows into one-way platforms, with occlusion
    Creature.swift    state (activity, energy, facing), per-pixel hit testing
    Species.swift     animation timing + alpha masks, decoupled from any image type
  Gremlets/         macOS front end
    Overlay.swift     click-through NSPanels, CALayer rendering, mouse input, particles
    WindowTracker.swift  CGWindowList → window frames (y-flipped into Cocoa space)
    SpriteLibrary.swift  Aseprite JSON loader + alpha masks
    App.swift         adaptive game loop, menu bar, roster persistence, perf monitor
  spritegen/        part-based pixel-art generator for the 13 built-in species
```

Details and design decisions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Performance

Measured with `GREMLETS_PERF=1` (prints process CPU% every 10 s from `getrusage`), release build,
MacBook (Apple Silicon), macOS 15:

| Scenario | CPU |
|---|---|
| 3 creatures walking/jumping (30 Hz loop, 10 Hz window polling) | 1.6–2.0% |

How it stays cheap:
- The loop rate adapts: 60 Hz only while something is airborne or being dragged, 30 Hz while walking, 8 Hz when everyone is idle or asleep.
- Window polling (the most expensive call) runs at 4–10 Hz and only jumps to 60 Hz while a window that a creature is standing on is moving.
- Sprite layers only get new `contents` when the animation frame actually changes. Hearts and Zzz particles are pure Core Animation, so they cost no per-frame CPU.
- Timer tolerance lets macOS coalesce wakeups.

## Roadmap

- [ ] Creatures notice each other (follow, play, bump)
- [ ] Peek around screen edges
- [ ] Demo GIF + signed/notarized download
- [ ] Windows port of the platform layer (the engine is already platform-independent)
