import SwiftUI
import MapKit

/// Destination search + route start/stop (R13.1). Dark, big-target, VoiceOver-first.
struct NavigateView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var nav: RouteNavigator { model.router }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TelemetryText(text: "NAVIGATE · WALKING ROUTES", size: 9, color: .white.opacity(0.45))
                .accessibilityAddTraits(.isHeader)

            if nav.authorizationDenied {
                deniedCard
            } else if nav.state == .navigating || nav.state == .arrived {
                activeRouteCard
            }

            searchField

            if let error = nav.searchError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(nav.searchResults.enumerated()), id: \.offset) { _, item in
                        resultRow(item)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 24, leading: 16, bottom: 20, trailing: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .onAppear { nav.requestAuthorization() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("", text: $query, prompt: Text("Where to?").foregroundStyle(.white.opacity(0.4)))
                .focused($searchFocused)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .avCard()
                .accessibilityLabel("Destination")
                .accessibilityHint("Type a place or address, then search")

            Button {
                runSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.bgDeep)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent))
            }
            .accessibilityLabel("Search")
        }
    }

    private func runSearch() {
        searchFocused = false
        Task { await nav.search(query) }
    }

    private func resultRow(_ item: MKMapItem) -> some View {
        Button {
            dismiss()
            Task { await nav.navigate(to: item) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name ?? "Unknown place")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    if let locality = item.placemark.title {
                        Text(locality)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: "figure.walk")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            }
        }
        .accessibilityLabel("\(item.name ?? "Place"). \(item.placemark.title ?? "")")
        .accessibilityHint("Starts a walking route")
    }

    private var activeRouteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TelemetryText(text: nav.state == .arrived ? "ARRIVED" : "NAVIGATING TO",
                          size: 9, color: Theme.accent)
            Text(nav.destinationName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            Button {
                nav.stopNavigation()
            } label: {
                Text("End navigation")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .avCard(.white.opacity(0.08), stroke: .white.opacity(0.25))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .avCard()
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location access is off. Navigation needs it to guide you.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.bgDeep)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .avCard()
    }
}

/// Persistent turn-by-turn bar over the Live screen while navigating (R13.6).
struct GuidanceBar: View {
    @ObservedObject var nav: RouteNavigator

    var body: some View {
        if nav.state == .navigating || nav.state == .arrived {
            HStack(spacing: 12) {
                Image(systemName: nav.state == .arrived ? "checkmark.circle.fill" : "figure.walk")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(nav.currentInstruction.isEmpty ? nav.destinationName : nav.currentInstruction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if nav.state == .navigating {
                        TelemetryText(
                            text: "\(Int(nav.distanceToManeuver)) M TO TURN · \(Int(nav.remainingDistance)) M LEFT",
                            size: 9, color: .white.opacity(0.5))
                    }
                }
                Spacer()
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .avCard(.black.opacity(0.82), stroke: .white.opacity(0.15))
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.accent).frame(width: 3)
            }
            .accessibilityElement()
            .accessibilityLabel("Navigation")
            .accessibilityValue(nav.state == .arrived
                ? "Arrived at \(nav.destinationName)"
                : "\(nav.currentInstruction), in \(spokenWalkDistance(nav.distanceToManeuver))")
        }
    }
}
