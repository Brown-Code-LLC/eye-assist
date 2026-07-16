import Foundation
import Vision
import CoreVideo
import Combine
import QuartzCore

/// A recognized text region in the current view (R15).
struct TextDetection: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let confidence: Float
    /// Vision-normalized, origin bottom-left (same space as Detection.bbox).
    let bbox: CGRect

    static func == (lhs: TextDetection, rhs: TextDetection) -> Bool { lhs.id == rhs.id }
}

/// Decides which recognized strings get spoken (R15.3). Pure logic, unit-tested:
/// each string is keyed by its lowercased alphanumerics; a key is spoken at most
/// once per `expiry`; low-confidence strings must appear in two consecutive
/// scans, high-confidence ones pass immediately; ≤ `maxPerScan` per scan.
struct TextSpeakGate {
    static let expiry: TimeInterval = 30
    static let immediateConfidence: Float = 0.8
    static let maxPerScan = 3

    private var spokenAt: [String: Date] = [:]
    private var pending: Set<String> = []

    static func key(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// `candidates` in reading order. Returns the strings to speak now.
    mutating func admit(_ candidates: [(text: String, confidence: Float)],
                        now: Date = Date()) -> [String] {
        spokenAt = spokenAt.filter { now.timeIntervalSince($0.value) < Self.expiry }

        var toSpeak: [String] = []
        var stillPending: Set<String> = []
        for cand in candidates {
            let key = Self.key(cand.text)
            guard key.count >= 2, spokenAt[key] == nil else { continue }
            if cand.confidence >= Self.immediateConfidence || pending.contains(key) {
                if toSpeak.count < Self.maxPerScan {
                    toSpeak.append(cand.text)
                    spokenAt[key] = now
                }
            } else {
                stillPending.insert(key) // needs one more sighting (anti-flicker)
            }
        }
        pending = stillPending
        return toSpeak
    }
}

/// On-device OCR over camera frames at low cadence (R15.1): one accurate
/// Vision text request every ~1.5 s on its own queue, so the YOLO pipeline's
/// FPS is untouched.
final class TextReaderService: ObservableObject {
    static let scanInterval: CFTimeInterval = 1.5
    static let minConfidence: Float = 0.5

    /// Regions for the HUD (main thread).
    @Published private(set) var texts: [TextDetection] = []

    /// Automatic reading allowed (mode + setting + not paused — R15.5).
    /// Scanning continues regardless so ON-DEMAND "describe" can include text.
    var autoSpeak = true
    /// (joined text, pan −1…+1) — new text that cleared the gate.
    var onNewText: ((String, Float) -> Void)?

    private let queue = DispatchQueue(label: "audiovision.ocr")
    private var busy = false
    private var lastScanAt: CFTimeInterval = 0
    private var gate = TextSpeakGate()

    func process(pixelBuffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        guard !busy, now - lastScanAt >= Self.scanInterval else { return }
        busy = true
        lastScanAt = now
        queue.async { [weak self] in
            self?.scan(pixelBuffer)
            self?.busy = false
        }
    }

    private func scan(_ pixelBuffer: CVPixelBuffer) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try handler.perform([request])
        } catch {
            return
        }

        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        var found: [TextDetection] = []
        for obs in observations {
            guard let top = obs.topCandidates(1).first,
                  top.confidence >= Self.minConfidence,
                  top.string.trimmingCharacters(in: .whitespaces).count >= 2 else { continue }
            found.append(TextDetection(text: top.string,
                                       confidence: top.confidence,
                                       bbox: obs.boundingBox))
        }
        // Reading order: top-to-bottom (Vision y grows upward).
        found.sort { $0.bbox.midY > $1.bbox.midY }

        DispatchQueue.main.async { self.texts = found }

        guard autoSpeak else { return }
        let toSpeak = gate.admit(found.map { ($0.text, $0.confidence) })
        guard !toSpeak.isEmpty else { return }
        let first = found.first { $0.text == toSpeak[0] }
        let pan = Float((first?.bbox.midX ?? 0.5) * 2 - 1)
        onNewText?(toSpeak.joined(separator: ". "), pan)
    }

    /// Currently visible text as one sentence — appended to on-demand scene
    /// descriptions (R15.5).
    var visibleTextSummary: String? {
        let strings = texts.prefix(4).map(\.text)
        guard !strings.isEmpty else { return nil }
        return "Text reads: " + strings.joined(separator: ". ")
    }
}
