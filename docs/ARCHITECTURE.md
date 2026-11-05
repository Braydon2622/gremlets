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
