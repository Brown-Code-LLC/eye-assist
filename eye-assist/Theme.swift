import SwiftUI

/// Design tokens from the AudioVision mockups (specs/design.md §4).
/// OLED black + clinical white, one green accent, 2pt corners,
/// system sans for prose + monospaced for telemetry.
enum Theme {
    // oklch(0.75 0.18 150) ≈ #40CC6D
    static let accent = Color(red: 0.251, green: 0.80, blue: 0.427)
    static let accentDark = Color(red: 0.0, green: 0.549, blue: 0.184) // oklch(0.55 0.18 150)
    static let bg = Color(red: 0.055, green: 0.059, blue: 0.063)       // #0E0F10
    static let bgDeep = Color(red: 0.039, green: 0.039, blue: 0.039)   // #0A0A0A
    static let card = Color(red: 0.078, green: 0.086, blue: 0.094)     // #141618
    static let radius: CGFloat = 2

    static func telemetry(_ size: CGFloat = 10, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Monospaced UPPERCASE telemetry label, e.g. "YOLO11N · 31 FPS".
struct TelemetryText: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = .white

    var body: some View {
        Text(text.uppercased())
            .font(Theme.telemetry(size))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// The mockups' `av-pulse` animation (opacity 1 ↔ 0.35, 1.4s).
struct PulseDot: View {
    var color: Color = Theme.accent
    var size: CGFloat = 6
    @State private var dim = false

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

/// Animated speaking waveform (narration bar, mockup 1a).
struct Waveform: View {
    var active: Bool
    var color: Color = Theme.accent
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 22)
                    .scaleEffect(y: active ? (phase ? [0.4, 1, 0.55, 0.85][i] : [1, 0.5, 0.9, 0.35][i]) : 0.3,
                                 anchor: .bottom)
                    .animation(.easeInOut(duration: 0.35).delay(Double(i) * 0.08), value: phase)
            }
        }
        .frame(height: 22)
        .onAppear { startPulse() }
    }

    private func startPulse() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            phase.toggle()
        }
    }
}

extension View {
    /// 2pt-radius card with hairline stroke, per mockups.
    func avCard(_ fill: Color = Theme.card, stroke: Color = .white.opacity(0.1)) -> some View {
        background(RoundedRectangle(cornerRadius: Theme.radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(stroke, lineWidth: 1))
    }
}
