import Foundation
import SwiftUI
import AVFoundation
import Combine

/// Central app state (design.md §1): owns the services, receives detections,
/// drives narration, focus tracking (R4) and permission flow (R8).
@MainActor
final class AppModel: ObservableObject {

    // MARK: Services
    let settings = SettingsStore.shared
    let camera = CameraService()
    let detector = DetectionService()
    let speech = SpeechService()
    let tone = SpatialToneService()
    let history: HistoryStore
    let narration: NarrationEngine
    let voiceQuery = VoiceQueryService()
    let advisor = NavigationAdvisor()
    let router = RouteNavigator()
    let textReader = TextReaderService()

    // MARK: Published state
    @Published private(set) var detections: [Detection] = []
    @Published private(set) var fps: Double = 0
    @Published private(set) var pathSuggestion: PathSuggestion = .clear
    @Published var audioPaused = false {
        didSet {
            narration.paused = audioPaused
            speech.muted = audioPaused
            if audioPaused { speech.stopAll() }
        }
    }
    @Published var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published var cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied

    // Focus mode (R4)
    struct Focus {
        var detection: Detection
        var guiding = false
        var lostSince: Date?
    }
    @Published var focus: Focus?

    private var lastGuidanceSpokenAt = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init() {
        let history = HistoryStore()
        self.history = history
        self.narration = NarrationEngine(speech: speech, history: history, settings: settings)

        camera.onFrame = { [weak self] pixelBuffer, depth in
            self?.detector.process(pixelBuffer: pixelBuffer, depth: depth)
            self?.textReader.process(pixelBuffer: pixelBuffer) // own cadence (R15.1)
        }
        detector.onDetections = { [weak self] detections, fps in
            Task { @MainActor in
                self?.handle(detections: detections, fps: fps)
            }
        }
        // Turn cues share the one speech queue with narration (R13.6).
        router.speak = { [weak self] sentence, interrupt in
            self?.speech.speak(sentence, interrupt: interrupt)
        }
        // New text cleared the speak-once gate (R15.2).
        textReader.onNewText = { [weak self] text, pan in
            Task { @MainActor in
                guard let self, self.focus == nil else { return }
                self.speech.speak("Text: \(text)", pan: pan, spatial: self.settings.spatialAudio)
            }
        }
        // Views observe AppModel; forward the text reader's region updates.
        textReader.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    func startSession() {
        guard cameraAuthorized else { return }
        history.beginSession()
        camera.configureAndStart()
    }

    func stopSession() {
        camera.stop()
        speech.stopAll()
        tone.stop()
    }

    func requestCameraPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAuthorized = granted
        cameraDenied = !granted
        if granted { startSession() }
    }

    func requestSpeechPermissions() {
        VoiceQueryService.requestAuthorization()
    }

    // MARK: Detection handling

    private func handle(detections: [Detection], fps: Double) {
        // Category filters applied here, on the main actor where settings live (R1.6).
        let filtered = detections.filter { settings.enabledCategories.contains($0.category) }
        self.detections = filtered
        self.fps = fps

        pathSuggestion = advisor.update(filtered)
        // Automatic text reading only in continuous/new-only, toggle on,
        // audio unpaused (R15.5); scanning itself continues for on-demand.
        textReader.autoSpeak = settings.readTextAloud
            && settings.mode != .onDemand && !audioPaused

        if focus != nil {
            trackFocusedObject(in: filtered)
        } else {
            narration.ingest(filtered)
            narration.ingestNavigation(pathSuggestion)
        }
    }

    // MARK: Focus mode (R4)

    func lock(on detection: Detection) {
        focus = Focus(detection: detection)
        speech.speak("Locked on \(detection.displayName). Other objects silenced.",
                     interrupt: true)
        if settings.spatialAudio { startToneFor(detection) }
    }

    func unlock() {
        focus = nil
        tone.stop()
        speech.speak("Unlocked.", interrupt: true)
    }

    func toggleGuidance() {
        guard var f = focus else { return }
        f.guiding.toggle()
        focus = f
        if f.guiding {
            if !tone.isRunning { startToneFor(f.detection) }
            speech.speak("Guiding you to the \(f.detection.displayName).", interrupt: true)
        }
    }

    private func startToneFor(_ d: Detection) {
        tone.start()
        tone.update(pan: Double(d.bbox.midX) * 2 - 1,
                    centerOffset: abs(Double(d.bbox.midX) - 0.5) * 2)
    }

    private func trackFocusedObject(in detections: [Detection]) {
        guard var f = focus else { return }
        // Re-match by label + nearest center (design.md §3).
        let candidates = detections.filter { $0.label == f.detection.label }
        let previous = f.detection
        let match = candidates.min {
            hypot($0.bbox.midX - previous.bbox.midX, $0.bbox.midY - previous.bbox.midY) <
            hypot($1.bbox.midX - previous.bbox.midX, $1.bbox.midY - previous.bbox.midY)
        }

        if let match {
            f.detection = match
            f.lostSince = nil
            tone.update(pan: Double(match.bbox.midX) * 2 - 1,
                        centerOffset: abs(Double(match.bbox.midX) - 0.5) * 2)
            if f.guiding, Date().timeIntervalSince(lastGuidanceSpokenAt) > 2.5, !speech.hasPendingSpeech {
                lastGuidanceSpokenAt = Date()
                var s = "\(match.displayName), \(match.position.spoken)"
                if let d = match.distanceMeters { s += ", \(spokenDistance(d))" }
                speech.speak(s, pan: Float(match.bbox.midX * 2 - 1), spatial: settings.spatialAudio)
            }
        } else {
            if f.lostSince == nil {
                f.lostSince = Date()
            } else if Date().timeIntervalSince(f.lostSince!) > 2, !speech.hasPendingSpeech {
                speech.speak("\(f.detection.displayName) lost. Still looking.")
                f.lostSince = Date() // repeat notice every ~2s while lost (R4.5)
            }
        }
        focus = f
    }

    // MARK: On-demand & gestures

    func describeScene() {
        narration.describeScene(detections)
        // On-demand users get visible text with their description (R15.5).
        if settings.readTextAloud, let textSummary = textReader.visibleTextSummary {
            speech.speak(textSummary)
        }
    }

    func repeatLast() {
        speech.repeatLast()
    }

    func beginVoiceQuestion() {
        speech.stopAll()
        voiceQuery.startListening()
    }

    func endVoiceQuestion() {
        let answer = voiceQuery.stopAndAnswer(current: detections, history: history.entries)
        speech.speak(answer, interrupt: true)
    }
}
