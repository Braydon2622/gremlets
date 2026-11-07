# Gremlets architecture

## Layers

```
┌──────────────────────── macOS front end (Sources/Gremlets) ────────────────────────┐
│ AppDelegate: adaptive Timer loop ──► WindowTracker.snapshot() ──► world.setEnvironment │
│                                  ──► world.step(dt) ──► OverlayController.render()     │
│ OverlayController: NSPanel per screen, CALayer per creature, mouse → world input       │
└──────────────────────────────────────────┬───────────────────────────────────────────┘
                                           │ plain Swift values (Vec2, Rect, WindowInfo)
┌──────────────────────── GremletsCore (no AppKit) ──────────────────────────────────────┐
│ World ─ physics, grounding, riding, input     Brain ─ utility AI                        │
│ SurfaceBuilder ─ occlusion-aware platforms    SpeciesInfo ─ animation timing + masks    │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

The engine uses one coordinate space: **global desktop points, y-up** (Cocoa screen space). The
platform layer converts once at the boundary. CGWindowList reports top-left-origin rects relative to
the primary display, so `y_cocoa = primaryHeight − y_cg − height`.

A Windows port only has to supply screens, window rects, the cursor, a timer and a renderer.

## Click-through overlay

A full-screen transparent window normally either eats every click or ignores every click. Returning
`nil` from `hitTest` does **not** forward a click to another app. So:

1. Each screen gets a borderless, non-activating `NSPanel` at `.floating` level with
   `ignoresMouseEvents = true` (clicks pass through to whatever is underneath).
2. A global and a local `mouseMoved` monitor (plus every tick) check whether the cursor is over an
   **opaque pixel** of a creature, using per-frame alpha masks built when the sprites load, with 1px of slack.
3. Only then does that screen's panel flip to `ignoresMouseEvents = false`, so the next click lands on
   the creature. As soon as the cursor leaves, it flips back.
4. `.nonactivatingPanel` + `acceptsFirstMouse` mean clicking a creature doesn't steal focus from the app
   you're working in.
5. `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` keeps
   the overlay on every Space, over full-screen apps, and out of Cmd-Tab and Mission Control.

Global mouse-moved monitoring needs no Accessibility permission (only key events do).

## Window surfaces

`SurfaceBuilder.build` turns screens + windows (front-to-back) into one-way platforms:

- Each screen's `visibleFrame.minY` becomes a floor (so creatures walk on top of the Dock line).
- Each window's top edge becomes a platform, **minus** the x-ranges covered by any window in front of it
  at that height (interval subtraction). The result is the visible part of the edge, possibly split in
  several segments. Segments under 24pt, or too close to the top of the screen, are dropped.

Windows are read with `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, filtered to layer 0, excluding
our own process. Bounds don't require Screen Recording permission.

**Riding windows:** each creature remembers the `ownerID` (window number) it stands on. When a new
snapshot arrives, the delta between that window's old and new frame is applied to the creature before
the surfaces are rebuilt, so dragging a window carries its passengers. If the window disappeared, moved
to another Space, or got covered, the next grounding check finds no support and the creature falls.

Polling is adaptive: about 10 Hz normally, 4 Hz when the world is idle, and 60 Hz for 0.6 s after a
*ridden* window changes, so riding looks smooth without paying for 60 Hz polling all the time.

## Physics

- Semi-implicit Euler with `dt` clamped to 1/20 s (no explosions after sleep or wake).
- One-way platforms: while falling, land on the **highest** surface whose y was crossed this step
  (`prev.y ≥ s.y ≥ next.y`) at the new x. Because it tests crossing rather than overlap, fast falls
  can't tunnel through.
- Walls are the current screen's edges, extended across touching monitors at that height. Throws bounce
  with 45% restitution, and the ceiling clamps.
- Jumps solve the ballistic equations directly: pick a target point on a reachable surface, aim for an
  apex 40pt above it, `vy = √(2g·apex)`, flight time `t = (vy + √(vy² − 2g·dh)) / g`, `vx = dx / t`.
