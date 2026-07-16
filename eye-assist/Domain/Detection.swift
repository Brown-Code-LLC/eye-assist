import Foundation
import CoreGraphics

/// Horizontal position bucket derived from the bounding-box center (R1.4).
enum PositionBucket: String, Codable {
    case left = "LEFT"
    case ahead = "AHEAD"
    case right = "RIGHT"

    init(normalizedMidX x: CGFloat) {
        switch x {
        case ..<0.38: self = .left
        case 0.62...: self = .right
        default: self = .ahead
        }
    }

    var spoken: String {
        switch self {
        case .left: return "on your left"
        case .ahead: return "ahead"
        case .right: return "on your right"
        }
    }

    var short: String { rawValue }
}

/// Settings filter groups over the COCO-80 label set (R6.4).
enum FilterCategory: String, Codable, CaseIterable {
    case people
    case vehicles
    case street
    case furniture
    case smallItems
    case other

    static let labelMap: [String: FilterCategory] = {
        var map: [String: FilterCategory] = [:]
        map["person"] = .people
        for l in ["bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat"] {
            map[l] = .vehicles
        }
        // Everyday street & pedestrian-lane objects (COCO street classes).
        for l in ["traffic light", "stop sign", "fire hydrant", "parking meter", "bench"] {
            map[l] = .street
        }
        for l in ["chair", "couch", "bed", "dining table", "toilet", "potted plant", "refrigerator", "oven", "sink", "tv"] {
            map[l] = .furniture
        }
        for l in ["bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl",
                  "backpack", "umbrella", "handbag", "tie", "suitcase", "cell phone",
                  "book", "scissors", "remote", "keyboard", "mouse", "laptop", "clock", "vase", "toothbrush"] {
            map[l] = .smallItems
        }
        return map
    }()

    /// Safety-critical street labels announced ahead of others (R6.7).
    static let priorityLabels: Set<String> = [
        "traffic light", "stop sign", "person", "car", "bus", "truck",
        "bicycle", "motorcycle", "train", "fire hydrant", "dog",
    ]

    static func category(for label: String) -> FilterCategory {
        labelMap[label.lowercased()] ?? .other
    }

    var displayName: String {
        switch self {
        case .people: return "People"
        case .vehicles: return "Vehicles"
        case .street: return "Street & signals"
        case .furniture: return "Furniture & obstacles"
        case .smallItems: return "Small items"
        case .other: return "Other"
        }
    }

    var subtitle: String {
        switch self {
        case .people: return "person"
        case .vehicles: return "car, bicycle, bus, truck"
        case .street: return "traffic light, stop sign, hydrant, bench"
        case .furniture: return "chair, table, couch, bed"
        case .smallItems: return "cup, phone, bag, bottle"
        case .other: return "animals, everything else"
        }
    }
}

/// Binary instance mask cropped to a detection's bbox (R14): row-major grid
/// in proto resolution, row 0 = top of the box.
struct SegMask: Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    /// Fraction of set pixels per column (0…1); length == width.
    let columnOccupancy: [Float]
}

/// One detected object in the current frame (design.md §2).
struct Detection: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let confidence: Float
    /// Normalized rect in upright-image space, origin at BOTTOM-left (Vision convention).
    let bbox: CGRect
    let position: PositionBucket
    let distanceMeters: Double?
    /// Instance mask when the segmentation model is active (R14); nil on the
    /// box-only fallback pipeline.
    var mask: SegMask?

    /// True horizontal extent (normalized x) from mask columns >10% occupied;
    /// falls back to the bbox interval without a mask (R14.3).
    var footprintXInterval: ClosedRange<CGFloat> {
        guard let mask, mask.width > 0 else { return bbox.minX...bbox.maxX }
        var first = -1, last = -1
        for (i, f) in mask.columnOccupancy.enumerated() where f > 0.1 {
            if first < 0 { first = i }
            last = i
        }
        guard first >= 0 else { return bbox.minX...bbox.maxX }
        let lo = bbox.minX + CGFloat(first) / CGFloat(mask.width) * bbox.width
        let hi = bbox.minX + CGFloat(last + 1) / CGFloat(mask.width) * bbox.width
        return lo...min(hi, bbox.maxX)
    }

    var category: FilterCategory { FilterCategory.category(for: label) }
    var displayName: String { label.capitalized }

    /// Physical obstacle relevant to path planning (R11.1): anything but small
    /// handheld items, close enough to matter and big enough to be real.
    var isNavObstacle: Bool {
        category != .smallItems
            && (distanceMeters ?? .infinity) < 2.5
            && bbox.height > 0.12
    }

    /// e.g. "0.94 · LEFT · 1.2 M"
    var telemetryLine: String {
        var parts = [String(format: "%.2f", confidence), position.short]
        if let d = distanceMeters { parts.append(String(format: "%.1f M", d)) }
        return parts.joined(separator: " · ")
    }

    static func == (lhs: Detection, rhs: Detection) -> Bool { lhs.id == rhs.id }
}

/// Natural-language distance for narration (design.md §3).
func spokenDistance(_ meters: Double) -> String {
    switch meters {
    case ..<0.75: return "half a meter"
    case ..<1.35: return "one meter"
    case ..<1.85: return "one and a half meters"
    case ..<10:
        let rounded = (meters * 2).rounded() / 2
        if rounded == rounded.rounded() { return "\(Int(rounded)) meters" }
        return "\(Int(rounded)) and a half meters"
    default: return "far away"
    }
}
