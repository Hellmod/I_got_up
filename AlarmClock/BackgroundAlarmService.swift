import AVFoundation
import Foundation

// MARK: - BackgroundAlarmService
//
// When the app is minimised, this service keeps an AVAudioPlayer looping so iOS
// does not suspend the process.  A timer then detects the alarm time and sets
// NotificationManager.shared.firingAlarm so that AlarmActiveView appears as soon
// as the user brings the app to the foreground.
//
// The actual alarm *sound* is delivered by the UNNotification itself (custom
// 29-second WAV), so this service does not need to play any alarm tone.

final class BackgroundAlarmService {
    static let shared = BackgroundAlarmService()

    private var keepAlivePlayer: AVAudioPlayer?
    private var checkTimer: Timer?
    private var lastFiredKey: [UUID: String] = [:]
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
            print("❌ BackgroundAlarmService: \(error)")
            isMonitoring = false
            return
        }

        // Play a barely-audible tone to satisfy iOS background-audio keep-alive.
        let data = makeWAV(duration: 1.0) { t in sin(2.0 * .pi * 18.0 * t) * 0.001 }
        keepAlivePlayer = try? AVAudioPlayer(data: data)
        keepAlivePlayer?.volume = 0.01
        keepAlivePlayer?.numberOfLoops = -1
        keepAlivePlayer?.prepareToPlay()
        keepAlivePlayer?.play()

        checkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkAlarms()
        }
        checkAlarms()
    }

    func stopMonitoring() {
        isMonitoring = false
        checkTimer?.invalidate()
        checkTimer = nil
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

            let fires: Bool
            switch alarm.repeatSchedule {
            case .once: fires = true
            case .weekdays(let days): fires = days.contains { $0.calendarWeekday == comps.weekday }
            }
            guard fires else { continue }

            lastFiredKey[alarm.id] = minuteKey

            // Show full-screen CallKit "incoming call" screen (bypasses silent mode,
            // no notification banner needed). Also set firingAlarm so AlarmActiveView
            // appears immediately if user opens app via app-switcher instead of Accept.
            AlarmCallManager.shared.reportIncomingAlarm(alarm)
            DispatchQueue.main.async {
                NotificationManager.shared.firingAlarm = alarm
            }
        }
    }

    // MARK: - WAV synthesis

    private func makeWAV(duration: Double, generator: (Double) -> Double) -> Data {
        let sampleRate = 44100
        let numSamples = Int(Double(sampleRate) * duration)
        let pcmSize    = numSamples * 2

        var data = Data()
        data.reserveCapacity(44 + pcmSize)

        func le<T: FixedWidthInteger>(_ v: T) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: "RIFF".utf8); le(UInt32(36 + pcmSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8); le(UInt32(16))
        le(UInt16(1)); le(UInt16(1))
        le(UInt32(sampleRate)); le(UInt32(sampleRate * 2))
        le(UInt16(2)); le(UInt16(16))
        data.append(contentsOf: "data".utf8); le(UInt32(pcmSize))

        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let v = max(-1.0, min(1.0, generator(t)))
            le(Int16(v * Double(Int16.max)))
        }
        return data
    }
}
