import Foundation
import CoreML
import AVFoundation
import Accelerate

/// Decodes YOLO-seg raw Core ML outputs (R14): the export has no embedded NMS,
/// so score filtering, greedy NMS, and mask composition happen here.
/// Tensor layout (validated against the exported model):
///  - boxes  [1, 116, 8400]: rows 0–3 xywh (center, 640-px model space),
///    4–83 class scores, 84–115 mask coefficients
///  - protos [1, 32, 160, 160]: mask prototypes; instance mask logits =
///    coeffs · protos, sigmoid > 0.5 ⟺ logit > 0 (sigmoid skipped)
enum SegmentationDecoder {
    static let confidenceThreshold: Float = 0.5
    static let iouThreshold: Float = 0.45
    static let maxInstances = 12

    private static let inputSize: Float = 640
    private static let protoSize = 160
    private static let coeffCount = 32
    private static let classCount = 80

    /// COCO-80, in YOLO training order.
    static let classNames = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
        "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
        "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
        "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
        "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
        "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
        "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
        "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
        "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear",
        "hair drier", "toothbrush",
    ]

    private struct Candidate {
        let anchor: Int
        let classIndex: Int
        let score: Float
        let cx: Float, cy: Float, w: Float, h: Float
    }

    /// `outputs` are the model's two MultiArrays in any order.
    static func decode(outputs: [MLMultiArray], depth: AVDepthData?) -> [Detection] {
        guard let boxesArray = outputs.first(where: { $0.shape.count == 3 }),
              let protosArray = outputs.first(where: { $0.shape.count == 4 }),
              boxesArray.dataType == .float32, protosArray.dataType == .float32
        else { return [] }

        let anchorCount = boxesArray.shape[2].intValue
        guard boxesArray.shape[1].intValue == 4 + classCount + coeffCount else { return [] }

        return boxesArray.withUnsafeBufferPointer(ofType: Float.self) { boxesBuf in
            protosArray.withUnsafeBufferPointer(ofType: Float.self) { protosBuf in
                decode(boxes: boxesBuf.baseAddress!, anchorCount: anchorCount,
                       protos: protosBuf.baseAddress!, depth: depth)
            }
        }
    }

    private static func decode(boxes: UnsafePointer<Float>, anchorCount: Int,
                               protos: UnsafePointer<Float>,
                               depth: AVDepthData?) -> [Detection] {
        @inline(__always) func at(_ channel: Int, _ anchor: Int) -> Float {
            boxes[channel * anchorCount + anchor]
        }

        // 1. Score filter
        var candidates: [Candidate] = []
        for a in 0..<anchorCount {
            var bestScore: Float = 0
            var bestClass = 0
            for c in 0..<classCount {
                let s = at(4 + c, a)
                if s > bestScore { bestScore = s; bestClass = c }
            }
            guard bestScore >= confidenceThreshold else { continue }
            candidates.append(Candidate(anchor: a, classIndex: bestClass, score: bestScore,
                                        cx: at(0, a), cy: at(1, a), w: at(2, a), h: at(3, a)))
        }
        candidates.sort { $0.score > $1.score }

        // 2. Greedy NMS
        var kept: [Candidate] = []
        for cand in candidates where kept.count < maxInstances {
            if kept.allSatisfy({ iou($0, cand) < iouThreshold }) {
                kept.append(cand)
            }
        }

        // 3. Masks + Detection structs
        return kept.map { cand in
            let mask = composeMask(for: cand, boxes: boxes, anchorCount: anchorCount, protos: protos)

            // Model space (top-left origin, 640 px) → Vision-normalized (bottom-left).
            let nx = CGFloat((cand.cx - cand.w / 2) / inputSize)
            let nyTop = CGFloat((cand.cy - cand.h / 2) / inputSize)
            let nw = CGFloat(cand.w / inputSize)
            let nh = CGFloat(cand.h / inputSize)
            let bbox = CGRect(x: nx, y: 1 - nyTop - nh, width: nw, height: nh)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

            let label = classNames.indices.contains(cand.classIndex)
                ? classNames[cand.classIndex] : "object"
            return Detection(
                label: label,
                confidence: cand.score,
                bbox: bbox,
                position: PositionBucket(normalizedMidX: bbox.midX),
                distanceMeters: DistanceEstimator.estimate(bbox: bbox, label: label, depth: depth),
                mask: mask
            )
        }
    }

    /// mask logits = coeffs(32) · protos(32×160×160), cropped to the box.
    private static func composeMask(for cand: Candidate, boxes: UnsafePointer<Float>,
                                    anchorCount: Int, protos: UnsafePointer<Float>) -> SegMask? {
        let planeSize = protoSize * protoSize
        var coeffs = [Float](repeating: 0, count: coeffCount)
        for k in 0..<coeffCount {
            coeffs[k] = boxes[(4 + classCount + k) * anchorCount + cand.anchor]
        }
        var logits = [Float](repeating: 0, count: planeSize)
        // y = protosᵀ(planeSize×32) · coeffs — protos stored row-major [32, planeSize].
        cblas_sgemv(CblasRowMajor, CblasTrans, Int32(coeffCount), Int32(planeSize),
                    1, protos, Int32(planeSize), coeffs, 1, 0, &logits, 1)

        // Crop to the box in proto space (640 → 160 is ÷4).
        let scale = Float(protoSize) / inputSize
        let x0 = max(0, Int((cand.cx - cand.w / 2) * scale))
        let x1 = min(protoSize, Int(((cand.cx + cand.w / 2) * scale).rounded(.up)))
        let y0 = max(0, Int((cand.cy - cand.h / 2) * scale))
        let y1 = min(protoSize, Int(((cand.cy + cand.h / 2) * scale).rounded(.up)))
        let w = x1 - x0, h = y1 - y0
        guard w > 0, h > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h)
        var columnHits = [Int](repeating: 0, count: w)
        for row in 0..<h {
            let src = (y0 + row) * protoSize + x0
            let dst = row * w
            for col in 0..<w where logits[src + col] > 0 {
                pixels[dst + col] = 1
                columnHits[col] += 1
            }
        }
        let occupancy = columnHits.map { Float($0) / Float(h) }
        return SegMask(width: w, height: h, pixels: pixels, columnOccupancy: occupancy)
    }

    private static func iou(_ a: Candidate, _ b: Candidate) -> Float {
        let ax1 = a.cx - a.w / 2, ay1 = a.cy - a.h / 2, ax2 = a.cx + a.w / 2, ay2 = a.cy + a.h / 2
        let bx1 = b.cx - b.w / 2, by1 = b.cy - b.h / 2, bx2 = b.cx + b.w / 2, by2 = b.cy + b.h / 2
        let ix = max(0, min(ax2, bx2) - max(ax1, bx1))
        let iy = max(0, min(ay2, by2) - max(ay1, by1))
        let inter = ix * iy
        let union = a.w * a.h + b.w * b.h - inter
        return union > 0 ? inter / union : 0
    }
}

private extension MLMultiArray {
    /// Contiguous typed access; float32 arrays from Core ML are contiguous.
    func withUnsafeBufferPointer<T, R>(ofType type: T.Type,
                                       _ body: (UnsafeBufferPointer<T>) -> R) -> R {
        let count = shape.reduce(1) { $0 * $1.intValue }
        return withUnsafeBytes { raw in
            body(UnsafeBufferPointer(start: raw.baseAddress?.assumingMemoryBound(to: T.self),
                                     count: count))
        }
    }
}
