// spritegen: generates the placeholder Gremlet sprite sheets.
//
// Output per species (in Species/<id>/):
//   sheet.png    horizontal strip of 24x24 frames
//   sheet.json   Aseprite "array" export format with frameTags (idle, walk, jump, fall, land, sleep, react, drag)
//   species.json display name, element, scale and movement tuning
//
// The app reads exactly the same format Aseprite exports, so hand-drawn art can replace these files 1:1.
//
// Usage: swift run spritegen [outputDir]   (default: ./Species)

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S = 24  // frame size in pixels
let CX = 12 // body is centred between columns 11 and 12

// MARK: - Species definitions

enum BodyShape { case dome, pebble, drop }
enum Eyes { case open, closed, happy, surprised }

struct SpeciesDef {
    let id: String
    let name: String
    let element: String
    let shape: BodyShape
    let baseW: Int
    let baseH: Int
    let palette: [Character: UInt32]
    /// Accessory frames drawn on top of the head; the last row sits on the body's top row.
    let accessory: [[String]]
    let accessoryOffsetX: Int
    let mossCap: Bool
    let tuning: [String: Any]
}

let kindlet = SpeciesDef(
    id: "kindlet", name: "Kindlet", element: "ember", shape: .dome, baseW: 14, baseH: 11,
    palette: [
        "o": 0x3B1A1F, "b": 0xF2784B, "s": 0xC9483A, "h": 0xFFC59E, "e": 0x2A1414, "w": 0xFFFFFF,
        "k": 0xFF9EAE, "m": 0x7A2230, "f": 0x8F2F2F, "A": 0xFF5A2A, "a": 0xFFB02E, "Y": 0xFFF27A,
    ],
    accessory: [
        ["..A..",
         ".AaA.",
         ".AaA.",
         "AaYaA"],
        ["...A.",
         "..AA.",
         ".AaA.",
         "AaYaA"],
    ],
    accessoryOffsetX: -2, mossCap: false,
    tuning: ["walkSpeed": 70, "jumpPower": 1.0, "sleepiness": 0.8]
)

let mossling = SpeciesDef(
    id: "mossling", name: "Mossling", element: "moss", shape: .pebble, baseW: 16, baseH: 10,
    palette: [
        "o": 0x22302A, "b": 0xA7B5A9, "s": 0x7D8C82, "h": 0xDFE8DE, "e": 0x1D2421, "w": 0xFFFFFF,
        "k": 0xF0A3B4, "m": 0x4A2A33, "f": 0x4F5C55, "M": 0x6BBF59, "N": 0x3F8F46,
        "L": 0x5CCF54, "l": 0x2F8F3A, "t": 0x3F8F46,
    ],
    accessory: [
        ["LL.LL",
         "lLtLl",
         "..t..",
         "..t.."],
        [".LL.LL",
         ".lLtLl",
         "...t..",
         "..t..."],
    ],
    accessoryOffsetX: -2, mossCap: true,
    tuning: ["walkSpeed": 45, "jumpPower": 0.8, "sleepiness": 1.4]
)

let dropple = SpeciesDef(
    id: "dropple", name: "Dropple", element: "tide", shape: .drop, baseW: 13, baseH: 12,
    palette: [
        "o": 0x1C2B55, "b": 0x6EC3FF, "s": 0x3A86D6, "h": 0xE4F6FF, "e": 0x13204A, "w": 0xFFFFFF,
        "k": 0xFF9ECB, "m": 0x2A3570, "f": 0x2F5FA8, "B": 0xBDE8FF,
    ],
    accessory: [
        ["....B",
         "...B.",
         ".....",
         "....."],
        ["...B.",
         "....B",
         ".....",
         "....."],
    ],
    accessoryOffsetX: 1, mossCap: false,
    tuning: ["walkSpeed": 85, "jumpPower": 1.25, "sleepiness": 0.6]
)

// MARK: - Poses

struct Pose {
    var dw = 0, dh = 0          // squash/stretch relative to base size
    var lift = 0                // body raised off the ground (airborne)
    var eyes: Eyes = .open
    var lookAhead = 0           // eyes shifted toward facing direction
    var feet: (Int, Int) = (0, 0) // stride offsets for left/right foot
    var bob = 0                 // body bob (px up)
    var acc = 0                 // accessory frame
    var mouthOpen = false
}

struct Anim { let name: String; let poses: [Pose]; let ms: Int }

