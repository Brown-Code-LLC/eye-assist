import Foundation
import Combine
import CoreGraphics

/// Turns the detection stream into speech according to the narration mode
/// (R2.*): CONTINUOUS scene summaries, NEW-ONLY announcements, or ON-DEMAND
/// silence until asked. Also feeds History (announced objects only) and the
/// spatial-pan indicator.
@MainActor
final class NarrationEngine: ObservableObject {

    /// Last announced object — drives the "NEW OBJECT ANNOUNCED" card (1b).
    @Published private(set) var lastAnnouncement: Detection?
    /// Pan of the most recent announcement, −1…+1, for the pan bar (R3.2).
    @Published private(set) var lastPan: Double = 0
    /// "Ignoring N known objects in view" (1b).
    @Published private(set) var ignoredCount = 0

    var paused = false

    private let speech: SpeechService
    private let history: HistoryStore
    private let settings: SettingsStore

    private var lastContinuousAt = Date.distantPast
    private static let continuousInterval: TimeInterval = 3.5
    // Navigation speech state (R11.3)
    private var lastNavSuggestion: PathSuggestion = .clear
    private var lastNavSpokenKind: PathSuggestion.Kind = .clear
    private var lastNavSpokenAt = Date.distantPast
    private static let navSpeechInterval: TimeInterval = 4
    /// label → last seen; entry expires after 10s absence so the object
    /// re-announces when it returns (new-only mode).
    private var knownLabels: [String: Date] = [:]
    private static let knownExpiry: TimeInterval = 10

    init(speech: SpeechService, history: HistoryStore, settings: SettingsStore) {
        self.speech = speech
        self.history = history
        self.settings = settings
    }

    // MARK: - Frame ingest

    func ingest(_ detections: [Detection]) {
        let now = Date()
        // Expire absent labels.
        let present = Set(detections.map(\.label))
        knownLabels = knownLabels.filter { present.contains($0.key) || now.timeIntervalSince($0.value) < Self.knownExpiry }
        for label in present { knownLabels[label] = now }

        guard !paused else { return }

        switch settings.mode {
        case .continuous:
            guard now.timeIntervalSince(lastContinuousAt) >= Self.continuousInterval,
                  !speech.hasPendingSpeech,
                  let sentence = sceneSentence(detections, verbosity: settings.verbosity) else { return }
            lastContinuousAt = now
            announce(detections.first, sentence: sentence)

        case .newOnly:
            let newOnes = detections.filter { det in
                guard let seen = knownLabels[det.label] else { return true }
                return seen == now // just inserted this frame → first sighting
            }
            // A label whose timestamp was just refreshed isn't distinguishable
            // via the dictionary alone; track announced labels separately.
            let unannounced = announcementOrder(newOnes.filter { !announcedLabels.contains($0.label) })
            ignoredCount = detections.count - unannounced.count
            guard let first = unannounced.first else { return }
            announcedLabels.insert(first.label)
            scheduleAnnouncedExpiry(for: first.label)
            announce(first, sentence: newObjectSentence(first, verbosity: settings.verbosity))

        case .onDemand:
            break // silent until describeScene()/voice question (R2.1)
        }
    }

    private var announcedLabels = Set<String>()

    private func scheduleAnnouncedExpiry(for label: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.knownExpiry))
            guard let self else { return }
            if let seen = self.knownLabels[label], Date().timeIntervalSince(seen) >= Self.knownExpiry - 0.5 {
                self.announcedLabels.remove(label)
            } else if self.knownLabels[label] == nil {
                self.announcedLabels.remove(label)
            } else {
                self.scheduleAnnouncedExpiry(for: label) // still in view, check again later
            }
        }
    }

    // MARK: - Navigation (R11.3)

    /// Speaks path-suggestion changes: rate-limited, STOP interrupts current
    /// speech immediately, CLEAR is only announced when recovering from a
    /// blocked state.
    func ingestNavigation(_ suggestion: PathSuggestion) {
        lastNavSuggestion = suggestion
        guard !paused, settings.mode != .onDemand else { return }
        guard suggestion.kind != lastNavSpokenKind else { return }

        let now = Date()
        let urgent = suggestion.kind == .stop
        guard urgent || now.timeIntervalSince(lastNavSpokenAt) >= Self.navSpeechInterval else { return }

        lastNavSpokenKind = suggestion.kind
        lastNavSpokenAt = now
        speech.speak(suggestion.spoken, interrupt: urgent)
    }

    // MARK: - On demand

    /// "Describe scene" button / voice trigger (R2.1 on-demand).
    /// Includes the current path suggestion so on-demand users get safety
    /// guidance too (R11.3).
    func describeScene(_ detections: [Detection]) {
        var sentence = sceneSentence(detections, verbosity: settings.verbosity)
            ?? "Nothing detected right now."
        if lastNavSuggestion.isWarning {
            sentence += " " + lastNavSuggestion.spoken
        }
        announce(detections.first, sentence: sentence, interrupt: true)
    }

    func repeatLast() {
        speech.repeatLast()
    }

    // MARK: - Sentence composition (R2.2)

    private func announce(_ primary: Detection?, sentence: String, interrupt: Bool = false) {
        let pan = primary.map { Float($0.bbox.midX * 2 - 1) } ?? 0
        lastPan = Double(pan)
        lastAnnouncement = primary
        speech.speak(sentence, pan: pan, spatial: settings.spatialAudio, interrupt: interrupt)
        if let primary { history.add(primary) }
    }

    private func phrase(_ d: Detection, verbosity: Verbosity) -> String {
        var s = "\(d.displayName) \(d.position.spoken)"
        if verbosity != .brief, let dist = d.distanceMeters {
            s += ", \(spokenDistance(dist))"
        }
        if verbosity == .full {
            s += ", \(Int(d.confidence * 100)) percent"
        }
        return s
    }

    /// Safety-critical street objects first, then by confidence (R6.7).
    private func announcementOrder(_ detections: [Detection]) -> [Detection] {
        detections.sorted {
            let p0 = FilterCategory.priorityLabels.contains($0.label)
            let p1 = FilterCategory.priorityLabels.contains($1.label)
            if p0 != p1 { return p0 }
            return $0.confidence > $1.confidence
        }
    }

    /// Top-3 detections (priority-ordered) → one sentence, e.g.
    /// "Person ahead, one meter. Chair on your right."
    private func sceneSentence(_ detections: [Detection], verbosity: Verbosity) -> String? {
        guard !detections.isEmpty else { return nil }
        var parts = announcementOrder(detections).prefix(3).map { phrase($0, verbosity: verbosity) }
        if verbosity == .full {
            parts.append("\(detections.count) object\(detections.count == 1 ? "" : "s") in view")
        }
        return parts.joined(separator: ". ") + "."
    }

    private func newObjectSentence(_ d: Detection, verbosity: Verbosity) -> String {
        var s = "New: " + phrase(d, verbosity: verbosity)
        // Near obstacles carry their avoidance hint inline (R11.5).
        if d.isNavObstacle, let hint = lastNavSuggestion.avoidanceHint {
            s += " — \(hint)"
        }
        return s + "."
    }
}
