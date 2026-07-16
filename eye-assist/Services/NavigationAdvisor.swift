import Foundation
import CoreGraphics

/// One stabilized safe-path suggestion derived from the current detections (R11).
struct PathSuggestion: Equatable {
    enum Kind: Equatable {
        case clear
        case moveLeft
        case moveRight
        case straightCaution
        case stop
    }

    let kind: Kind
    /// Nearest blocking obstacle, for speech (R11.6).
    let obstacleLabel: String?
    let obstacleDistance: Double?

    static let clear = PathSuggestion(kind: .clear, obstacleLabel: nil, obstacleDistance: nil)

    /// HUD banner text (monospace, mockup style).
    var display: String {
        switch kind {
        case .clear: return "PATH CLEAR"
        case .moveLeft: return "◂ MOVE LEFT"
        case .moveRight: return "MOVE RIGHT ▸"
        case .straightCaution: return "▴ STRAIGHT · CAUTION"
        case .stop: return "■ STOP"
        }
    }

    var isWarning: Bool { kind != .clear }

    /// Spoken form, naming the nearest obstacle (R11.6).
    var spoken: String {
        let obstacle: String? = obstacleLabel.map { label in
            var s = label.capitalized
            if let d = obstacleDistance { s += " ahead, \(spokenDistance(d))" }
            return s
        }
        switch kind {
        case .clear:
            return "Path clear."
        case .moveLeft:
            return [obstacle, "Move left."].compactMap { $0 }.joined(separator: ". ")
        case .moveRight:
            return [obstacle, "Move right."].compactMap { $0 }.joined(separator: ". ")
        case .straightCaution:
            return "Continue straight, watch \(obstacleLabel.map { "the \($0)" } ?? "the side")."
        case .stop:
            return "Stop. " + (obstacle.map { $0 + ". " } ?? "") + "Obstacles blocking the way."
        }
    }

    /// Short avoidance hint appended to object announcements (R11.5).
    var avoidanceHint: String? {
        switch kind {
        case .moveLeft: return "move left to avoid"
        case .moveRight: return "move right to avoid"
        case .stop: return "stop"
        default: return nil
        }
    }
}

/// Splits the frame into three lanes, marks lanes blocked by near obstacles,
/// and derives one suggestion with hysteresis so advice doesn't flicker (R11).
final class NavigationAdvisor {
    private static let laneRanges: [ClosedRange<CGFloat>] = [0...0.38, 0.38...0.62, 0.62...1]
    private static let minOverlapFraction: CGFloat = 0.2
    private static let persistence: TimeInterval = 0.6

    private(set) var current: PathSuggestion = .clear
    private var candidate: PathSuggestion?
    private var candidateSince = Date.distantPast

    /// Feed each frame's detections; returns the stabilized suggestion.
    func update(_ detections: [Detection]) -> PathSuggestion {
        let proposed = Self.compute(detections)
        if proposed == current {
            candidate = nil
            return current
        }
        if proposed != candidate {
            candidate = proposed
            candidateSince = Date()
            return current
        }
        // STOP is safety-critical: adopt immediately (R11.4 exception).
        if proposed.kind == .stop || Date().timeIntervalSince(candidateSince) >= Self.persistence {
            current = proposed
            candidate = nil
        }
        return current
    }

    static func compute(_ detections: [Detection]) -> PathSuggestion {
        let obstacles = detections.filter(\.isNavObstacle)
        guard !obstacles.isEmpty else { return .clear }

        // Lane blocked when an obstacle overlaps ≥20% of its width (R11.1).
        // The obstacle's extent is its mask-true footprint, not the bbox, so
        // free space beside irregular shapes isn't overstated (R14.3).
        var laneObstacles: [[Detection]] = [[], [], []]
        for obstacle in obstacles {
            let footprint = obstacle.footprintXInterval
            for (i, lane) in laneRanges.enumerated() {
                let overlap = min(footprint.upperBound, lane.upperBound)
                    - max(footprint.lowerBound, lane.lowerBound)
                if overlap >= (lane.upperBound - lane.lowerBound) * minOverlapFraction {
                    laneObstacles[i].append(obstacle)
                }
            }
        }
        let leftBlocked = !laneObstacles[0].isEmpty
        let centerBlocked = !laneObstacles[1].isEmpty
        let rightBlocked = !laneObstacles[2].isEmpty

        func nearest(_ lanes: [Int]) -> Detection? {
            lanes.flatMap { laneObstacles[$0] }
                .min { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        }

        if !centerBlocked {
            if leftBlocked || rightBlocked {
                let side = nearest([0, 2])
                return PathSuggestion(kind: .straightCaution,
                                      obstacleLabel: side?.label,
                                      obstacleDistance: side?.distanceMeters)
            }
            return .clear
        }

        let center = nearest([1])
        switch (leftBlocked, rightBlocked) {
        case (false, false):
            // Both sides free: send the user toward the side farther from the
            // center obstacle's mass.
            let goLeft = (center?.bbox.midX ?? 0.5) >= 0.5
            return PathSuggestion(kind: goLeft ? .moveLeft : .moveRight,
                                  obstacleLabel: center?.label,
                                  obstacleDistance: center?.distanceMeters)
        case (false, true):
            return PathSuggestion(kind: .moveLeft,
                                  obstacleLabel: center?.label,
                                  obstacleDistance: center?.distanceMeters)
        case (true, false):
            return PathSuggestion(kind: .moveRight,
                                  obstacleLabel: center?.label,
                                  obstacleDistance: center?.distanceMeters)
        case (true, true):
            return PathSuggestion(kind: .stop,
                                  obstacleLabel: center?.label,
                                  obstacleDistance: center?.distanceMeters)
        }
    }
}
