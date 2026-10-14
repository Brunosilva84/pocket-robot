import AVFoundation
import NaturalLanguage

/// Speaks reply text; tells the app when the queue has drained.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var queued = 0
    private var voices: [String: AVSpeechSynthesisVoice] = [:]  // best voice per language
    var onFinished: (() -> Void)?

    var isSpeaking: Bool { queued > 0 }

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if queued == 0 {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        queued += 1
        let u = AVSpeechUtterance(string: trimmed)
        u.voice = voice(for: trimmed)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.pitchMultiplier = 1.0
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0
        synth.speak(u)
    }

    /// Best installed voice for the text's language: premium > enhanced > default, device region breaks ties.
    private func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let detected = NLLanguageRecognizer.dominantLanguage(for: text).flatMap { $0 == .undetermined ? nil : $0.rawValue }
        let lang = baseLanguage(detected ?? AVSpeechSynthesisVoice.currentLanguageCode())
        if let cached = voices[lang] { return cached }
        let region = Locale.current.region?.identifier
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { baseLanguage($0.language) == lang }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .max { score($0, region) < score($1, region) }
        voices[lang] = best
        return best
    }

    private func score(_ v: AVSpeechSynthesisVoice, _ region: String?) -> Int {
        let inRegion = region.map { v.language.hasSuffix("-\($0)") } ?? false
        return v.quality.rawValue * 2 + (inRegion ? 1 : 0)
    }

    /// "en-GB" / "zh-Hans" -> "en" / "zh".
    private func baseLanguage(_ code: String) -> String {
        String(code.prefix { $0 != "-" && $0 != "_" })
    }

    func stop() {
        queued = 0
        synth.stopSpeaking(at: .immediate)
    }

    private func utteranceEnded() {
        guard queued > 0 else { return }
        queued -= 1
        if queued == 0 {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            onFinished?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }
}