- Throw velocity comes from the cursor samples in the last 100 ms of the drag, capped at 2400 pt/s.

## Behavior (utility AI)

`Activity` is a small state machine (idle, walk, chase, alert, crouch, airborne, land, dizzy, yawn, sleep,
wake, react, pet, dragged). One-shot activities (yawn, wake, react, alert, land) last exactly one play-through
of their animation, so art and behavior can't drift apart. Chains add drama: tired → yawn → sleep → startled
wake; spotting the cursor → alert "!" → chase; landing faster than 1700 pt/s → dizzy with orbiting stars.
Physical states (airborne, land, crouch) are driven by the world. When a *voluntary* activity times out,
`Brain.decide` scores every candidate:

| Choice | Weight |
|---|---|
| idle | 1.0 |
| walk | 1.5 × (0.4 + energy) |
| hop | 0.35 × energy |
| jump to window | 1.3 × (0.3 + energy), only if a reachable surface exists |
| sleep | (0.55 − energy) × 6 × species sleepiness, only when tired |
| chase cursor | 0.45 × energy, only if the cursor is nearby and roughly level |

Then it picks one by weighted random choice. Adding a behavior means appending one `Choice`. Species
tune it through `walkSpeed`, `jumpPower` and `sleepiness` (Mossling naps a lot, Dropple jumps high).

At ledges, a walker turns back 65% of the time and otherwise walks off and tumbles down.

## Social behavior

