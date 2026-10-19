import Foundation
import FirebaseFirestore

/// Groups in Firestore (rules: core/firebase/firestore-scriberocks.rules):
///   scriberocks_groups/{groupId}                  name, about, reportsToHide (moderator-created)
///   scriberocks_groups/{groupId}/members/{uid}    displayName, joinedAt, guardianApproved
///   scriberocks_groups/{groupId}/posts/{postId}   authorId, authorName, text, createdAt, reportedBy, review
///   scriberocks_reports/{reportId}                groupId, postId, postText, authorId, reporterId, reason, createdAt
///   scriberocks_users/{uid}                       termsVersion
///   scriberocks_users/{uid}/blocks/{blockedUid}   createdAt
/// A Cloud Function emails each new report to the moderator.
final class FirestoreGroupService: GroupService {
    private var db: Firestore { Firestore.firestore() }
    private var groupsCollection: CollectionReference { db.collection("scriberocks_groups") }
    private func posts(_ groupId: String) -> CollectionReference { groupsCollection.document(groupId).collection("posts") }
    private func members(_ groupId: String) -> CollectionReference { groupsCollection.document(groupId).collection("members") }
    private func user(_ userId: String) -> DocumentReference { db.collection("scriberocks_users").document(userId) }

    func groups() async throws -> [RockGroup] {
        try await groupsCollection.getDocuments().documents.map { doc in
            let d = doc.data()
            return RockGroup(id: doc.documentID, name: d["name"] as? String ?? doc.documentID, about: d["about"] as? String ?? "",
                             reportsToHide: d["reportsToHide"] as? Int ?? 2)
        }.sorted { $0.name < $1.name }
    }

    func memberships(userId: String) async throws -> Set<String> {
        // Per group, not a collection-group query: the Firebase project is shared,
        // and a {path=**}/members rule would reach other apps' collections.
        var joined = Set<String>()
        for group in try await groups() where try await members(group.id).document(userId).getDocument().exists {
            joined.insert(group.id)
        }
        return joined
    }

    func join(groupId: String, userId: String, displayName: String, guardianApproved: Bool) async throws {
        try await members(groupId).document(userId).setData([
            "uid": userId, "displayName": displayName, "joinedAt": FieldValue.serverTimestamp(), "guardianApproved": guardianApproved,
        ])
    }

    func posts(groupId: String) async throws -> [GroupPost] {
        try await posts(groupId).order(by: "createdAt", descending: true).limit(to: 200).getDocuments().documents.compactMap {
            Self.post(id: $0.documentID, groupId: groupId, data: $0.data())
        }
    }

    static func post(id: String, groupId: String, data d: [String: Any]) -> GroupPost? {
        guard let authorId = d["authorId"] as? String, let text = d["text"] as? String else { return nil }
        return GroupPost(id: id, groupId: groupId, authorId: authorId, authorName: d["authorName"] as? String ?? "Scribe", text: text,
                         createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? .now, reportedBy: d["reportedBy"] as? [String] ?? [],
                         review: (d["review"] as? String).flatMap(GroupPost.Review.init))
    }

    func post(text: String, groupId: String, userId: String, displayName: String) async throws -> GroupPost {
        let ref = posts(groupId).document()
        try await ref.setData([
            "authorId": userId, "authorName": displayName, "text": text, "createdAt": FieldValue.serverTimestamp(), "reportedBy": [String](),
        ])
        return GroupPost(id: ref.documentID, groupId: groupId, authorId: userId, authorName: displayName, text: text, createdAt: .now, reportedBy: [], review: nil)
    }

    func delete(post: GroupPost) async throws {
        try await posts(post.groupId).document(post.id).delete()
    }

    func report(post: GroupPost, reporterId: String, reason: String) async throws {
        let batch = db.batch()
        batch.updateData(["reportedBy": FieldValue.arrayUnion([reporterId])], forDocument: posts(post.groupId).document(post.id))
        batch.setData([
            "groupId": post.groupId, "postId": post.id, "postText": post.text, "authorId": post.authorId,
            "reporterId": reporterId, "reason": reason, "createdAt": FieldValue.serverTimestamp(),
        ], forDocument: db.collection("scriberocks_reports").document())
        try await batch.commit()
    }

    func blockedUsers(userId: String) async throws -> Set<String> {
        Set(try await user(userId).collection("blocks").getDocuments().documents.map(\.documentID))
    }

    func block(_ authorId: String, by userId: String) async throws {
        try await user(userId).collection("blocks").document(authorId).setData(["createdAt": FieldValue.serverTimestamp()])
    }

    func acceptedTermsVersion(userId: String) async throws -> Int? {
        try await user(userId).getDocument().data()?["termsVersion"] as? Int
    }

    func acceptTerms(version: Int, userId: String) async throws {
        try await user(userId).setData(["termsVersion": version, "termsAcceptedAt": FieldValue.serverTimestamp()], merge: true)
    }

    func deleteAllData(userId: String) async throws {
        for group in try await groups() {
            let mine = try await posts(group.id).whereField("authorId", isEqualTo: userId).getDocuments().documents
            for doc in mine { try await doc.reference.delete() }
            try await members(group.id).document(userId).delete()
        }
        for doc in try await user(userId).collection("blocks").getDocuments().documents { try await doc.reference.delete() }
    }
}
