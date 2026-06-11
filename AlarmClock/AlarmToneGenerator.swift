import Foundation

// MARK: - AlarmToneGenerator
//
// Synthesizes the alarm tones offered in the sound picker and writes them to
// Library/Sounds, where AlarmKit (AlertConfiguration.AlertSound.named) and
// AVAudioPlayer can read them. Each file is 29 s — just under the system's
// 30-second limit for alert sounds. No-op when the files already exist.

enum AlarmToneGenerator {

    static func ensureSounds() {
        guard let dir = soundsDirectory() else { return }
        for sound in availableSounds {
            guard let fileName = sound.fileName else { continue }
            let url = dir.appendingPathComponent(fileName)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            let data = render(toneID: sound.id)
            try? data.write(to: url, options: .atomic)
            print("✅ Tone generated: \(fileName)")
        }
    }

    static func fileURL(for fileName: String) -> URL? {
        soundsDirectory()?.appendingPathComponent(fileName)
    }

    // MARK: - Directory

    private static func soundsDirectory() -> URL? {
        guard let lib = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let dir = lib.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Tone definitions
    // Each generator returns an amplitude in [-1, 1] for time t within its cycle.

    private static func render(toneID: String) -> Data {
        switch toneID {
        case "classic":
            // Two 880 Hz beeps per 1 s cycle — traditional alarm clock.
            return makeWAV(cycle: 1.0) { t in
                let beep = (t < 0.18) || (0.25..<0.43).contains(t)
                return beep ? sin(2 * .pi * 880 * t) * 0.85 : 0
            }
        case "digital":
            // Three rapid 1320 Hz chirps — digital watch style.
            return makeWAV(cycle: 0.9) { t in
                let inChirp = (t < 0.07) || (0.12..<0.19).contains(t) || (0.24..<0.31).contains(t)
                return inChirp ? sin(2 * .pi * 1320 * t) * 0.8 : 0
            }
        case "gentle":
            // Soft C5/E5 swell with slow attack — calm wake-up.
            return makeWAV(cycle: 2.0) { t in
                let envelope = min(t / 0.6, 1.0) * max(0, 1.0 - max(0, t - 1.4) / 0.6)
                let chord = sin(2 * .pi * 523.25 * t) * 0.5 + sin(2 * .pi * 659.25 * t) * 0.3
                return chord * envelope * 0.6
            }
        case "sonar":
            // 700 Hz ping with exponential decay — submarine sonar.
            return makeWAV(cycle: 1.4) { t in
                sin(2 * .pi * 700 * t) * exp(-t * 4.0) * 0.9
            }
        case "bell":
            // Struck bell: fundamental + harmonics, long decay.
            return makeWAV(cycle: 2.0) { t in
                let decay = exp(-t * 2.2)
                let tone = sin(2 * .pi * 660 * t) * 0.6
                         + sin(2 * .pi * 1320 * t) * 0.25
                         + sin(2 * .pi * 1980 * t) * 0.1
                return tone * decay
            }
        default:
            return makeWAV(cycle: 1.0) { t in
                t < 0.2 ? sin(2 * .pi * 880 * t) * 0.85 : 0
            }
        }
    }

    // MARK: - WAV synthesis

    /// Repeats `generator`'s cycle for 29 s and encodes mono 16-bit 44.1 kHz WAV.
    private static func makeWAV(cycle: Double, generator: (Double) -> Double) -> Data {
        let sampleRate = 44100
        let duration = 29.0
        let numSamples = Int(Double(sampleRate) * duration)
        let pcmSize = numSamples * 2

        var data = Data()
        data.reserveCapacity(44 + pcmSize)

        func le<T: FixedWidthInteger>(_ v: T) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: "RIFF".utf8); le(UInt32(36 + pcmSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8); le(UInt32(16))
        le(UInt16(1))                  // PCM
        le(UInt16(1))                  // mono
        le(UInt32(sampleRate))
        le(UInt32(sampleRate * 2))     // byte rate
        le(UInt16(2))                  // block align
        le(UInt16(16))                 // bits per sample
        data.append(contentsOf: "data".utf8); le(UInt32(pcmSize))

        let cycleSamples = Int(cycle * Double(sampleRate))
        for i in 0..<numSamples {
            let t = Double(i % cycleSamples) / Double(sampleRate)
            let v = max(-1.0, min(1.0, generator(t)))
            le(Int16(v * Double(Int16.max)))
        }
        return data
    }
}
