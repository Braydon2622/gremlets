// spritegen: generates the 50 built-in Gremlet sprite sheets.
//
// Output per species (in Species/<id>/):
//   sheet.png     horizontal strip of 32x32 frames (20 animations)
//   sheet.json    Aseprite "array" export format with frameTags
//   species.json  name, element, family, description, behavior tuning, flight and signature move
//   preview.png   upscaled contact sheet of key poses (docs only)
// Plus Species/lineup.png with all 50 idle frames.
//
// Usage: swift run spritegen [outputDir]
//        SPRITEGEN_DEBUG="kindlet:0,flurrie:19" SPRITEGEN_DEBUG_DIR=/tmp swift run spritegen   (big single frames)

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func writePNG(_ frames: [Canvas], to url: URL, scale k: Int = 1, background: UInt32? = nil, pad: Int = 0, perRow: Int? = nil) throws {
    let cols = min(perRow ?? frames.count, max(1, frames.count))
    let rows = (frames.count + cols - 1) / cols
    let cellW = W * k + pad, cellH = H * k + pad
    let width = cellW * cols, height = cellH * rows
    var buf = [UInt8](repeating: 0, count: width * height * 4)
    if let bg = background {
        let c = [UInt8(bg >> 16 & 0xFF), UInt8(bg >> 8 & 0xFF), UInt8(bg & 0xFF), 255]
        for i in stride(from: 0, to: buf.count, by: 4) { buf.replaceSubrange(i..<(i + 4), with: c) }
    }
    for (fi, f) in frames.enumerated() {
        let ox = (fi % cols) * cellW, oy = (fi / cols) * cellH
        for y in 0..<(H * k) { for x in 0..<(W * k) {
            guard let c = f.px[(y / k) * W + x / k] else { continue }
            let i = ((oy + y) * width + ox + x) * 4
            buf[i] = UInt8(c >> 16 & 0xFF); buf[i + 1] = UInt8(c >> 8 & 0xFF); buf[i + 2] = UInt8(c & 0xFF); buf[i + 3] = 255
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
    try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

let env = ProcessInfo.processInfo.environment
let flatPoses = anims.flatMap { $0.frames }

if let dbg = env["SPRITEGEN_DEBUG"], let dir = env["SPRITEGEN_DEBUG_DIR"] {
    // Debug mode: render chosen frames large and exit.
    var cells: [Canvas] = []
    for item in dbg.split(separator: ",") {
        let parts = item.split(separator: ":")
        let idx = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let ids = parts[0] == "*" ? roster.map(\.id) : [String(parts[0])]
        for id in ids {
            guard let sp = roster.first(where: { $0.id == id }) else { continue }
            cells.append(render(sp, flatPoses[min(idx, flatPoses.count - 1)].0))
        }
    }
    let k = Int(env["SPRITEGEN_DEBUG_SCALE"] ?? "") ?? 10
    try writePNG(cells, to: URL(fileURLWithPath: dir).appendingPathComponent("debug.png"), scale: k, background: 0xF3EFE6, pad: 8,
                 perRow: Int(env["SPRITEGEN_DEBUG_ROW"] ?? "") ?? 10)
    exit(0)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Species")
// Remove sheets for species that are no longer in the roster.
if let existing = try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil) {
    let keep = Set(roster.map(\.id))
    for d in existing where d.hasDirectoryPath && !keep.contains(d.lastPathComponent) { try? FileManager.default.removeItem(at: d) }
}
precondition(Set(roster.map(\.id)).count == roster.count, "duplicate species id")

var lineup: [Canvas] = []
for sp in roster {
    let dir = outDir.appendingPathComponent(sp.id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var frames: [Canvas] = [], frameJSON: [[String: Any]] = [], tags: [[String: Any]] = []
    for a in anims {
        let from = frames.count
        for (pose, ms) in a.frames {
            frameJSON.append(["filename": "\(sp.id) \(frames.count).aseprite",
                              "frame": ["x": frames.count * W, "y": 0, "w": W, "h": H], "duration": ms])
            frames.append(render(sp, pose))
        }
        tags.append(["name": a.name, "from": from, "to": frames.count - 1, "direction": "forward"])
    }
    try writePNG(frames, to: dir.appendingPathComponent("sheet.png"))
    try writeJSON(["frames": frameJSON,
                   "meta": ["app": "gremlets-spritegen", "image": "sheet.png", "format": "RGBA8888",
                            "size": ["w": frames.count * W, "h": H], "scale": "1", "frameTags": tags]],
                  to: dir.appendingPathComponent("sheet.json"))
    try writeJSON(["name": sp.name, "element": sp.element, "family": sp.family, "description": sp.blurb, "scale": 3,
                   "walkSpeed": sp.walkSpeed, "jumpPower": sp.jumpPower, "sleepiness": sp.sleepiness,
                   "flies": sp.flies, "floats": sp.floats, "special": sp.special],
                  to: dir.appendingPathComponent("species.json"))

    func at(_ name: String, _ i: Int) -> Canvas {
        let tag = tags.first { ($0["name"] as! String) == name }!
        return frames[(tag["from"] as! Int) + i]
    }
    let key = [at("idle", 0), at("walk", 1), at(sp.flies ? "fly" : "jump", 0), at("fall", 0), at("special", 2),
               at("dance", 1), at("yawn", 3), at("sleep", 2), at("react", 2), at("drag", 0)]
    try writePNG(key, to: dir.appendingPathComponent("preview.png"), scale: 5, background: 0xF3EFE6, pad: 6)
    lineup.append(frames[0])
}
try writePNG(lineup, to: outDir.appendingPathComponent("lineup.png"), scale: 5, background: 0xF3EFE6, pad: 8, perRow: 10)
print("Generated \(roster.count) species × \(flatPoses.count) frames")