let anims: [Anim] = [
    Anim(name: "idle", poses: [Pose(acc: 0), Pose(dw: 1, dh: -1, acc: 1)], ms: 420),
    Anim(name: "walk", poses: [
        Pose(lookAhead: 1, feet: (-1, 1), bob: 0, acc: 0),
        Pose(lookAhead: 1, feet: (0, 0), bob: 1, acc: 1),
        Pose(lookAhead: 1, feet: (1, -1), bob: 0, acc: 0),
        Pose(lookAhead: 1, feet: (0, 0), bob: 1, acc: 1),
    ], ms: 120),
    Anim(name: "jump", poses: [Pose(dw: -2, dh: 2, lift: 2, lookAhead: 1, acc: 1)], ms: 100),
    Anim(name: "fall", poses: [Pose(dw: 0, dh: 0, lift: 2, eyes: .surprised, acc: 0, mouthOpen: true)], ms: 100),
    Anim(name: "land", poses: [Pose(dw: 3, dh: -3, acc: 0)], ms: 120),
    Anim(name: "sleep", poses: [Pose(dw: 2, dh: -2, eyes: .closed, acc: 0), Pose(dw: 2, dh: -3, eyes: .closed, acc: 0)], ms: 800),
    Anim(name: "react", poses: [Pose(dw: 2, dh: -2, eyes: .happy, acc: 1, mouthOpen: true), Pose(dw: -1, dh: 1, lift: 1, eyes: .happy, acc: 0, mouthOpen: true)], ms: 160),
    Anim(name: "drag", poses: [Pose(dw: -2, dh: 2, lift: 2, eyes: .surprised, acc: 0, mouthOpen: true), Pose(dw: -2, dh: 2, lift: 2, eyes: .surprised, acc: 1, mouthOpen: true)], ms: 200),
]

// MARK: - Rasterizer (character grid -> palette)

typealias Grid = [[Character]]

func blank() -> Grid { Array(repeating: Array(repeating: ".", count: S), count: S) }

func set(_ g: inout Grid, _ x: Int, _ y: Int, _ c: Character) {
    guard x >= 0, x < S, y >= 0, y < S else { return }
    g[y][x] = c
}

func draw(_ sp: SpeciesDef, _ p: Pose) -> Grid {
    var g = blank()
    let w = sp.baseW + p.dw
    let h = sp.baseH + p.dh
    let bottom = S - 3 - p.lift - p.bob   // body bottom row; feet occupy the rows below it
    let top = bottom - h + 1

    // Feet: 2x2 dark nubs reaching from under the body to the ground (or dangling when lifted).
    let footRows = p.lift > 0 ? [bottom + 1, bottom + 2] : Array((bottom + 1)...(S - 1))
    for (fx, off) in [(CX - 5, p.feet.0), (CX + 3, p.feet.1)] {
        for y in footRows { set(&g, fx + off, y, "f"); set(&g, fx + off + 1, y, "f") }
    }

    // Body silhouette.
    var rowSpan: [Int: (Int, Int)] = [:]
    for r in 0..<h {
        let t = (Double(r) + 0.5) / Double(h)
        var f: Double
        switch sp.shape {
        case .dome:
            f = t < 0.55 ? sqrt(max(0, 1 - pow((0.55 - t) / 0.55, 2))) : 1
        case .pebble:
            f = t < 0.4 ? sqrt(max(0, 1 - pow((0.4 - t) / 0.4, 2))) * 0.85 + 0.15 : 1
        case .drop:
            f = t < 0.6 ? max(0.12, pow(t / 0.6, 0.8)) : 1
        }
        var hw = Int((Double(w) / 2 * f).rounded())
        if r == h - 1 { hw -= 1 } // rounded bottom corners
        hw = max(1, hw)
        let l = CX - hw, rr = CX + hw - 1
        rowSpan[top + r] = (l, rr)
        for x in l...rr { set(&g, x, top + r, "b") }
    }

    // Outline: body pixels touching empty space.
    var outlined = g
    for y in 0..<S { for x in 0..<S where g[y][x] == "b" {
        let n = [(x-1,y),(x+1,y),(x,y-1),(x,y+1)].contains { (nx, ny) in
            nx < 0 || ny < 0 || nx >= S || ny >= S || (g[ny][nx] != "b")
        }
        if n { outlined[y][x] = "o" }
    }}
    g = outlined

    // Shading: lower third and right rim.
    for y in top...bottom {
        guard let (l, r) = rowSpan[y] else { continue }
        for x in l...r where g[y][x] == "b" {
            if Double(y - top) >= Double(h) * 0.72 { g[y][x] = "s" }
            if x == r - 1 && y > top + 1 { g[y][x] = "s" }
        }
        _ = l
    }

    // Moss cap for Mossling.
    if sp.mossCap {
        for y in top...(top + 2) {
            guard let (l, r) = rowSpan[y] else { continue }
            for x in l...r where g[y][x] == "b" || g[y][x] == "s" {
                g[y][x] = ((x + y) % 3 == 0) ? "N" : "M"
            }
        }
        // drippy moss edge
        if let (l, r) = rowSpan[top + 3] {
            for x in stride(from: l + 2, through: r - 2, by: 3) where g[top + 3][x] == "b" { g[top + 3][x] = "M" }
        }
    }

    // Highlight (top-left).
    let hy = top + 2
    if !sp.mossCap, let (l, _) = rowSpan[hy] {
        for x in (l + 2)...(l + (sp.shape == .drop ? 3 : 4)) where g[hy][x] == "b" { g[hy][x] = "h" }
    }
    if sp.shape == .drop, let (l, _) = rowSpan[hy + 1], g[hy + 1][l + 2] == "b" { g[hy + 1][l + 2] = "h" }

    // Face.
    let ey = top + Int(Double(h) * (sp.shape == .drop ? 0.52 : 0.45))
    let lx = CX - 4 + p.lookAhead, rx = CX + 2 + p.lookAhead
    switch p.eyes {
    case .open:
        for ex in [lx, rx] {
            set(&g, ex, ey, "w"); set(&g, ex + 1, ey, "e")
            set(&g, ex, ey + 1, "e"); set(&g, ex + 1, ey + 1, "e")
        }
    case .surprised:
        for ex in [lx, rx] {
            set(&g, ex, ey, "e"); set(&g, ex + 1, ey, "e")
            set(&g, ex, ey + 1, "e"); set(&g, ex + 1, ey + 1, "w")
        }
    case .closed:
        for ex in [lx, rx] { set(&g, ex, ey + 1, "e"); set(&g, ex + 1, ey + 1, "e") }
    case .happy:
        for ex in [lx - 1, rx] {
            set(&g, ex, ey + 1, "e"); set(&g, ex + 1, ey, "e"); set(&g, ex + 2, ey + 1, "e")
        }
    }
    // Blush + mouth.
    set(&g, lx - 2, ey + 2, "k"); set(&g, rx + 3, ey + 2, "k")
    let mx = CX - 1 + p.lookAhead
    if p.mouthOpen {
        set(&g, mx, ey + 2, "m"); set(&g, mx + 1, ey + 2, "m"); set(&g, mx, ey + 3, "m"); set(&g, mx + 1, ey + 3, "m")
    } else if p.eyes != .closed {
        set(&g, mx, ey + 2, "m"); set(&g, mx + 1, ey + 2, "m")
    }

    // Accessory on top of the head.
    let accRows = sp.accessory[p.acc % sp.accessory.count]
    for (i, row) in accRows.enumerated() {
        let y = top - (accRows.count - 1) + i
        for (j, c) in row.enumerated() where c != "." {
            set(&g, CX + sp.accessoryOffsetX + j, y, c)
        }
    }
    return g
}

