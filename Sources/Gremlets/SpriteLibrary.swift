import AppKit
import GremletsCore

/// A species with its frame bitmaps (platform side) plus engine metadata.
struct LoadedSpecies {
    let info: SpeciesInfo
    let frames: [CGImage]
}

/// Loads sprite sheets in Aseprite JSON export format (array or hash `frames`, with `meta.frameTags`).
///
/// Search order (later folders override earlier ones by species id):
///   1. built-in sheets (app bundle `Resources/Species`, or the repo's `Species/` folder in dev builds)
///   2. `~/Library/Application Support/Gremlets/Species/<id>/` for drop-in art
enum SpriteLibrary {
    static var userSpeciesFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gremlets/Species", isDirectory: true)
    }

    static var builtInFolder: URL? {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Species"),
           FileManager.default.fileExists(atPath: res.path) { return res }
        // Dev builds (`swift run`): <repo>/Sources/Gremlets/SpriteLibrary.swift -> <repo>/Species
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dev = repo.appendingPathComponent("Species")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static func loadAll() -> [String: LoadedSpecies] {
        var out: [String: LoadedSpecies] = [:]
        for root in [builtInFolder, userSpeciesFolder].compactMap({ $0 }) {
            guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                do {
                    if let s = try load(dir) { out[s.info.id] = s }
                } catch {
                    NSLog("Gremlets: skipping species at \(dir.path): \(error)")
                }
            }
        }
        return out
    }

    struct LoadError: Error, CustomStringConvertible { let description: String }

    static func load(_ dir: URL) throws -> LoadedSpecies? {
        let jsonURL = dir.appendingPathComponent("sheet.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return nil }
        guard let sheet = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any] else {
            throw LoadError(description: "sheet.json is not an object")
        }
        let meta = sheet["meta"] as? [String: Any] ?? [:]
        let imageName = meta["image"] as? String ?? "sheet.png"
        let imageURL = dir.appendingPathComponent((imageName as NSString).lastPathComponent)
        guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let sheetImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw LoadError(description: "can't read \(imageURL.lastPathComponent)")
        }

        // Aseprite exports `frames` either as an array or as a hash keyed by "name N.aseprite".
        var rawFrames: [[String: Any]] = []
        if let arr = sheet["frames"] as? [[String: Any]] {
            rawFrames = arr
        } else if let hash = sheet["frames"] as? [String: [String: Any]] {
            func num(_ k: String) -> Int { Int(k.split(whereSeparator: { !$0.isNumber }).last ?? "0") ?? 0 }
            rawFrames = hash.keys.sorted { num($0) < num($1) }.map { hash[$0]! }
        }
        guard !rawFrames.isEmpty else { throw LoadError(description: "no frames") }

        var images: [CGImage] = []
        var masks: [[Bool]] = []
        var durations: [Double] = []
        var fw = 0, fh = 0
        for f in rawFrames {
            guard let r = f["frame"] as? [String: Any],
                  let x = r["x"] as? Int, let y = r["y"] as? Int, let w = r["w"] as? Int, let h = r["h"] as? Int,
                  let img = sheetImage.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
                throw LoadError(description: "bad frame rect")
            }
            fw = max(fw, w); fh = max(fh, h)
            images.append(img)
            masks.append(alphaMask(img))
            durations.append(Double(f["duration"] as? Int ?? 100) / 1000)
        }

        var animations: [String: SpeciesInfo.Animation] = [:]
        for tag in meta["frameTags"] as? [[String: Any]] ?? [] {
            guard let name = tag["name"] as? String, let from = tag["from"] as? Int, let to = tag["to"] as? Int,
                  from <= to, to < images.count else { continue }
            var idx = Array(from...to)
            switch tag["direction"] as? String {
            case "reverse": idx.reverse()
            case "pingpong": idx += idx.dropFirst().dropLast().reversed()
            default: break
            }
            animations[name.lowercased()] = .init(frames: idx, durations: idx.map { durations[$0] })
        }
        if animations["idle"] == nil {
            animations["idle"] = .init(frames: Array(images.indices), durations: durations)
        }

        var extra: [String: Any] = [:]
        if let d = try? Data(contentsOf: dir.appendingPathComponent("species.json")),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { extra = obj }
        let id = dir.lastPathComponent
        let info = SpeciesInfo(
            id: id,
            name: extra["name"] as? String ?? id.capitalized,
            element: extra["element"] as? String ?? "",
            frameWidth: fw, frameHeight: fh,
            scale: (extra["scale"] as? Double) ?? 3,
            animations: animations, masks: masks,
            walkSpeed: extra["walkSpeed"] as? Double ?? 70,
            jumpPower: extra["jumpPower"] as? Double ?? 1,
            sleepiness: extra["sleepiness"] as? Double ?? 1,
            blurb: extra["description"] as? String ?? "")
        return LoadedSpecies(info: info, frames: images)
    }

    static func alphaMask(_ img: CGImage) -> [Bool] {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Bitmap context memory is top row first, matching the mask's row-major-from-top layout.
        return (0..<(w * h)).map { buf[$0 * 4 + 3] > 24 }
    }
}
