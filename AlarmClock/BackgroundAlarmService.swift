import AVFoundation
import Foundation

// MARK: - BackgroundAlarmService
//
// Keeps a silent AVAudioEngine running when the app is in the background so that
// the OS doesn't suspend it. A periodic timer then detects when an alarm is due
// and plays the alarm tone directly — no user interaction required.
//
// Limitation: this only works when the app was previously opened and is minimised
// (not killed). A killed app cannot be woken up by third-party code on iOS.

final class BackgroundAlarmService {
    static let shared = BackgroundAlarmService()

    private let engine = AVAudioEngine()
    private let silentNode = AVAudioPlayerNode()
    private let alarmNode  = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    private var checkTimer: Timer?
    private var lastFiredKey: [UUID: String] = [:]   // prevents double-fire within same minute
    private(set) var isMonitoring = false
    private var alarmSoundActive = false

    private init() {
        engine.attach(silentNode)
        engine.attach(alarmNode)
        engine.connect(silentNode, to: engine.mainMixerNode, format: format)
        engine.connect(alarmNode,  to: engine.mainMixerNode, format: format)
    }

    // MARK: - Public API

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)

            silentNode.scheduleBuffer(makeSilentBuffer(), at: nil, options: .loops)
            if !engine.isRunning { try engine.start() }
            silentNode.play()

            checkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                self?.checkAlarms()
            }
            checkAlarms() // check immediately
        } catch {
            isMonitoring = false
            print("❌ BackgroundAlarmService start error: \(error)")
        }
    }

    /// Stop background alarm sound without stopping the keep-alive engine.
    /// Called by AlarmActiveView when it takes over sound playback.
    func stopAlarmSound() {
        alarmSoundActive = false
        alarmNode.stop()
    }

    /// Stop everything — called when app returns to foreground.
    func stopMonitoring() {
        isMonitoring = false
        alarmSoundActive = false
        checkTimer?.invalidate()
        checkTimer = nil
        alarmNode.stop()
        silentNode.stop()
        engine.stop()
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
        alarmSoundActive = true

        // Schedule looping alarm tone via the engine (plays even when screen is locked)
        alarmNode.scheduleBuffer(makeAlarmBuffer(), at: nil, options: .loops)
        alarmNode.play()

        // Notify in-app UI to show AlarmActiveView
        DispatchQueue.main.async {
            NotificationManager.shared.firingAlarm = alarm
        }
    }

    // MARK: - Audio buffers

    /// ~0.1s of silence — looped to keep the audio session alive in background.
    private func makeSilentBuffer() -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(4410) // 0.1 s
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        // floatChannelData is already zero-initialised → silence
        return buf
    }

    /// A "beep-beep" pattern: two 880 Hz pulses + pause, ~0.8 s total, looped.
    private func makeAlarmBuffer() -> AVAudioPCMBuffer {
        let sampleRate = 44100.0
        // (frequency Hz, duration s, amplitude)
        let segments: [(Double, Double, Float)] = [
            (880, 0.15, 0.85),
            (0,   0.05, 0),
            (880, 0.15, 0.85),
            (0,   0.45, 0),
        ]
        let totalFrames = AVAudioFrameCount(segments.reduce(0.0) { $0 + $1.1 } * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        buf.frameLength = totalFrames
        let out = buf.floatChannelData![0]
        var offset = 0
        for (freq, dur, amp) in segments {
            let count = Int(dur * sampleRate)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                out[offset + i] = freq > 0
                    ? Float(sin(2.0 * .pi * freq * t)) * amp
                    : 0
            }
            offset += count
        }
        return buf
    }
}