// MARK: - Output

func rgba(_ hex: UInt32) -> [UInt8] {
    [UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF), 255]
}

func writePNG(frames: [Grid], palette: [Character: UInt32], to url: URL, scale k: Int = 1, background: UInt32? = nil) throws {
    let cell = S * k
    let width = cell * frames.count, height = cell
    var buf = [UInt8](repeating: 0, count: width * height * 4)
    if let bg = background { for i in stride(from: 0, to: buf.count, by: 4) { buf.replaceSubrange(i..<(i + 4), with: rgba(bg)) } }
    for (fi, g) in frames.enumerated() {
        for y in 0..<height { for x in 0..<cell {
            guard let hex = palette[g[y / k][x / k]] else { continue }
            let i = (y * width + fi * cell + x) * 4
            buf.replaceSubrange(i..<(i + 4), with: rgba(hex))
        }}
    }
    let provider = CGDataProvider(data: Data(buf) as CFData)!
    let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "spritegen", code: 1) }
}

func writeJSON(_ obj: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Species")

for sp in [kindlet, mossling, dropple] {
    let dir = outDir.appendingPathComponent(sp.id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var frames: [Grid] = []
    var frameJSON: [[String: Any]] = []
    var tags: [[String: Any]] = []
    for a in anims {
        let from = frames.count
        for p in a.poses {
            frameJSON.append([
                "filename": "\(sp.id) \(frames.count).aseprite",
                "frame": ["x": frames.count * S, "y": 0, "w": S, "h": S],
                "duration": a.ms,
            ])
            frames.append(draw(sp, p))
        }
        tags.append(["name": a.name, "from": from, "to": frames.count - 1, "direction": "forward"])
    }
    try writePNG(frames: frames, palette: sp.palette, to: dir.appendingPathComponent("sheet.png"))
    // Upscaled contact sheet for docs/review (not loaded by the app).
    try writePNG(frames: frames, palette: sp.palette, to: dir.appendingPathComponent("preview.png"), scale: 6, background: 0xF3EFE6)
    try writeJSON([
        "frames": frameJSON,
        "meta": ["app": "gremlets-spritegen", "image": "sheet.png", "format": "RGBA8888",
                 "size": ["w": frames.count * S, "h": S], "scale": "1", "frameTags": tags],
    ], to: dir.appendingPathComponent("sheet.json"))
    var info: [String: Any] = ["name": sp.name, "element": sp.element, "scale": 3]
    info.merge(sp.tuning) { $1 }
    try writeJSON(info, to: dir.appendingPathComponent("species.json"))

    // ASCII preview of the idle frame for quick review in the terminal.
    print("\(sp.name) (\(sp.element)) - \(frames.count) frames")
    for row in frames[0] { print("  " + String(row.map { $0 == "." ? " " : $0 })) }
}
