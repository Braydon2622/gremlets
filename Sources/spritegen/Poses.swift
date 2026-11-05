// Shared poses and animations. Every species is rendered through the same 20 animations,
// so behavior code can rely on them existing for all 50 Gremlets.

import Foundation

enum Eyes { case open, blink, sleep, happy, wide, squint, dizzy, sleepy }
enum Mouth { case none, smile, cat, open, yell, yawn, grin, wobble }
enum Arm { case down, up, out, swing(Double), flail(Double), tucked, rub, wave(Double) }
enum Legs { case stand, step(Double), dangle(Double), tucked }
enum Brows { case none, worried, determined }

struct Pose {
    var sx = 1.0, sy = 1.0      // squash & stretch
    var lift = 0.0              // body raised off the ground
    var lean = 0.0              // whole-body x offset
    var tilt = 0.0              // head-top parts x offset
    var eyes: Eyes = .open
    var look = 0.0              // eye x shift
    var mouth: Mouth = .smile
    var arms: (Arm, Arm) = (.down, .down)
    var legs: Legs = .stand
    var brows: Brows = .none
    var ear = 0.0               // 1 = droop, -1 = swept back / perked
    var tail = 0.0              // -1...1 sway
    var acc = 0                 // accessory state: 0/1 normal, 2 = excited/flare, 3 = sleepy/dim
    var sweat = false
    var bubble = 0.0            // snot bubble radius
    var tear = false
    var blush = 1
    var lying = false           // flattened sleeping pose
    var wing = 0.0              // -1 down stroke ... 0 rest ... 1 raised
    var flying = false          // wings spread for flight
}

struct Anim { let name: String; let frames: [(Pose, Int)] }

func P(_ f: (inout Pose) -> Void) -> Pose { var p = Pose(); f(&p); return p }

