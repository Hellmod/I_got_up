import Foundation

// MARK: - AlarmSoundGenerator
//
// Generates a 29-second beep-beep alarm tone as a PCM WAV file and saves it to
// the app's Library/Sounds directory.  iOS plays files from that directory as
// UNNotificationSound — even when the app is completely killed — so this gives
// us a long ringing alarm sound without any background execution.
//
// Call ensureAlarmSound() once at app start; it's a no-op on subsequent launches.

enum AlarmSoundGenerator {
    static let soundName = "alarm_ringtone.wav"

    @discardableResult
    static func ensureAlarmSound() -> URL? {
        guard let dir = soundsDirectory() else { return nil }
        let url = dir.appendingPathComponent(soundName)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let data = generate(duration: 29.0)
        try? data.write(to: url, options: .atomic)
        print("✅ Alarm sound written to \(url.path)")
        return url
    }

    // MARK: - Private

    private static func soundsDirectory() -> URL? {
        guard let lib = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let dir = lib.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a WAV blob: two 880 Hz beeps per second, repeated for `duration` seconds.
    private static func generate(duration: Double) -> Data {
        let sampleRate = 44100
        let numSamples = Int(Double(sampleRate) * duration)
        let pcmSize   = numSamples * 2  // 16-bit mono

        var data = Data()
        data.reserveCapacity(44 + pcmSize)

        func le<T: FixedWidthInteger>(_ v: T) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }

        // RIFF / WAVE / fmt  / data  header
        data.append(contentsOf: "RIFF".utf8); le(UInt32(36 + pcmSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8); le(UInt32(16))
        le(UInt16(1))                       // PCM
        le(UInt16(1))                       // mono
        le(UInt32(sampleRate))
        le(UInt32(sampleRate * 2))          // byte rate
        le(UInt16(2))                       // block align
        le(UInt16(16))                      // bits/sample
        data.append(contentsOf: "data".utf8); le(UInt32(pcmSize))

        // Pattern: beep1 (0–0.18s) · gap · beep2 (0.25–0.43s) · silence → 1.0 s cycle
        let cycle = sampleRate
        let fadeLen = Int(0.01 * Double(sampleRate))  // 10 ms fade to prevent clicks

        for i in 0..<numSamples {
            let pos = i % cycle
            let t   = Double(pos) / Double(sampleRate)

            let inBeep1 = pos < Int(0.18 * Double(sampleRate))
            let beep2Lo = Int(0.25 * Double(sampleRate))
            let beep2Hi = Int(0.43 * Double(sampleRate))
            let inBeep2 = pos >= beep2Lo && pos < beep2Hi

            var sample: Double = 0
            if inBeep1 || inBeep2 {
                let offset = inBeep1 ? pos : (pos - beep2Lo)
                let len    = inBeep1 ? Int(0.18 * Double(sampleRate)) : (beep2Hi - beep2Lo)
                let fade   = Double(min(offset, len - 1 - offset, fadeLen)) / Double(fadeLen)
                let amp    = min(1.0, fade) * 0.85
                sample = sin(2.0 * .pi * 880.0 * t) * amp
            }

            le(Int16(max(-1.0, min(1.0, sample)) * Double(Int16.max)))
        }
        return data
    }
}
