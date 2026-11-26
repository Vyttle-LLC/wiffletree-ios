import AVFoundation
import Observation
import Speech

/// The composer's mic (design call 5): speech recognised on this iPhone only, never sent to a
/// server, with the input level for the live waveform.
@MainActor
@Observable
final class Dictation {
    private(set) var isListening = false
    /// The latest input levels, oldest first, each from 0 to 1.
    private(set) var levels = Array(repeating: Float(0), count: 13)
    /// Why dictation could not start, such as a denied permission.
    var problem: String?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    /// Changes when dictation is cancelled or starts again, so a result is used only by the session
    /// that heard it.
    @ObservationIgnored private var session = 0

    /// Starts listening. `onText` gets the whole transcript so far each time it grows.
    func start(onText: @escaping @MainActor (String) -> Void) async {
        guard !isListening else { return }
        guard await Self.speechAllowed(), await AVAudioApplication.requestRecordPermission() else {
            problem = "Dictation needs the microphone and speech recognition. Allow both in Settings."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            problem = "Dictation on this iPhone isn't available for your language."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.feed(request) { [weak self] level in
                Task { @MainActor in self?.push(level) }
            })
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            problem = "Dictation couldn't start: \(error.localizedDescription)"
            return
        }
        cancel()
        self.engine = engine
        self.request = request
        isListening = true
        let session = session
        task = recognizer.recognitionTask(with: request, resultHandler: Self.results { [weak self] text, ended in
            Task { @MainActor in
                // A result of a cancelled session, such as the final one after Send, must not put
                // the sent text back in the field.
                guard let self, self.session == session else { return }
                if let text { onText(text) }
                if ended {
                    self.stop()
                    self.task = nil
                }
            }
        })
    }

    /// Stops listening and lets recognition finish: its final words still reach the field, where
    /// they can be edited before sending.
    func stop() {
        guard isListening else { return }
        endAudio()
        task?.finish()
    }

    /// Stops listening and drops anything still being recognised, as Send and leaving the screen do.
    func cancel() {
        session += 1
        if isListening { endAudio() }
        task?.cancel()
        task = nil
    }

    private func endAudio() {
        isListening = false
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        engine = nil
        request = nil
        levels = levels.map { _ in 0 }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func push(_ level: Float) {
        levels = Array((levels + [level]).suffix(levels.count))
    }

    // The audio and speech callbacks run off the main actor, so they are built outside it.

    private nonisolated static func feed(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        level: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            level(rootMeanSquare(buffer))
        }
    }

    private nonisolated static func results(
        _ handle: @escaping @Sendable (_ text: String?, _ ended: Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            handle(result?.bestTranscription.formattedString, error != nil || result?.isFinal == true)
        }
    }

    /// The buffer's loudness, scaled so speech fills most of the range.
    private nonisolated static func rootMeanSquare(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        let sum = (0..<count).reduce(Float(0)) { $0 + samples[$1] * samples[$1] }
        return min(1, (sum / Float(count)).squareRoot() * 12)
    }

    private nonisolated static func speechAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }
}
