import Foundation
import Vision
import CoreML
import AVFoundation

/// Runs the YOLO Core ML model over camera frames via Vision (R1.*).
/// The exported model embeds NMS, so results arrive as
/// `VNRecognizedObjectObservation` regardless of YOLO generation.
final class DetectionService {
    static let confidenceThreshold: Float = 0.5

    private var visionModel: VNCoreMLModel?
    private let inferenceQueue = DispatchQueue(label: "audiovision.inference")
    private var busy = false
    private var frameTimestamps: [CFTimeInterval] = []

    /// Model name for the telemetry badge, from Models/model_name.txt (R1.3).
    let modelName: String

    /// Called on the inference queue with filtered detections + measured FPS.
    var onDetections: (([Detection], Double) -> Void)?

    init() {
        if let url = Bundle.main.url(forResource: "model_name", withExtension: "txt"),
           let name = try? String(contentsOf: url, encoding: .utf8) {
            modelName = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        } else {
            modelName = "YOLO"
        }
        inferenceQueue.async { [weak self] in self?.loadModel() }
    }

    private func loadModel() {
        // .mlpackage / .mlmodel both compile to .mlmodelc in the app bundle.
        guard let url = Bundle.main.url(forResource: "YOLODetector", withExtension: "mlmodelc") else {
            print("DetectionService: YOLODetector.mlmodelc missing from bundle")
            return
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let mlModel = try MLModel(contentsOf: url, configuration: config)
            visionModel = try VNCoreMLModel(for: mlModel)
        } catch {
            print("DetectionService: model load failed – \(error)")
        }
    }

    /// Throttled: frames arriving while an inference is in flight are dropped.
    /// Category filtering happens downstream in AppModel (R1.6).
    func process(pixelBuffer: CVPixelBuffer, depth: AVDepthData?) {
        guard !busy, visionModel != nil else { return }
        busy = true
        inferenceQueue.async { [weak self] in
            defer { self?.busy = false }
            self?.runInference(pixelBuffer: pixelBuffer, depth: depth)
        }
    }

    private func runInference(pixelBuffer: CVPixelBuffer, depth: AVDepthData?) {
        guard let visionModel else { return }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        // Back camera in portrait: buffer is landscape, rotate with .right.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try handler.perform([request])
        } catch {
            return
        }

        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
        let detections: [Detection] = observations.compactMap { obs in
            guard let top = obs.labels.first,
                  top.confidence >= Self.confidenceThreshold else { return nil }
            return Detection(
                label: top.identifier,
                confidence: top.confidence,
                bbox: obs.boundingBox,
                position: PositionBucket(normalizedMidX: obs.boundingBox.midX),
                distanceMeters: DistanceEstimator.estimate(
                    bbox: obs.boundingBox, label: top.identifier, depth: depth)
            )
        }
        .sorted { $0.confidence > $1.confidence }

        // Rolling 2s window FPS (R1.3).
        let now = CACurrentMediaTime()
        frameTimestamps.append(now)
        frameTimestamps.removeAll { now - $0 > 2 }
        let fps = Double(frameTimestamps.count) / 2

        onDetections?(detections, fps)
    }
}
