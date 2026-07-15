import SwiftUI

/// Bounding boxes + labels over the camera feed (mockup 1a, R1.2).
/// Highest-confidence detection gets the accent box; others white, with
/// opacity graded by confidence. Tapping a box locks focus (R4.1).
struct HUDOverlay: View {
    let detections: [Detection]
    let onTap: (Detection) -> Void

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(detections.enumerated()), id: \.element.id) { index, det in
                DetectionBox(detection: det,
                             rect: viewRect(for: det.bbox, in: geo.size),
                             isPrimary: index == 0,
                             onTap: onTap)
            }

            // Center crosshair (1a).
            Rectangle()
                .stroke(.white.opacity(0.4), lineWidth: 1)
                .frame(width: 26, height: 26)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 2, height: 2)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(true)
    }
}

/// One bounding box with its label chip, approach tag, and footer.
private struct DetectionBox: View {
    let detection: Detection
    let rect: CGRect
    let isPrimary: Bool
    let onTap: (Detection) -> Void

    private var color: Color { isPrimary ? Theme.accent : .white }
    private var opacity: Double { isPrimary ? 1.0 : Double(max(0.5, detection.confidence)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(color.opacity(opacity), lineWidth: isPrimary ? 2 : 1)
            labelChip
            if isPrimary {
                TelemetryText(text: primaryFooter, size: 9, color: Theme.accent)
                    .offset(y: rect.height + 6)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .contentShape(Rectangle())
        .onTapGesture { onTap(detection) }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double tap to lock focus on this object")
    }

    /// Label chip riding the top edge: name, confidence, distance (R1.7).
    private var labelChip: some View {
        HStack(spacing: 6) {
            Text(detection.label.uppercased())
                .font(Theme.telemetry(10, weight: .bold))
            Text(String(format: "%.2f", detection.confidence))
                .font(Theme.telemetry(10, weight: .regular))
            if let d = detection.distanceMeters {
                Text(String(format: "%.1fM", d))
                    .font(Theme.telemetry(10, weight: .bold))
            }
        }
        .tracking(0.6)
        .foregroundStyle(Theme.bgDeep)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(opacity))
        .offset(y: -22)
    }

    private var primaryFooter: String {
        let arrow: String
        switch detection.position {
        case .left: arrow = "◂ LEFT"
        case .ahead: arrow = "▴ AHEAD"
        case .right: arrow = "RIGHT ▸"
        }
        if let d = detection.distanceMeters {
            return "\(arrow) · \(String(format: "%.1f", d)) M"
        }
        return arrow
    }

    private var accessibilityText: String {
        var s = "\(detection.displayName), \(detection.position.spoken)"
        if let d = detection.distanceMeters { s += ", \(spokenDistance(d))" }
        return s
    }
}

/// Persistent safe-path banner under the top telemetry (R11.3).
struct NavigationBanner: View {
    let suggestion: PathSuggestion

    var body: some View {
        HStack(spacing: 8) {
            if suggestion.isWarning { PulseDot(color: Theme.bgDeep) }
            TelemetryText(text: bannerText, size: 11,
                          color: suggestion.isWarning ? Theme.bgDeep : .white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(suggestion.isWarning ? Theme.accent : Color.black.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(.white.opacity(suggestion.isWarning ? 0 : 0.15), lineWidth: 1)
        )
        .accessibilityElement()
        .accessibilityLabel("Path guidance")
        .accessibilityValue(suggestion.spoken)
    }

    private var bannerText: String {
        var t = suggestion.display
        if suggestion.isWarning, let label = suggestion.obstacleLabel {
            t += " · \(label.uppercased())"
            if let d = suggestion.obstacleDistance {
                t += String(format: " %.1fM", d)
            }
        }
        return t
    }
}

/// L…R spatial pan indicator bar (mockups 1a/1g, R3.2).
struct PanIndicator: View {
    /// −1…+1
    let pan: Double
    var caption: String = "SPATIAL PAN"

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                TelemetryText(text: "L", size: 8, color: .white.opacity(0.5))
                Spacer()
                TelemetryText(text: caption, size: 8, color: .white.opacity(0.5))
                Spacer()
                TelemetryText(text: "R", size: 8, color: .white.opacity(0.5))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.18)).frame(height: 3)
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 9, height: 9)
                        .offset(x: (pan + 1) / 2 * max(0, geo.size.width - 9), y: -3)
                }
            }
            .frame(height: 9)
        }
        .accessibilityElement()
        .accessibilityLabel("Spatial pan indicator")
        .accessibilityValue(pan < -0.25 ? "left" : pan > 0.25 ? "right" : "center")
    }
}