Social behaviors live in `Social.swift` and plug into the same utility brain. When friends are nearby
(same level, within ~360 pt), new choices appear: **greet** (walk over, both wave, heart; 90 s cooldown per pair),
**tag** (chaser/runner roles that swap on contact, with a short immunity so they don't tag straight back),
**follow**, **nap together** (when tired and a friend is asleep), **stack** (hop onto a friend's head) and
**join a dance** (a dancer invites idle neighbours, so dance parties spread).

**Stacking** reuses the platform system: every standing creature contributes a narrow one-way surface at the
top of its head (`headTop` is measured from the idle frame's alpha mask). Riders reference the carrier with a
reserved owner id range, and each step updates lower creatures first, then moves riders by their carrier's
delta, so a stacked friend rides along when the carrier walks, jumps or rides a moving window.

**Bumps:** two walkers meeting head-on bonk and bounce apart 35% of the time (otherwise they squeeze past).
**Startle:** a cursor swipe faster than 2,800 pt/s within 90 pt makes a creature hop away, or take off if it can fly.

**Flight** is a separate steering mode (no gravity): fly toward a point 34 pt above a chosen surface with
eased velocity and a sinusoidal flutter, then drop the last bit and land through the normal one-way platform
check.

A **soak test** runs 8 creatures for 10 simulated minutes with sliding and closing windows and a wandering
cursor. It asserts no creature leaves the screen or produces NaNs, and that every behavior actually occurs.

## Rendering

One `CALayer` per creature with `magnificationFilter = .nearest` (crisp pixels at 3×), anchored at the
feet, mirrored with an affine transform for facing left. `contents` only changes when the animation
frame index changes, and all updates happen inside a `CATransaction` with actions disabled.
Hearts and Zzz particles are fire-and-forget `CAAnimationGroup`s, so the render server animates them.

## Sprites

`SpriteLibrary` reads Aseprite's JSON export (array or hash `frames`, `meta.frameTags` with
forward/reverse/pingpong). It also builds alpha masks per frame for hit testing. Built-ins come from the
app bundle (or the repo's `Species/` in dev), and user art in `~/Library/Application Support/Gremlets/Species`
overrides them by id.

## Ownership (wallet-verified unlocks)

```
menu "Connect Wallet…" ─► browser opens http://127.0.0.1:47920/connect (nonce baked into the page)
   page: eth_requestAccounts ─► personal_sign(message with nonce)          (free, no transaction)
   page ─► POST /wallet/proof?address&signature&nonce   (X-Gremlets header, same origin)
app:  eth_chainId == 84532?  ─► eth_call ecrecover precompile (0x…01) with EIP-191 hash ‖ v ‖ r ‖ s
      signer == claimed?     ─► batched eth_call ownerOf(1…50) on the Gremlets contract
      store {address, ownedTokenIDs, checkedAt}  ─► Access recomputes owned / demo per species
```

- **Why the precompile:** recovering a secp256k1 public key needs big-integer elliptic-curve math. The node
  already has to be trusted for `ownerOf`, so asking it for `ecrecover` adds no new trust and keeps all
  EC code out of the app. Hashing (Keccak-256 + EIP-191) runs locally, so the node only sees a hash and a signature.
- **Access rules** live in `GremletsCore/Ownership.swift` as pure value types (`Access`, `DemoPolicy`) and are
  unit tested with an injected clock. Kinds: `owned`, `custom` (species outside the collection), `demo`, and
  `unlocked` (no deployment configured yet). The demo session starts with the first demo Gremlet, ends quietly if
  you send them all home, and otherwise fires once so the app can play the goodbye wave and remove them.
- **Local server hardening:** loopback only. A `Host` allow-list blocks DNS rebinding. State-changing routes need
  a custom header, which forces a CORS preflight that is never approved. The page is served with
  `default-src 'none'` CSP and `frame-ancestors 'none'`.

## Presence (calls, away, power)

Once a second the app samples four cheap facts and hands them to `PresenceTracker` (pure, unit tested):

| Fact | Source | Permission |
|---|---|---|
| Camera in use by any app | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` on every video device | none |
| Microphone in use by another app | CoreAudio process objects `kAudioProcessPropertyIsRunningInput` (macOS 14.2+); older systems fall back to the default input device, only when it's input-only | none |
| Seconds since last input | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)` | none |
| Low Power Mode | `ProcessInfo.isLowPowerModeEnabled` | none |

The tracker turns those into edge-triggered events: `hide(.manual | .call)`, `show`, `away`, `welcomeBack`, plus a
tick-rate cap (2 Hz hidden, 12 Hz away, 30 Hz on Low Power). Calls get an 8-second grace period because meeting apps
blip the mic on and off when you mute. Using the per-process input flag matters: a headset's device-level
"running" flag is also true whenever music plays. Hiding calls `orderOut` on the overlay panels (rather than
alpha 0), so screen-capture APIs have nothing to pick up, and the simulation stops so no time "piles up".
The boss key uses Carbon `RegisterEventHotKey`, which unlike global key monitors needs no Accessibility permission.

## The grown world

Everything the Gremlets build lives in the engine as plain data and becomes surfaces the physics already understands:

- **Grove** (`Grove.swift`): six plants in a corner garden, levelled by Claude tasks (`feedGrove`). Their geometry
  (`ledges(floor:)`) turns into one-way `Surface`s (the bouncecap is a trampoline, the skyvine a ladder of leaves).
- **Village** (`Construction.swift`): finished Claude buildings, the mine and the merchant's items are `House` records
  along the floor; roofs are surfaces. Bridges Gremlets build between windows crumble when a window moves.
- **Bonsai** (`Bonsai.swift`): one `Bonsai` record per project, grown by `ClaudeBuddy` events. `BonsaiGeometry.layout`
  is a pure function of the record (seeded by an FNV-1a hash of the project name), so the same work always grows the
  same tree and the app, the postcard, the journal and the web port all draw it identically. `rebuildAttached()`
  places live trees on their terminal window's visible top edge (or in the nursery) and turns foliage pads and the
  terminal's mossy ledges into surfaces; `attachedOwnerWindow` lets riders on those surfaces move with the window
  exactly like riders on a window top.
- **Rendering** (`BonsaiArt`, `IslandArt`, `BuildArt`, `GroveArt`): procedural pixel art drawn on a tiny
  `PixelCanvas` and shown at 3× with nearest-neighbour scaling, regenerated only when its cache key changes.
- **Events** (`ClaudeBuddy` → `World.claudeTool`, `bonsaiGrow`, `feedGrove` …): the Claude Code hook sends only event
  names, the project folder's name and a tool name. Nothing about files, prompts or output ever reaches the app.
