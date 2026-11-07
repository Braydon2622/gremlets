import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turns a screen recording into a looping GIF (for a README or a post): frames sampled at `fps`, scaled to `width`.
enum GIFMaker {
    static func make(from movie: URL, fps: Double = 10, width: Int = 900, maxSeconds: Double = 45) -> URL? {
        let asset = AVURLAsset(url: movie)
        let duration = min(maxSeconds, CMTimeGetSeconds(asset.duration))
        guard duration > 0.5 else { return nil }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: width, height: width)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)
        let out = movie.deletingPathExtension().appendingPathExtension("gif")
        try? FileManager.default.removeItem(at: out)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, 0, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
        var t = 0.0
        var count = 0
        while t < duration {
            if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
                CGImageDestinationAddImage(dest, cg, frameProps)
                count += 1
            }
            t += 1.0 / fps
        }
        guard count > 0, CGImageDestinationFinalize(dest) else { return nil }
        return out
    }
}
