import Foundation
import MapKit
import CoreLocation
import Combine

/// GPS walking navigation with turn-by-turn guidance (R13).
/// Routes come from MapKit (`MKDirections`, walking only); the guidance loop is
/// ours: distance-to-maneuver thresholds drive advance/immediate spoken cues,
/// off-route detection triggers a reroute, proximity to the route end arrival.
@MainActor
final class RouteNavigator: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case routing
        case navigating
        case arrived
    }

    // Guidance tunables (R13.3–R13.5)
    static let advanceCueDistance: CLLocationDistance = 50
    static let immediateCueDistance: CLLocationDistance = 12
    static let offRouteDistance: CLLocationDistance = 30
    static let arrivalDistance: CLLocationDistance = 15
    static let rerouteCooldown: TimeInterval = 20

    @Published private(set) var state: State = .idle
    @Published private(set) var destinationName = ""
    @Published private(set) var currentInstruction = ""
    @Published private(set) var distanceToManeuver: CLLocationDistance = 0
    @Published private(set) var remainingDistance: CLLocationDistance = 0
    @Published private(set) var authorizationDenied = false
    @Published private(set) var searchResults: [MKMapItem] = []
    @Published var searchError: String?

    /// Wired to SpeechService by AppModel: (sentence, interrupt).
    var speak: ((String, Bool) -> Void)?

    private let manager = CLLocationManager()
    private var route: MKRoute?
    private var routePoints: [MKMapPoint] = []
    private var destination: MKMapItem?
    private var stepIndex = 0
    private var advanceCueFired = false
    private var lastRerouteAt = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 3
    }

    // MARK: - Permissions (R13.7)

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: authorizationDenied = true
        default: authorizationDenied = false
        }
    }

    // MARK: - Destination search (R13.1)

    func search(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searchError = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let loc = manager.location {
            request.region = MKCoordinateRegion(center: loc.coordinate,
                                                latitudinalMeters: 5_000,
                                                longitudinalMeters: 5_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems
            if response.mapItems.isEmpty { searchError = "No places found for “\(query)”." }
        } catch {
            searchResults = []
            searchError = "Search failed. Check your connection."
        }
    }

    // MARK: - Routing (R13.2)

    func navigate(to item: MKMapItem) async {
        state = .routing
        destination = item
        destinationName = item.name ?? "Destination"
        do {
            let route = try await walkingRoute(to: item)
            start(route: route)
            let dist = spokenWalkDistance(route.distance)
            let mins = max(1, Int(route.expectedTravelTime / 60))
            speak?("Starting walking route to \(destinationName). \(dist), about \(mins) minute\(mins == 1 ? "" : "s"). \(firstInstruction())", true)
        } catch {
            state = .idle
            searchError = "No walking route found."
            speak?("I couldn't find a walking route to \(destinationName).", false)
        }
    }

    private func walkingRoute(to item: MKMapItem) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = item
        request.transportType = .walking // never driving (R13.2)
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "AudioVision", code: 1)
        }
        return route
    }

    private func start(route: MKRoute) {
        self.route = route
        routePoints = Array(UnsafeBufferPointer(start: route.polyline.points(),
                                                count: route.polyline.pointCount))
        stepIndex = 0
        advanceCueFired = false
        remainingDistance = route.distance
        currentInstruction = firstInstruction()
        state = .navigating
        manager.startUpdatingLocation()
        advanceToNextMeaningfulStep()
    }

    func stopNavigation(announce: Bool = true) {
        if announce, state == .navigating { speak?("Navigation ended.", false) }
        state = .idle
        route = nil
        routePoints = []
        destination = nil
        currentInstruction = ""
        manager.stopUpdatingLocation()
    }

    // MARK: - Guidance loop (R13.3–R13.5)

    private func handle(location: CLLocation) {
        guard state == .navigating, let route else { return }
        let here = MKMapPoint(location.coordinate)

        // Arrival (R13.5)
        if let last = routePoints.last, here.distance(to: last) < Self.arrivalDistance {
            state = .arrived
            currentInstruction = "Arrived"
            speak?("You have arrived at \(destinationName).", true)
            manager.stopUpdatingLocation()
            return
        }

        // Off-route (R13.4)
        let deviation = Self.nearestDistance(from: here, toPolyline: routePoints)
        if deviation > Self.offRouteDistance {
            if Date().timeIntervalSince(lastRerouteAt) > Self.rerouteCooldown, let destination {
                lastRerouteAt = Date()
                speak?("You've left the route. Finding a new way.", true)
                Task { await navigate(to: destination) }
            }
            return
        }

        // Progress + cues for the current maneuver
        let steps = route.steps
        guard stepIndex < steps.count else { return }
        let maneuverPoint = MKMapPoint(steps[stepIndex].polyline.coordinate)
        let d = here.distance(to: maneuverPoint)
        distanceToManeuver = d
        remainingDistance = max(0, d + remaining(after: stepIndex))

        if d < Self.immediateCueDistance {
            speak?(steps[stepIndex].instructions, true)
            stepIndex += 1
            advanceCueFired = false
            advanceToNextMeaningfulStep()
        } else if d < Self.advanceCueDistance, !advanceCueFired {
            advanceCueFired = true
            speak?("In \(spokenWalkDistance(d)), \(lowercasedFirst(steps[stepIndex].instructions))", false)
        }
    }

    /// Skips steps with empty instructions (MapKit's leading "proceed" stub).
    private func advanceToNextMeaningfulStep() {
        guard let route else { return }
        while stepIndex < route.steps.count,
              route.steps[stepIndex].instructions.isEmpty {
            stepIndex += 1
        }
        if stepIndex < route.steps.count {
            currentInstruction = route.steps[stepIndex].instructions
        } else {
            currentInstruction = "Continue to \(destinationName)"
        }
    }

    private func firstInstruction() -> String {
        route?.steps.first(where: { !$0.instructions.isEmpty })?.instructions
            ?? "Head toward \(destinationName)."
    }

    private func remaining(after index: Int) -> CLLocationDistance {
        guard let route else { return 0 }
        return route.steps.dropFirst(index + 1).reduce(0) { $0 + $1.distance }
    }

    // MARK: - Geometry (unit-testable)

    static func nearestDistance(from point: MKMapPoint, toPolyline points: [MKMapPoint]) -> CLLocationDistance {
        guard !points.isEmpty else { return .infinity }
        var best = CLLocationDistance.infinity
        for i in 0..<max(1, points.count - 1) {
            let d = points.count == 1
                ? point.distance(to: points[0])
                : distance(from: point, toSegment: points[i], points[i + 1])
            best = min(best, d)
        }
        return best
    }

    static func distance(from p: MKMapPoint, toSegment a: MKMapPoint, _ b: MKMapPoint) -> CLLocationDistance {
        let abx = b.x - a.x, aby = b.y - a.y
        let lenSq = abx * abx + aby * aby
        guard lenSq > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq))
        return p.distance(to: MKMapPoint(x: a.x + t * abx, y: a.y + t * aby))
    }
}

extension RouteNavigator: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.handle(location: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationDenied = status == .denied || status == .restricted
        }
    }
}

/// "500 meters" / "1.2 kilometers" — for both cues and the guidance bar.
func spokenWalkDistance(_ meters: CLLocationDistance) -> String {
    if meters < 1_000 {
        let rounded = max(5, Int((meters / 5).rounded()) * 5)
        return "\(rounded) meters"
    }
    return String(format: "%.1f kilometers", meters / 1_000)
}

private func lowercasedFirst(_ s: String) -> String {
    guard let first = s.first else { return s }
    return first.lowercased() + s.dropFirst()
}
