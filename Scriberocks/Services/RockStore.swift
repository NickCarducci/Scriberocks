import Foundation
import Combine

/// Owns the user's rocks. The JSON file on device is the source of truth;
/// when a user is signed in, every change is mirrored to `RockSyncService`.
final class RockStore: ObservableObject {
    /// Newest first.
    @Published private(set) var rocks: [Rock] = []
    @Published private(set) var isSyncing = false
    @Published var syncError: String?

    /// Key the 1.0–1.5 app stored plain strings under.
    static let legacyDefaultsKey = "ROCKS"

    private let fileURL: URL
    private let defaults: UserDefaults
    private let sync: RockSyncService
    private var userId: String?

    init(
        sync: RockSyncService,
        fileURL: URL = RockStore.defaultFileURL,
        defaults: UserDefaults = .standard
    ) {
        self.sync = sync
        self.fileURL = fileURL
        self.defaults = defaults
        load()
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "rocks.json")
    }

    // MARK: - Mutations

    @discardableResult
    func add(text: String) -> Rock? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let rock = Rock(text: trimmed)
        rocks.insert(rock, at: 0)
        persist()
        push(rock)
        return rock
    }

    func update(_ rock: Rock) {
        guard let index = rocks.firstIndex(where: { $0.id == rock.id }),
              rocks[index] != rock else { return }
        var updated = rock
        updated.updatedAt = .now
        rocks[index] = updated
        persist()
        push(updated)
    }

    func toggleDiamond(_ rock: Rock) {
        var toggled = rock
        toggled.isDiamond.toggle()
        update(toggled)
    }

    func delete(_ ids: Set<UUID>) {
        rocks.removeAll { ids.contains($0.id) }
        persist()
        guard let userId else { return }
        Task {
            for id in ids {
                do { try await sync.delete(rockId: id, userId: userId) }
                catch { syncError = error.localizedDescription }
            }
        }
    }

    // MARK: - Account

    /// Called whenever the signed-in user changes. Signing in merges the
    /// device's rocks with the account's backup; signing out keeps the
    /// device copy.
    func setUser(_ newUserId: String?) async {
        guard newUserId != userId else { return }
        userId = newUserId
        await refresh()
    }

    /// Pulls the account's rocks (including edits made on the web) and
    /// pushes anything this device has that the server doesn't.
    func refresh() async {
        guard let userId, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let remote = try await sync.fetchRocks(userId: userId)
            let merged = Self.merge(local: rocks, remote: remote)
            if merged.rocks != rocks {
                rocks = merged.rocks
                persist()
            }
            for rock in merged.needsUpload {
                try await sync.upsert(rock, userId: userId)
            }
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Last-write-wins merge by `updatedAt`. A tombstone newer than the local
    /// copy deletes it. Returns the merged list (newest first) and the rocks
    /// the server is missing or has an older copy of.
    nonisolated static func merge(local: [Rock], remote: RemoteRocks) -> (rocks: [Rock], needsUpload: [Rock]) {
        let remoteByID = Dictionary(remote.rocks.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        var mergedByID = remoteByID
        var needsUpload: [Rock] = []
        for rock in local {
            if let server = remoteByID[rock.id], server.updatedAt >= rock.updatedAt { continue }
            if let deletedAt = remote.tombstones[rock.id], deletedAt >= rock.updatedAt { continue }
            mergedByID[rock.id] = rock
            needsUpload.append(rock)
        }
        let merged = mergedByID.values.sorted { $0.createdAt > $1.createdAt }
        return (merged, needsUpload)
    }

    // MARK: - Persistence

    private func push(_ rock: Rock) {
        guard let userId else { return }
        Task {
            do { try await sync.upsert(rock, userId: userId) }
            catch { syncError = error.localizedDescription }
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Rock].self, from: data) {
            rocks = decoded
            return
        }
        migrateLegacyRocks()
    }

    /// 1.x stored `[String]` under "ROCKS", appended oldest→newest, with no
    /// dates. Keep that order by spacing createdAt one second apart.
    private func migrateLegacyRocks() {
        guard let legacy = defaults.array(forKey: Self.legacyDefaultsKey) as? [String],
              !legacy.isEmpty else { return }
        let now = Date.now
        rocks = legacy.enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { offset, text in
                Rock(text: text, createdAt: now.addingTimeInterval(TimeInterval(offset - legacy.count)))
            }
            .reversed()
        if persist() {
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(rocks)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            syncError = "Couldn't save on this device: \(error.localizedDescription)"
            return false
        }
    }
}
