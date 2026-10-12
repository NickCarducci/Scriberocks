import Foundation
import FirebaseFirestore

/// Stores rocks at `scriberocks_users/{uid}/rocks/{rockId}`.
/// Namespaced so it can share a Firebase project with other apps.
struct FirestoreRockSyncService: RockSyncService {
    private var db: Firestore { Firestore.firestore() }

    private func userDocument(_ userId: String) -> DocumentReference {
        db.collection("scriberocks_users").document(userId)
    }

    private func rocksCollection(_ userId: String) -> CollectionReference {
        userDocument(userId).collection("rocks")
    }

    func fetchRocks(userId: String) async throws -> RemoteRocks {
        let snapshot = try await rocksCollection(userId).getDocuments()
        var remote = RemoteRocks()
        for document in snapshot.documents {
            let data = document.data()
            guard let id = UUID(uuidString: document.documentID) else { continue }
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
            if data["deleted"] as? Bool == true {
                remote.tombstones[id] = updatedAt ?? .distantPast
                continue
            }
            guard let text = data["text"] as? String,
                  let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else { continue }
            remote.rocks.append(Rock(
                id: id,
                text: text,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDiamond: data["isDiamond"] as? Bool ?? false
            ))
        }
        return remote
    }

    func upsert(_ rock: Rock, userId: String) async throws {
        try await rocksCollection(userId).document(rock.id.uuidString).setData([
            "text": rock.text,
            "createdAt": Timestamp(date: rock.createdAt),
            "updatedAt": Timestamp(date: rock.updatedAt),
            "isDiamond": rock.isDiamond,
        ])
    }

    func delete(rockId: UUID, userId: String) async throws {
        try await rocksCollection(userId).document(rockId.uuidString).setData([
            "deleted": true,
            "updatedAt": Timestamp(date: .now),
        ], merge: true)
    }

    func deleteAllData(userId: String) async throws {
        let snapshot = try await rocksCollection(userId).getDocuments()
        // Firestore batches cap at 500 writes.
        for chunk in stride(from: 0, to: snapshot.documents.count, by: 450) {
            let batch = db.batch()
            for document in snapshot.documents[chunk..<min(chunk + 450, snapshot.documents.count)] {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
        }
        try await userDocument(userId).delete()
    }
}
