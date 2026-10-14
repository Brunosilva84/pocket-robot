import AVFoundation

/// Records AAC m4a, 16 kHz mono, while the screen is held.
@MainActor
final class Recorder {
    private var recorder: AVAudioRecorder?
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "talk.m4a")

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// Asks for the microphone the first time; later calls return the stored answer.
    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        try? FileManager.default.removeItem(at: fileURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let r = try AVAudioRecorder(url: fileURL, settings: settings)
        guard r.record() else { throw RecorderError.couldNotStart }
        recorder = r
    }

    /// Stops and returns the file, or nil when nothing usable was recorded.
    func stop() -> URL? {
        guard let r = recorder else { return nil }
        let duration = r.currentTime
        r.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return duration > 0.3 ? fileURL : nil
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum RecorderError: Error {
    case couldNotStart
}
