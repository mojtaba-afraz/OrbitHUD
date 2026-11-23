import Foundation

public enum SharedSnapshotStorage {
    public static var sharedSnapshotURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("AntigravityUsageWidget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("latest_usage_snapshot.json")
    }

    public static func save(_ snapshot: AntigravityUsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: sharedSnapshotURL, options: .atomic)
        }
    }

    public static func load() -> AntigravityUsageSnapshot? {
        guard let data = try? Data(contentsOf: sharedSnapshotURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AntigravityUsageSnapshot.self, from: data)
    }
}
