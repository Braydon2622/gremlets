import AVFoundation
import AppKit
import GremletsCore

/// A postcard of the village is saved once a day (the first time the Gremlets are out), to ~/Pictures/Gremlets/Daily.
/// `gremlet timelapse` stitches those into a short video: your village growing, one day per half second.
enum TimeLapse {
    static var dailyFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Gremlets/Daily", isDirectory: true)
    }

    /// Saves today's postcard if there isn't one yet. Returns true when it wrote one.
    @discardableResult
    static func saveToday(world: World, species: [String: LoadedSpecies]) -> Bool {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let url = dailyFolder.appendingPathComponent("\(f.string(from: Date())).png")
        guard !FileManager.default.fileExists(atPath: url.path), let (image, _) = VillageSnapshot.render(world: world, species: species) else { return false }
        try? FileManager.default.createDirectory(at: dailyFolder, withIntermediateDirectories: true)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    /// Builds the video from every daily postcard, oldest first. Returns the file, or nil if there's nothing to show.
    static func build(secondsPerDay: Double = 0.5) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dailyFolder, includingPropertiesForKeys: nil) else { return nil }
        let days = files.filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !days.isEmpty, let first = NSImage(contentsOf: days[0])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = first.width & ~1, h = first.height & ~1
        let out = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Gremlets", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH.mm"
        let url = out.appendingPathComponent("Village time-lapse \(df.string(from: Date())).mp4")
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 30
        let framesPerDay = max(1, Int(secondsPerDay * Double(fps)))
        var frame: Int64 = 0
        // Each day holds for a moment; the last one lingers.
        for (i, day) in days.enumerated() {
            guard let img = NSImage(contentsOf: day)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let pool = adaptor.pixelBufferPool else { continue }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let buffer = pb else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.interpolationQuality = .none
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                // The date, small, in the corner.
                let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
                NSAttributedString(string: day.deletingPathExtension().lastPathComponent, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
                    .draw(at: CGPoint(x: 24, y: 20))
                NSGraphicsContext.restoreGraphicsState()
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let hold = i == days.count - 1 ? framesPerDay * 4 : framesPerDay
            for _ in 0..<hold {
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
                adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: fps))
                frame += 1
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        return writer.status == .completed ? url : nil
    }
}
