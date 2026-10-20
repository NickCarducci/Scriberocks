import SwiftUI

/// A group's posts. Share a rock (terms once, then the content filter);
/// report, block, or delete your own from each post's menu. Readers under
/// Communication Limits see approved authors; the rest collapse into one row
/// that asks a parent or guardian about those writers.
struct GroupFeedView: View {
    @StateObject private var viewModel: GroupFeedViewModel
    @EnvironmentObject private var rockStore: RockStore
    @State private var askingGuardian = false
    @State private var choosingRock = false
    @State private var showingTerms = false
    @State private var pendingText: String?
    @State private var notice: String?
    @State private var reporting: GroupPost?

    init(group: RockGroup, service: GroupService, userId: String?, displayName: String?, requiresGuardianApproval: Bool) {
        _viewModel = StateObject(wrappedValue: GroupFeedViewModel(
            group: group, service: service, userId: userId, displayName: displayName,
            requiresGuardianApproval: requiresGuardianApproval,
            approvedAmong: { await GuardianApproval.approved(among: $0) }
        ))
    }

    var body: some View {
        List {
            if viewModel.hiddenForGuardianCount > 0 {
                guardianRow
            }
            ForEach(viewModel.visiblePosts) { item in
                PostRow(item: item)
                    .contextMenu { menu(for: item.post) }
                    .swipeActions { swipe(for: item.post) }
            }
        }
        .overlay {
            if viewModel.visiblePosts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView("Nothing shared yet", image: "rock", description: Text("Share a rock to start the conversation."))
            }
        }
        .navigationTitle(viewModel.group.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Share a rock", systemImage: "square.and.arrow.up") { choosingRock = true }
                    .disabled(rockStore.rocks.isEmpty)
            }
        }
        .task { await viewModel.load() }
        .task {
            for await ids in GuardianApproval.approvals() { viewModel.guardianApproved(ids) }
        }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $choosingRock) {
            RockPicker(rocks: rockStore.rocks) { text in
                choosingRock = false
                Task { await share(text) }
            }
        }
        .sheet(isPresented: $showingTerms) {
            TermsView {
                showingTerms = false
                Task {
                    await viewModel.acceptTerms()
                    if let text = pendingText { await share(text) }
                }
            }
        }
        .confirmationDialog("Report this post?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }), titleVisibility: .visible) {
            ForEach(["Harassment or bullying", "Hate", "Threats or self-harm", "Sexual content", "Spam", "Something else"], id: \.self) { reason in
                Button(reason) {
                    if let post = reporting { Task { await viewModel.report(post, reason: reason) } }
                    reporting = nil
                }
            }
        } message: {
            Text("It's hidden for you now and reviewed by a person, usually within 24 hours.")
        }
        .alert("Groups", isPresented: Binding(get: { notice != nil || viewModel.errorMessage != nil }, set: { if !$0 { notice = nil; viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? viewModel.errorMessage ?? "")
        }
    }

    private var guardianRow: some View {
        let authors = viewModel.authorsAwaitingApproval
        let count = viewModel.hiddenForGuardianCount
        return VStack(alignment: .leading, spacing: 8) {
            Label("\(count) \(count == 1 ? "post" : "posts") from \(authors.count) \(authors.count == 1 ? "writer" : "writers") you haven't been approved to see",
                  systemImage: "person.2.badge.key")
                .font(.subheadline)
            Button {
                askingGuardian = true
                Task {
                    switch await GuardianApproval.ask(about: authors) {
                    case .sent: notice = "Request sent. Their posts appear when a parent or guardian approves."
                    case .notNeeded: viewModel.guardianNotRequired()
                    case .unavailable(let message): notice = message
                    }
                    askingGuardian = false
                }
            } label: {
                Label("Ask a parent or guardian", systemImage: "paperplane")
            }
            .buttonStyle(.bordered)
            .disabled(askingGuardian)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func menu(for post: GroupPost) -> some View {
        if viewModel.canDelete(post) {
            Button("Delete", systemImage: "trash", role: .destructive) { Task { await viewModel.delete(post) } }
        } else {
            Button("Report", systemImage: "flag") { reporting = post }
            Button("Block \(post.authorName)", systemImage: "hand.raised") { Task { await viewModel.block(post.authorId) } }
        }
    }

    @ViewBuilder
    private func swipe(for post: GroupPost) -> some View {
        if viewModel.canDelete(post) {
            Button("Delete", systemImage: "trash", role: .destructive) { Task { await viewModel.delete(post) } }
        } else {
            Button("Report", systemImage: "flag") { reporting = post }.tint(.orange)
        }
    }

    private func share(_ text: String) async {
        switch await viewModel.share(text) {
        case .posted: pendingText = nil
        case .needsTerms:
            pendingText = text
            showingTerms = true
        case .needsSignIn: notice = "Sign in on the Profile tab to share."
        case .flagged(let reason): notice = reason
        case .failed(let message): notice = message
        }
    }
}

private struct PostRow: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.post.authorName).font(.subheadline.weight(.semibold))
                Spacer()
                Text(item.post.createdAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            Text(item.post.text)
            if item.visibility == .awaitingReview {
                Label("Hidden from others while it's reviewed", systemImage: "eye.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Actions are in the menu: touch and hold")
    }
}

private struct RockPicker: View {
    let rocks: [Rock]
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(rocks) { rock in
                Button { pick(rock.text) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rock.text).lineLimit(3).foregroundStyle(.primary)
                        if rock.isDiamond { Label("Final draft", systemImage: "diamond.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Share a rock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct TermsView: View {
    let agree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(CommunityTerms.text).padding()
            }
            .navigationTitle("Community terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Agree", action: agree) }
            }
        }
    }
}
