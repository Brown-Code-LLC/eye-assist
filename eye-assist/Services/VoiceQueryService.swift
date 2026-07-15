import Foundation
import Speech
import AVFoundation
import Combine

/// Hold-to-ask voice questions (R7.*): "Where are my keys?" → match against
/// current detections, then recent history, and speak the answer.
@MainActor
final class VoiceQueryService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Spoken words → COCO-80 label (plus common synonyms).
    static let synonymMap: [String: String] = {
        var map: [String: String] = [:]
        let cocoLabels = [
            "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
            "boat", "bench", "cat", "dog", "horse", "backpack", "umbrella", "handbag",
            "tie", "suitcase", "bottle", "cup", "fork", "knife", "spoon", "bowl",
            "chair", "couch", "bed", "toilet", "tv", "laptop", "mouse", "remote",
            "keyboard", "book", "clock", "vase", "scissors", "toothbrush", "sink",
            "refrigerator", "oven", "microwave", "toaster",
        ]
        for l in cocoLabels { map[l] = l }
        map["phone"] = "cell phone"; map["cellphone"] = "cell phone"; map["mobile"] = "cell phone"
        map["sofa"] = "couch"; map["table"] = "dining table"; map["bag"] = "handbag"
        map["purse"] = "handbag"; map["glass"] = "wine glass"; map["mug"] = "cup"
        map["bike"] = "bicycle"; map["fridge"] = "refrigerator"; map["television"] = "tv"
        map["computer"] = "laptop"; map["people"] = "person"; map["someone"] = "person"
        // Street & pedestrian vocabulary
        map["traffic"] = "traffic light"; map["light"] = "traffic light"
        map["lights"] = "traffic light"; map["sign"] = "stop sign"
        map["hydrant"] = "fire hydrant"; map["meter"] = "parking meter"
        map["bench"] = "bench"; map["crossing"] = "traffic light"
        map["keys"] = "__unsupported__"; map["wallet"] = "__unsupported__"
        return map
    }()

    static func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    func startListening() {
        guard !isListening, let recognizer, recognizer.isAvailable else { return }
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            Task { @MainActor in
                self.transcript = result.bestTranscription.formattedString
            }
        }
    }

    /// Stops capture and returns the spoken answer for the question.
    func stopAndAnswer(current: [Detection], history: [HistoryEntry]) -> String {
        stopListening()
        let question = transcript.lowercased()
        guard !question.isEmpty else {
            return "I didn't catch that. Hold the button and ask, for example, where is my cup."
        }

        // Find the first known object word in the question.
        var target: String?
        for word in question.split(separator: " ").map(String.init) {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if let label = Self.synonymMap[cleaned] {
                if label == "__unsupported__" {
                    return "I can't detect \(cleaned) yet, but I can find things like cups, phones, and bags."
                }
                target = label
                break
            }
        }
        guard let target else {
            return "I heard: \(transcript). Ask about an object, like a cup, a phone, or a chair."
        }

        if let found = current.first(where: { $0.label == target }) {
            var answer = "\(found.displayName), \(found.position.spoken)"
            if let d = found.distanceMeters { answer += ", \(spokenDistance(d))" }
            return answer + "."
        }
        if let past = history.first(where: { $0.label == target }) {
            return "\(past.label.capitalized) isn't in view now. Last seen \(past.position.spoken) at \(past.timeString)."
        }
        return "I haven't seen a \(target) in this session."
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false

        // Hand the session back to playback so narration keeps working (R9.3).
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}
