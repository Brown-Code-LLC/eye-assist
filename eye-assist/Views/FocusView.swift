import SwiftUI

/// Focus mode chrome (mockup 1g, R4): rendered over the live camera when an
/// object is locked. Stat tiles, pan bar with tracking tone, guide/unlock.
struct FocusView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let focus = model.focus {
            let det = focus.detection
            let pan = Double(det.bbox.midX) * 2 - 1

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 7) {
                        PulseDot()
                        TelemetryText(text: focus.lostSince == nil ? "FOCUS MODE · TRACKING" : "FOCUS MODE · LOST",
                                      size: 9, color: focus.lostSince == nil ? Theme.accent : .white.opacity(0.6))
                    }
                    Spacer()
                    TelemetryText(text: "\(model.detector.modelName) · \(String(format: "%.2f", det.confidence))",
                                  size: 9, color: .white.opacity(0.4))
                }
                .padding(.top, 60)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    Text(det.displayName)
                        .font(.system(size: 44, weight: .bold))
                        .kerning(-1)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text("Audio locked to this object. Others are silenced.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }

                HStack(spacing: 8) {
                    statTile("DISTANCE",
                             det.distanceMeters.map { String(format: "%.1f m", $0) } ?? "—")
                    statTile("POSITION", det.position.rawValue.capitalized)
                    statTile("TONE", "\(model.tone.displayFrequency) Hz", valueColor: Theme.accent)
                }

                PanIndicator(pan: pan, caption: "PAN — TONE FOLLOWS OBJECT")

                HStack(spacing: 8) {
                    Button {
                        model.toggleGuidance()
                    } label: {
                        Text(focus.guiding ? "Stop guiding" : "Guide me to it")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.bgDeep)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent))
                    }
                    .accessibilityHint("Plays a tracking tone and speaks directions to the object")

                    Button {
                        model.unlock()
                    } label: {
                        Text("Unlock")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 110, height: 56)
                            .avCard(.white.opacity(0.08), stroke: .white.opacity(0.25))
                    }
                    .accessibilityHint("Exits focus mode and resumes normal narration")
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
            .background(
                // Darken everything but the locked object's box.
                GeometryReader { geo in
                    let rect = viewRect(for: det.bbox, in: geo.size)
                    ZStack {
                        Color.black.opacity(0.55)
                        Rectangle()
                            .stroke(Theme.accent, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            )
        }
    }

    private func statTile(_ label: String, _ value: String, valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TelemetryText(text: label, size: 8, color: .white.opacity(0.4))
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .avCard()
        .accessibilityElement()
        .accessibilityLabel("\(label): \(value)")
    }
}
