import Foundation
import AVFoundation
import CoreGraphics

/// Distance in meters for a detection (R1.5): median LiDAR depth inside the
/// box when available, otherwise a pinhole-camera heuristic from per-class
/// real-world height priors.
enum DistanceEstimator {

    /// Typical real-world heights (m) for **all 80 COCO classes** (R1.5) —
    /// visible vertical extent, not strict object height.
    private static let heightPriors: [String: Double] = [
        // people & animals
        "person": 1.7, "bird": 0.25, "cat": 0.3, "dog": 0.5, "horse": 1.6,
        "sheep": 0.9, "cow": 1.4, "elephant": 3.0, "bear": 1.5, "zebra": 1.4,
        "giraffe": 4.5,
        // vehicles
        "bicycle": 1.0, "car": 1.5, "motorcycle": 1.1, "airplane": 4.0, "bus": 3.0,
        "train": 3.5, "truck": 3.0, "boat": 1.5,
        // street & signals
        "traffic light": 0.9, "fire hydrant": 0.75, "stop sign": 0.75,
        "parking meter": 1.2, "bench": 0.85,
        // carried items
        "backpack": 0.45, "umbrella": 0.8, "handbag": 0.3, "tie": 0.5, "suitcase": 0.6,
        // sports
        "frisbee": 0.25, "skis": 1.7, "snowboard": 1.5, "sports ball": 0.22,
        "kite": 0.8, "baseball bat": 0.85, "baseball glove": 0.3, "skateboard": 0.2,
        "surfboard": 1.8, "tennis racket": 0.7,
        // tableware & food
        "bottle": 0.25, "wine glass": 0.18, "cup": 0.12, "fork": 0.18, "knife": 0.22,
        "spoon": 0.18, "bowl": 0.08, "banana": 0.2, "apple": 0.08, "sandwich": 0.1,
        "orange": 0.08, "broccoli": 0.15, "carrot": 0.18, "hot dog": 0.15,
        "pizza": 0.35, "donut": 0.1, "cake": 0.15,
        // furniture & fixtures
        "chair": 0.9, "couch": 0.8, "potted plant": 0.4, "bed": 0.6,
        "dining table": 0.75, "toilet": 0.75,
        // electronics & household
        "tv": 0.6, "laptop": 0.25, "mouse": 0.04, "remote": 0.18, "keyboard": 0.15,
        "cell phone": 0.15, "microwave": 0.3, "oven": 0.75, "toaster": 0.2,
        "sink": 0.3, "refrigerator": 1.7, "book": 0.25, "clock": 0.3, "vase": 0.3,
        "scissors": 0.2, "teddy bear": 0.35, "hair drier": 0.25, "toothbrush": 0.19,
    ]

    /// Generic prior when a label is unmapped — every detection still gets an
    /// estimate (R1.5), just a rougher one.
    private static let genericHeightPrior = 0.5

    /// bbox: normalized, Vision convention (origin bottom-left, upright image).
    static func estimate(bbox: CGRect, label: String, depth: AVDepthData?) -> Double? {
        if let depth, let d = lidarDistance(bbox: bbox, depth: depth) { return d }
        return heuristicDistance(bbox: bbox, label: label)
    }

    /// Median depth over a sample grid in the central 50% of the box.
    private static func lidarDistance(bbox: CGRect, depth: AVDepthData) -> Double? {
        let data = depth.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depth : depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = data.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride

        // Depth map is in sensor (landscape) orientation; the Vision bbox is in
        // upright space from a 90°-rotated frame. Map upright (x,y) -> sensor.
        let inner = bbox.insetBy(dx: bbox.width * 0.25, dy: bbox.height * 0.25)
        var samples: [Float32] = []
        let grid = 5
        let floatBuffer = base.assumingMemoryBound(to: Float32.self)
        for i in 0..<grid {
            for j in 0..<grid {
                let ux = inner.minX + inner.width * CGFloat(i) / CGFloat(grid - 1)
                let uy = inner.minY + inner.height * CGFloat(j) / CGFloat(grid - 1)
                // Upright(portrait, bottom-left origin) -> sensor(landscape, top-left):
                // sensorX grows with upright-bottom→top? Rotation used: .right ⇒
                // sensorX = 1 - uprightY(top-left)… equivalently with Vision's
                // bottom-left origin: sensorX = uy is wrong by mirror; use:
                let sx = Int((1 - uy) * CGFloat(width - 1))
                let sy = Int(ux * CGFloat(height - 1))
                guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                let v = floatBuffer[sy * rowStride + sx]
                if v.isFinite && v > 0 { samples.append(v) }
            }
        }
        guard samples.count >= 5 else { return nil }
        samples.sort()
        return Double(samples[samples.count / 2])
    }

    /// Pinhole model: distance = f_pix * realHeight / pixelHeight, assuming a
    /// ~58° vertical field of view. Clamped to a plausible 0.3–12 m band.
    private static func heuristicDistance(bbox: CGRect, label: String) -> Double? {
        let realHeight = heightPriors[label.lowercased()] ?? genericHeightPrior
        let boxHeightFraction = Double(bbox.height)
        guard boxHeightFraction > 0.02 else { return nil }
        let halfFOV = 58.0 / 2 * .pi / 180
        let focalNorm = 1 / (2 * tan(halfFOV)) // focal length in image-height units
        let distance = focalNorm * realHeight / boxHeightFraction
        return min(max(distance, 0.3), 12)
    }
}
