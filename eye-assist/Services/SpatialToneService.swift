import Foundation
import AVFoundation

/// Focus-mode tracking tone (R3.3): a sine wave rendered directly into a
/// stereo buffer so pan is exact — left/right gain follows the locked object's
/// horizontal position, pitch rises as the object approaches frame center.
final class SpatialToneService {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    // Written from main thread, read from the render thread.
    private let lock = NSLock()
    private var _frequency: Double = 880
    private var _pan: Double = 0 // −1…+1
    private var _active = false
    private var phase: Double = 0
    private let sampleRate: Double = 44100

    private(set) var isRunning = false

    /// Current tone frequency, for the TONE stat tile (mockup 1g).
    var displayFrequency: Int {
        lock.lock(); defer { lock.unlock() }
        return Int(_frequency)
    }

    func start() {
        guard !isRunning else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            self.lock.lock()
            let freq = self._frequency
            let pan = self._pan
            let active = self._active
            self.lock.unlock()

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 2,
                  let left = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let leftGain = Float(min(1, 1 - pan) * 0.5 + 0.15)
            let rightGain = Float(min(1, 1 + pan) * 0.5 + 0.15)
            let increment = 2 * Double.pi * freq / self.sampleRate

            for frame in 0..<Int(frameCount) {
                var sample: Float = 0
                if active {
                    // Pulsed tone: 120ms beep every 500ms reads better than a drone.
                    let t = self.phase / (2 * Double.pi * freq) // seconds since phase 0
                    let pulseOn = t.truncatingRemainder(dividingBy: 0.5) < 0.12
                    sample = pulseOn ? Float(sin(self.phase)) * 0.35 : 0
                }
                left[frame] = sample * leftGain
                right[frame] = sample * rightGain
                self.phase += increment
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        do {
            try engine.start()
            isRunning = true
        } catch {
            print("SpatialToneService: engine start failed – \(error)")
        }
        lock.lock(); _active = true; lock.unlock()
    }

    func stop() {
        lock.lock(); _active = false; lock.unlock()
        engine.pause()
        isRunning = false
    }

    /// pan −1…+1 from object midX; centerOffset 0…1 (0 = dead center) drives pitch.
    func update(pan: Double, centerOffset: Double) {
        lock.lock()
        _pan = max(-1, min(1, pan))
        // 1320 Hz at center → 440 Hz at edge (R3.3).
        _frequency = 440 + (1 - min(1, max(0, centerOffset))) * 880
        lock.unlock()
    }
}
