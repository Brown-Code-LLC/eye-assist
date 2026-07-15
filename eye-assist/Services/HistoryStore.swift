import Foundation
import Combine

/// Session log of announced detections, persisted as JSON (R5.*).
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var sessionStart = Date()

    private static let cap = 200
    private var saveTask: Task<Void, Never>?

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    func beginSession() {
        sessionStart = Date()
    }

    func add(_ detection: Detection) {
        let entry = HistoryEntry(
            label: detection.label,
            confidence: detection.confidence,
            position: detection.position,
            distanceMeters: detection.distanceMeters,
            date: Date()
        )
        entries.insert(entry, at: 0) // newest first, like mockup 1f
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        scheduleSave()
    }

    var sessionHeader: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "SESSION · TODAY \(f.string(from: sessionStart))–\(f.string(from: Date()))"
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [entries] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(entries) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = saved
    }
}
