import SwiftUI

/// Groups are forums. Signed-in members join and share rocks; guardian
/// approval, where it applies, is per author inside a group.
struct GroupsView: View {
    @StateObject private var viewModel: GroupsViewModel
    @EnvironmentObject private var childSafety: ChildSafetyManager
    @State private var notice: String?
    @State private var path: [RockGroup] = []
    let service: GroupService

    init(service: GroupService, userId: String?, displayName: String?) {
        self.service = service
        _viewModel = StateObject(wrappedValue: GroupsViewModel(service: service, userId: userId, displayName: displayName))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.userId == nil {
                    ContentUnavailableView("Sign in to join groups", systemImage: "person.3",
                                           description: Text("Groups are where you share rocks with other writers. Sign in on the Profile tab."))
                } else if viewModel.groups.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView("No groups yet", systemImage: "person.3")
                } else {
                    list
                }
            }
            .navigationTitle("Groups")
            .navigationDestination(for: RockGroup.self) { group in
                GroupFeedView(group: group, service: service, userId: viewModel.userId, displayName: viewModel.displayName,
                              requiresGuardianApproval: requiresGuardianApproval,
                              postingApproved: { [childSafety] in childSafety.postingApproved },
                              recordPostingApproval: { method in
                                  childSafety.markPostingApproved()
                                  await viewModel.recordPostingApproval(method: method)
                              })
            }
        }
        .task {
            await viewModel.load()
            #if DEBUG
            // Screenshot/QA hook: `-openGroup <id>` opens a group.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-openGroup"), i + 1 < args.count, let g = viewModel.groups.first(where: { $0.id == args[i + 1] }) {
                path = [g]
            }
            #endif
        }
        .task {
            // The approval lives with the account: load it, and record whether a
            // guardian control applies (the rules require approval then).
            if await viewModel.syncPostingApproval(requiresGuardianApproval: requiresGuardianApproval,
                                                   locallyApproved: childSafety.postingApproved) {
                childSafety.markPostingApproved()
            }
        }
        .task {
            // A guardian's answer to "Ask to post" (sent in Messages) can arrive any time.
            for await approved in PostingApproval.answers() where approved {
                childSafety.markPostingApproved()
                await viewModel.recordPostingApproval(method: .ask)
            }
        }
        .alert("Groups", isPresented: Binding(get: { notice != nil || viewModel.errorMessage != nil }, set: { if !$0 { notice = nil; viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? viewModel.errorMessage ?? "")
        }
    }

    private var requiresGuardianApproval: Bool {
        #if DEBUG
        // Screenshot/QA hook: `-guardedReader` reads as someone under Communication Limits.
        if ProcessInfo.processInfo.arguments.contains("-guardedReader") { return true }
        #endif
        return childSafety.requiresGuardianApproval
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.groups) { group in
                    if viewModel.isMember(group.id) {
                        NavigationLink(value: group) { row(group, member: true) }
                    } else {
                        HStack {
                            row(group, member: false)
                            Spacer()
                            Button("Join") { Task { await join(group) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            } footer: {
                Text("Report a post from its menu. Concerns: \(CommunityTerms.contact)")
            }
        }
        .refreshable { await viewModel.load() }
    }

    private func row(_ group: RockGroup, member: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.name).font(.headline)
            if !group.about.isEmpty {
                Text(group.about).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(member ? "Opens the group" : "")
    }

    private func join(_ group: RockGroup) async {
        switch await viewModel.join(group) {
        case .joined: break
        case .needsSignIn: notice = "Sign in on the Profile tab to join groups."
        case .failed(let message): notice = message
        }
    }
}

