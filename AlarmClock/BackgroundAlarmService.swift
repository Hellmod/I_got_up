import AVFoundation
import Foundation

// MARK: - BackgroundAlarmService
//
// Keeps an AVAudioPlayer loop running while the app is minimised so iOS does not
// suspend the process (requires UIBackgroundModes: audio).  A periodic timer then
// checks whether any enabled alarm is due and plays a synthesised beep-beep tone
// without requiring the user to tap a notification.
//
// Limitation: works only when the app is minimised (background), not killed.
// iOS does not allow third-party apps to self-launch from a terminated state.

final class BackgroundAlarmService {
    static let shared = BackgroundAlarmService()

    private var keepAlivePlayer: AVAudioPlayer?
    private var alarmPlayer: AVAudioPlayer?
    private var checkTimer: Timer?
    private var lastFiredKey: [UUID: String] = [:]  // prevents double-fire within same minute
    private(set) var isMonitoring = false

    private init() {}

    // MARK: - Public API

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("❌ BackgroundAlarmService session: \(error)")
            isMonitoring = false
            return
        }

        // Near-silent loop — keeps the audio session alive so the timer keeps firing.
        let silentData = makeWAV(duration: 1.0) { _ in 0 }
        keepAlivePlayer = try? AVAudioPlayer(data: silentData)
        keepAlivePlayer?.volume = 0.0
        keepAlivePlayer?.numberOfLoops = -1
        keepAlivePlayer?.prepareToPlay()
        keepAlivePlayer?.play()

        checkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkAlarms()
        }
        checkAlarms()
    }

    /// Stop alarm sound only — keep-alive stays running until stopMonitoring().
    /// Called by AlarmActiveView when it takes over playback.
    func stopAlarmSound() {
        alarmPlayer?.stop()
        alarmPlayer = nil
    }

    /// Stop everything — called when app returns to foreground.
    func stopMonitoring() {
        isMonitoring = false
        checkTimer?.invalidate()
        checkTimer = nil
        stopAlarmSound()
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func checkAlarms() {
        let alarms = AlarmStore().alarms.filter { $0.isEnabled }
        guard !alarms.isEmpty else { return }

        let now   = Date()
        let cal   = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .weekday], from: now)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let minuteKey = formatter.string(from: now)

        for alarm in alarms {
            guard alarm.hour == comps.hour, alarm.minute == comps.minute else { continue }
            guard lastFiredKey[alarm.id] != minuteKey else { continue }

            let shouldFire: Bool
            switch alarm.repeatSchedule {
            case .once:
                shouldFire = true
            case .weekdays(let days):
                shouldFire = days.contains { $0.calendarWeekday == comps.weekday }
            }
            guard shouldFire else { continue }

            lastFiredKey[alarm.id] = minuteKey
            fireAlarm(alarm)
        }
    }

    private func fireAlarm(_ alarm: Alarm) {
        // Beep-beep pattern: two 880 Hz pulses + silence, 0.8 s total, looped.
        let beepData = makeWAV(duration: 0.8) { t in
            let inBeep = (t < 0.15) || (t >= 0.20 && t < 0.35)
            return inBeep ? sin(2.0 * .pi * 880.0 * t) * 0.85 : 0
        }

        alarmPlayer = try? AVAudioPlayer(data: beepData)
        alarmPlayer?.volume = 1.0
        alarmPlayer?.numberOfLoops = -1
        alarmPlayer?.prepareToPlay()
        alarmPlayer?.play()

        DispatchQueue.main.async {
            NotificationManager.shared.firingAlarm = alarm
        }
    }

    // MARK: - WAV synthesis

    /// Generates a mono 16-bit 44.1 kHz WAV blob from a sample generator.
    private func makeWAV(duration: Double, generator: (Double) -> Double) -> Data {
        let sampleRate = 44100
        let numSamples = Int(Double(sampleRate) * duration)
        let pcmSize = numSamples * 2   // 16-bit → 2 bytes/sample

        var data = Data()
        data.reserveCapacity(44 + pcmSize)

        func le<T: FixedWidthInteger>(_ v: T) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }

        // RIFF / WAVE / fmt  / data  chunks
        data.append(contentsOf: "RIFF".utf8); le(UInt32(36 + pcmSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8); le(UInt32(16))
        le(UInt16(1))                              // PCM
        le(UInt16(1))                              // mono
        le(UInt32(sampleRate))
        le(UInt32(sampleRate * 2))                 // byte rate
        le(UInt16(2))                              // block align
        le(UInt16(16))                             // bits/sample
        data.append(contentsOf: "data".utf8); le(UInt32(pcmSize))

        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let v = max(-1.0, min(1.0, generator(t)))
            le(Int16(v * Double(Int16.max)))
        }
        return data
    }
}
