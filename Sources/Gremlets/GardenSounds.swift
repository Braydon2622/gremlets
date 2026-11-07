import AVFoundation

/// Optional, off by default: tiny synthesized sounds for the garden. A soft chime when a flower opens on a tree, two
/// notes for a golden fruit, a short rising figure for a milestone, a wooden knock when a house joins the village, a
/// sparkle for a gem. No audio files: sine tones with a struck-chime envelope, mixed quietly. Never during a focus
/// session or while the Gremlets are hidden.
final class GardenSounds {
    enum Cue { case sprout, bloom, fruit, milestone, house, gem }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var started = false
    private var lastPlayed: [String: CFTimeInterval] = [:]

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "sounds.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "sounds.enabled"); if !newValue { stop() } }
    }

    private func start() -> Bool {
        if started { return true }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.22
        do { try engine.start(); player.play(); started = true; return true } catch { return false }
    }

    func stop() {
        guard started else { return }
        player.stop(); engine.stop(); engine.detach(player)
        started = false
    }

    func play(_ cue: Cue) {
        guard enabled else { return }
        // Same cue at most twice a second, so a burst of edits doesn't turn into a wind-chime storm.
        let now = CACurrentMediaTime()
        if now - (lastPlayed["\(cue)"] ?? 0) < 0.5 { return }
        lastPlayed["\(cue)"] = now
        guard start() else { return }
        let notes: [(freq: Double, start: Double, dur: Double, gain: Double)]
        switch cue {
        case .sprout: notes = [(440, 0, 0.3, 0.35), (554.4, 0.1, 0.45, 0.3)]
        case .bloom: notes = [(880, 0, 0.5, 0.45), (1318.5, 0.08, 0.6, 0.3)]
        case .fruit: notes = [(659.3, 0, 0.35, 0.4), (987.8, 0.18, 0.6, 0.4)]
        case .milestone: notes = [(523.3, 0, 0.3, 0.35), (659.3, 0.12, 0.3, 0.35), (784, 0.24, 0.3, 0.35), (1046.5, 0.36, 0.9, 0.4)]
        case .house: notes = [(196, 0, 0.12, 0.55), (147, 0.14, 0.2, 0.45)]
        case .gem: notes = [(1760, 0, 0.25, 0.25), (2093, 0.06, 0.35, 0.25), (2637, 0.12, 0.5, 0.2)]
        }
        guard let buffer = render(notes) else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func render(_ notes: [(freq: Double, start: Double, dur: Double, gain: Double)]) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let total = notes.map { $0.start + $0.dur }.max() ?? 0.5
        let frames = AVAudioFrameCount(total * sr) + 1
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }
        for n in notes {
            let s0 = Int(n.start * sr), count = Int(n.dur * sr)
            for i in 0..<count where s0 + i < Int(frames) {
                let t = Double(i) / sr
                // A struck chime: quick attack, exponential decay, a touch of the second harmonic.
                let env = min(1, t / 0.005) * exp(-t * (5 / n.dur))
                let v = sin(2 * .pi * n.freq * t) + 0.25 * sin(2 * .pi * n.freq * 2 * t)
                data[s0 + i] += Float(v * env * n.gain)
            }
        }
        return buf
    }
}