let anims: [Anim] = {
    var a: [Anim] = []
    a.append(Anim(name: "idle", frames: [
        (P { _ in }, 520),
        (P { $0.sx = 1.06; $0.sy = 0.94; $0.acc = 1; $0.tail = 0.5; $0.wing = 0.2 }, 420),
        (P { $0.tail = 1 }, 520),
        (P { $0.eyes = .blink; $0.acc = 1; $0.tail = 0.5 }, 110),
    ]))
    a.append(Anim(name: "look", frames: [
        (P { $0.look = -1; $0.tilt = -1 }, 380),
        (P { $0.look = -1; $0.tilt = -1; $0.acc = 1; $0.mouth = .open }, 300),
        (P { $0.eyes = .blink }, 110),
        (P { $0.look = 1; $0.tilt = 1; $0.acc = 1 }, 380),
        (P { $0.look = 1; $0.tilt = 1; $0.mouth = .cat }, 300),
        (P { $0.acc = 1 }, 200),
    ]))
    a.append(Anim(name: "walk", frames: (0..<6).map { k -> (Pose, Int) in
        let s = sin(Double(k) * .pi / 3)
        return (P {
            $0.legs = .step(s); $0.arms = (.swing(s), .swing(-s)); $0.look = 1; $0.lean = 0.5
            $0.lift = abs(s) < 0.5 ? 1 : 0; $0.ear = 0.35 * abs(s); $0.tail = s; $0.acc = k % 2
            $0.sx = abs(s) < 0.5 ? 0.97 : 1.03; $0.sy = abs(s) < 0.5 ? 1.03 : 0.97
        }, 90)
    }))
    a.append(Anim(name: "crouch", frames: [
        (P { $0.sx = 1.2; $0.sy = 0.78; $0.eyes = .squint; $0.mouth = .cat; $0.brows = .determined; $0.ear = 0.4; $0.wing = -0.5 }, 120),
    ]))
    a.append(Anim(name: "jump", frames: [
        (P { $0.sx = 0.86; $0.sy = 1.16; $0.lift = 2; $0.arms = (.up, .up); $0.legs = .dangle(0); $0.look = 1; $0.mouth = .open; $0.ear = -1; $0.acc = 2; $0.wing = 1 }, 110),
        (P { $0.sx = 0.92; $0.sy = 1.1; $0.lift = 2; $0.arms = (.up, .up); $0.legs = .dangle(0.5); $0.look = 1; $0.mouth = .grin; $0.ear = -1; $0.acc = 2; $0.wing = -0.5 }, 110),
    ]))
    a.append(Anim(name: "fall", frames: [
        (P { $0.sy = 1.06; $0.sx = 0.95; $0.lift = 2; $0.arms = (.flail(1), .flail(-1)); $0.legs = .dangle(1); $0.eyes = .wide; $0.mouth = .yell; $0.brows = .worried; $0.sweat = true; $0.ear = -1; $0.wing = 1; $0.acc = 2 }, 80),
        (P { $0.sy = 1.06; $0.sx = 0.95; $0.lift = 2; $0.arms = (.flail(-1), .flail(1)); $0.legs = .dangle(-1); $0.eyes = .wide; $0.mouth = .yell; $0.brows = .worried; $0.sweat = true; $0.ear = -0.6; $0.wing = -1; $0.acc = 0 }, 80),
    ]))
    a.append(Anim(name: "land", frames: [
        (P { $0.sx = 1.3; $0.sy = 0.7; $0.eyes = .squint; $0.mouth = .open; $0.ear = 1; $0.arms = (.out, .out); $0.wing = -1 }, 80),
        (P { $0.sx = 0.92; $0.sy = 1.08; $0.lift = 1; $0.ear = -0.5; $0.wing = 0.5 }, 110),
    ]))
    a.append(Anim(name: "dizzy", frames: (0..<4).map { k -> (Pose, Int) in
        let s = [-1.0, 0, 1, 0][k]
        return (P { $0.eyes = .dizzy; $0.mouth = .wobble; $0.lean = s; $0.tilt = s; $0.arms = k % 2 == 0 ? (.out, .down) : (.down, .out); $0.ear = 1; $0.acc = 3; $0.wing = -0.6 }, 150)
    }))
    a.append(Anim(name: "yawn", frames: [
        (P { $0.eyes = .sleepy }, 160),
        (P { $0.sy = 1.06; $0.arms = (.up, .up); $0.eyes = .squint; $0.mouth = .open; $0.wing = 0.5 }, 180),
        (P { $0.sy = 1.13; $0.sx = 0.9; $0.arms = (.up, .up); $0.eyes = .squint; $0.mouth = .yawn; $0.tear = true; $0.ear = -1; $0.wing = 1 }, 220),
        (P { $0.sy = 1.15; $0.sx = 0.89; $0.arms = (.up, .up); $0.eyes = .squint; $0.mouth = .yawn; $0.tear = true; $0.ear = -1; $0.wing = 1 }, 620),
        (P { $0.sy = 0.94; $0.sx = 1.06; $0.eyes = .sleepy; $0.mouth = .cat; $0.ear = 0.6; $0.acc = 3; $0.wing = -0.6 }, 280),
        (P { $0.sy = 0.92; $0.sx = 1.08; $0.eyes = .blink; $0.ear = 0.8; $0.acc = 3; $0.wing = -1 }, 320),
    ]))
    a.append(Anim(name: "sleep", frames: [0.0, 1.0, 2.0, 1.0].enumerated().map { k, b -> (Pose, Int) in
        (P { $0.lying = true; $0.eyes = .sleep; $0.mouth = .none; $0.bubble = b + 1; $0.arms = (.tucked, .tucked); $0.legs = .tucked
            $0.ear = 1; $0.acc = 3; $0.sy = k == 2 ? 0.96 : 1.0; $0.wing = -1 }, 650)
    }))
    a.append(Anim(name: "wake", frames: [
        (P { $0.lift = 3; $0.sy = 1.15; $0.sx = 0.9; $0.eyes = .wide; $0.mouth = .open; $0.sweat = true; $0.arms = (.out, .out); $0.ear = -1; $0.acc = 2; $0.wing = 1 }, 170),
        (P { $0.lift = 1; $0.sy = 1.04; $0.eyes = .wide; $0.mouth = .smile; $0.ear = -0.5 }, 260),
        (P { $0.arms = (.rub, .rub); $0.eyes = .squint; $0.mouth = .cat }, 380),
        (P { $0.eyes = .blink }, 140),
    ]))
    a.append(Anim(name: "react", frames: [
        (P { $0.sx = 1.2; $0.sy = 0.8; $0.eyes = .happy; $0.mouth = .cat; $0.blush = 2; $0.ear = 0.5; $0.wing = -0.6 }, 80),
        (P { $0.sx = 0.86; $0.sy = 1.16; $0.lift = 3; $0.arms = (.up, .up); $0.eyes = .happy; $0.mouth = .grin; $0.blush = 2; $0.ear = -1; $0.acc = 2; $0.wing = 1 }, 100),
        (P { $0.sy = 1.08; $0.lift = 4; $0.arms = (.wave(1), .up); $0.eyes = .happy; $0.mouth = .grin; $0.blush = 2; $0.ear = -1; $0.acc = 2; $0.wing = 0 }, 130),
        (P { $0.lift = 2; $0.arms = (.wave(-1), .up); $0.eyes = .happy; $0.mouth = .grin; $0.blush = 2; $0.acc = 2; $0.wing = 1 }, 110),
        (P { $0.sx = 1.14; $0.sy = 0.88; $0.arms = (.out, .out); $0.eyes = .happy; $0.mouth = .cat; $0.blush = 2; $0.wing = -0.5 }, 90),
        (P { $0.eyes = .happy; $0.mouth = .smile; $0.blush = 2; $0.acc = 1 }, 280),
    ]))
    a.append(Anim(name: "pet", frames: (0..<4).map { k -> (Pose, Int) in
        let s = [-1.0, 0, 1, 0][k]
        return (P { $0.eyes = .happy; $0.mouth = .cat; $0.blush = 2; $0.tilt = s; $0.lean = s * 0.5; $0.ear = 0.5; $0.tail = s
            $0.sx = k % 2 == 0 ? 1.05 : 1.0; $0.sy = k % 2 == 0 ? 0.95 : 1.0; $0.acc = k % 2; $0.wing = k % 2 == 0 ? 0.4 : 0 }, 220)
    }))
    a.append(Anim(name: "drag", frames: (0..<4).map { k -> (Pose, Int) in
        let s = [1.0, 0, -1, 0][k]
        return (P { $0.lift = 3; $0.sy = 1.12; $0.sx = 0.9; $0.arms = (.up, .up); $0.legs = .dangle(s); $0.eyes = .wide; $0.mouth = .open
            $0.brows = .worried; $0.sweat = k < 2; $0.ear = -0.5; $0.tail = s; $0.lean = s * 0.5; $0.wing = k % 2 == 0 ? 1 : -0.5 }, 110)
    }))
    a.append(Anim(name: "alert", frames: [
        (P { $0.lift = 3; $0.sy = 1.14; $0.sx = 0.9; $0.eyes = .wide; $0.mouth = .open; $0.ear = -1; $0.arms = (.out, .out); $0.acc = 2; $0.wing = 1 }, 150),
        (P { $0.sx = 1.08; $0.sy = 0.92; $0.look = 1; $0.brows = .determined; $0.mouth = .cat }, 260),
    ]))
    // New in v3: flight, signature move, dance, greeting wave, playful run.
    a.append(Anim(name: "fly", frames: [1.0, 0.2, -1.0, 0.2].enumerated().map { k, w -> (Pose, Int) in
        (P { $0.flying = true; $0.wing = w; $0.lift = 3 + (k == 0 ? 1 : 0); $0.legs = .dangle(0.3); $0.arms = (.out, .out); $0.look = 1
            $0.mouth = k < 2 ? .cat : .smile; $0.tail = w * 0.5; $0.ear = -0.5; $0.acc = k % 2 }, 70)
    }))
    a.append(Anim(name: "special", frames: [
        (P { $0.sx = 1.15; $0.sy = 0.85; $0.eyes = .squint; $0.brows = .determined; $0.mouth = .cat; $0.arms = (.down, .down); $0.ear = 0.5; $0.wing = -0.6 }, 160),
        (P { $0.sx = 1.2; $0.sy = 0.8; $0.eyes = .squint; $0.brows = .determined; $0.mouth = .none; $0.ear = 0.7; $0.tail = -1; $0.wing = -1 }, 140),
        (P { $0.sx = 0.9; $0.sy = 1.12; $0.lift = 1; $0.look = 1; $0.eyes = .open; $0.mouth = .yell; $0.arms = (.out, .out); $0.ear = -1; $0.acc = 2; $0.tail = 1; $0.wing = 1; $0.flying = true }, 200),
        (P { $0.sx = 0.92; $0.sy = 1.1; $0.lift = 1; $0.look = 1; $0.eyes = .squint; $0.mouth = .yell; $0.arms = (.out, .out); $0.ear = -1; $0.acc = 2; $0.tail = 0.5; $0.wing = 0.6; $0.flying = true }, 260),
        (P { $0.sx = 1.05; $0.sy = 0.95; $0.eyes = .happy; $0.mouth = .grin; $0.blush = 2; $0.acc = 1; $0.wing = 0 }, 220),
        (P { $0.eyes = .happy; $0.mouth = .smile; $0.blush = 2 }, 240),
    ]))
    a.append(Anim(name: "dance", frames: (0..<6).map { k -> (Pose, Int) in
        let s = sin(Double(k) * .pi / 3)
        return (P { $0.lean = s * 1.5; $0.tilt = s * 1.5; $0.eyes = k == 3 ? .happy : .happy; $0.mouth = k % 3 == 0 ? .grin : .cat; $0.blush = 2
            $0.arms = k % 2 == 0 ? (.wave(1), .out) : (.out, .wave(-1)); $0.lift = k % 3 == 1 ? 2 : 0; $0.legs = .step(s)
            $0.sx = k % 3 == 2 ? 1.08 : 0.97; $0.sy = k % 3 == 2 ? 0.92 : 1.03; $0.tail = s; $0.ear = -0.3; $0.acc = k % 2 == 0 ? 2 : 1; $0.wing = s }, 140)
    }))
    a.append(Anim(name: "wave", frames: (0..<4).map { k -> (Pose, Int) in
        (P { $0.arms = (.down, .wave(k % 2 == 0 ? 1 : -1)); $0.eyes = .happy; $0.mouth = k < 2 ? .grin : .cat; $0.blush = 2; $0.look = 1
            $0.tilt = 0.5; $0.ear = -0.4; $0.acc = 1; $0.wing = k % 2 == 0 ? 0.5 : 0 }, 160)
    }))
    a.append(Anim(name: "run", frames: (0..<6).map { k -> (Pose, Int) in
        let s = sin(Double(k) * .pi / 3)
        return (P { $0.legs = .step(s * 1.4); $0.arms = (.flail(s), .flail(-s)); $0.look = 1; $0.lean = 1.2; $0.lift = abs(s) < 0.5 ? 2 : 0
            $0.eyes = .happy; $0.mouth = .grin; $0.blush = 2; $0.ear = -1; $0.tail = s; $0.acc = 2; $0.wing = s
            $0.sx = abs(s) < 0.5 ? 0.94 : 1.06; $0.sy = abs(s) < 0.5 ? 1.06 : 0.94 }, 70)
    }))
    return a
}()
