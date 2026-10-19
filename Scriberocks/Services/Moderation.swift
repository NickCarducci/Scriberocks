import Foundation

/// How a post appears to one viewer.
nonisolated enum PostVisibility: Equatable, Sendable {
    case shown
    /// The viewer's own post, hidden from others pending review.
    case awaitingReview
    case hidden
}

/// Whether joining a group can happen now or needs a guardian's OK.
nonisolated enum JoinStep: Equatable, Sendable {
    case join
    case askGuardian
}

/// App Review Guideline 1.2 safeguards, as pure rules: reports hide a post at
/// once for the reporter and for everyone at the group's threshold until the
/// moderator keeps it; blocked authors are hidden. Minors (or anyone under
/// Communication Limits) join groups with a guardian's approval rather than
/// getting a reduced app.
nonisolated enum Moderation {
    static func visibility(of post: GroupPost, viewer: String?, blocked: Set<String>, reportsToHide: Int) -> PostVisibility {
        if blocked.contains(post.authorId) { return .hidden }
        if let viewer, post.reportedBy.contains(viewer) { return .hidden }
        let hiddenByReports = post.review != .kept && Set(post.reportedBy).count >= max(reportsToHide, 1)
        guard hiddenByReports else { return .shown }
        return post.authorId == viewer ? .awaitingReview : .hidden
    }

    static func joinStep(requiresGuardianApproval: Bool, guardianApproved: Bool) -> JoinStep {
        requiresGuardianApproval && !guardianApproved ? .askGuardian : .join
    }
}
