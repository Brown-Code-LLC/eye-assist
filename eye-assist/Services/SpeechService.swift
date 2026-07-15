import Foundation
import AVFoundation
import Combine

/// All spoken output (R2.*, R3.1). Two render paths:
///  - spatial: AVSpeechSynthesizer.write → AVAudioPlayerNode with stereo pan
///    matched to the object position;
///  - plain: AVSpeechSynthesizer.speak (fallback / spatial off).
/// Utterances are serialized through an internal FIFO either way.
final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var currentText = ""

    var muted = false

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var playerFormat: AVAudioFormat?
    private let workQueue = DispatchQueue(label: "audiovision.speech")

    private struct Job { let text: String; let pan: Float; let spatial: Bool }
    private var queue: [Job] = []
    private var jobActive = false
    private(set) var lastSpoken: (text: String, pan: Float)?

    // write-path bookkeeping
    private var scheduledCount = 0
    private var completedCount = 0
    private var finalMarkerSeen = false

    override init() {
        super.init()
        synth.delegate = self
        configureSession()
        engine.attach(player)
    }

    private func configureSession() {
        // Duck (not stop) other audio; keep speaking on silent ringer (R9.3).
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    // MARK: - Public API

    /// pan −1(left)…+1(right); honored when `spatial` is true.
    func speak(_ text: String, pan: Float = 0, spatial: Bool = false, interrupt: Bool = false) {
        guard !muted, !text.isEmpty else { return }
        lastSpoken = (text, pan)
        workQueue.async { [self] in
            if interrupt {
                queue.removeAll()
                stopCurrentJob()
            }
            queue.append(Job(text: text, pan: pan, spatial: spatial))
            startNextIfIdle()
        }
    }

    func repeatLast() {
        guard let last = lastSpoken else { return }
        let wasMuted = muted
        muted = false
        speak(last.text, pan: last.pan, spatial: false, interrupt: true)
        muted = wasMuted
    }

    func stopAll() {
        workQueue.async { [self] in
            queue.removeAll()
            stopCurrentJob()
        }
    }

    var hasPendingSpeech: Bool { jobActive || !queue.isEmpty }

    // MARK: - Queue engine (all on workQueue)

    private func startNextIfIdle() {
        guard !jobActive, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        jobActive = true
        setUIState(speaking: true, text: job.text)

        let utterance = makeUtterance(job.text)
        if job.spatial {
            renderSpatial(utterance, pan: job.pan)
        } else {
            synth.speak(utterance) // completion via delegate
        }
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        // Settings are MainActor; read defaults directly to stay thread-safe.
        let speed = UserDefaults.standard.object(forKey: "speechSpeed") as? Double ?? 0.6
        let minR = AVSpeechUtteranceMinimumSpeechRate
        let maxR = AVSpeechUtteranceMaximumSpeechRate
        u.rate = minR + (maxR - minR) * Float(0.3 + speed * 0.55)
        if let id = UserDefaults.standard.string(forKey: "voiceIdentifier"),
           let v = AVSpeechSynthesisVoice(identifier: id) {
            u.voice = v
        } else {
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        return u
    }

    private func finishJob() {
        jobActive = false
        if queue.isEmpty { setUIState(speaking: false, text: currentText) }
        startNextIfIdle()
    }

    private func stopCurrentJob() {
        synth.stopSpeaking(at: .immediate)
        player.stop()
        jobActive = false
        setUIState(speaking: false, text: currentText)
    }

    private func setUIState(speaking: Bool, text: String) {
        DispatchQueue.main.async {
            self.isSpeaking = speaking
            self.currentText = text
        }
    }

    // MARK: - Spatial write path

    private func renderSpatial(_ utterance: AVSpeechUtterance, pan: Float) {
        scheduledCount = 0
        completedCount = 0
        finalMarkerSeen = false
        player.pan = max(-1, min(1, pan))

        synth.write(utterance) { [weak self] buffer in
            guard let self else { return }
            self.workQueue.async {
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    self.finalMarkerSeen = true
                    self.checkSpatialDone()
                    return
                }
                if !self.ensureEngine(format: pcm.format) {
                    // Engine unavailable → fall back to plain path for this text.
                    self.synth.speak(self.makeUtterance(utterance.speechString))
                    return
                }
                self.scheduledCount += 1
                self.player.scheduleBuffer(pcm) {
                    self.workQueue.async {
                        self.completedCount += 1
                        self.checkSpatialDone()
                    }
                }
                if !self.player.isPlaying { self.player.play() }
            }
        }
    }

    private func checkSpatialDone() {
        if finalMarkerSeen && completedCount >= scheduledCount {
            finishJob()
        }
    }

    private func ensureEngine(format: AVAudioFormat) -> Bool {
        if playerFormat != format {
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            playerFormat = format
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        return true
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        workQueue.async { [self] in
            if jobActive { finishJob() }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        workQueue.async { [self] in
            if jobActive { finishJob() }
        }
    }
}
