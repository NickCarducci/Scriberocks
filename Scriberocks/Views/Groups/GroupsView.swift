import SwiftUI

/// Groups are forums. Signed-in members join (minors with a guardian's
/// approval through PermissionKit) and share rocks.
struct GroupsView: View {
    @StateObject private var viewModel: GroupsViewModel
    @EnvironmentObject private var childSafety: ChildSafetyManager
    @EnvironmentObject private var rockStore: RockStore
    @State private var asking: RockGroup?
    @State private var notice: String?
    @State private var path: [RockGroup] = []
    let service: GroupService

    init(service: GroupService, userId: String?, displayName: String?) {
        self.service = service
        _viewModel = StateObject(wrappedValue: GroupsViewModel(
            service: service, userId: userId, displayName: displayName,
            guardianApproved: { await GuardianApproval.isApproved(groupId: $0) }
        ))
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
                GroupFeedView(group: group, service: service, userId: viewModel.userId, displayName: viewModel.displayName)
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
            for await groupId in GuardianApproval.approvals() {
                await viewModel.guardianApproved(groupId: groupId)
            }
        }
        .sheet(item: $asking) { group in
            GuardianRequestView(group: group) { result in
                asking = nil
                switch result {
                case .sent: notice = "Request sent. You'll join \(group.name) when a parent or guardian approves."
                case .notNeeded: Task { await viewModel.guardianApproved(groupId: group.id) }
                case .unavailable(let message): notice = message
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Groups", isPresented: Binding(get: { notice != nil || viewModel.errorMessage != nil }, set: { if !$0 { notice = nil; viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? viewModel.errorMessage ?? "")
        }
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
        switch await viewModel.join(group, requiresGuardianApproval: childSafety.requiresGuardianApproval) {
        case .joined: break
        case .askGuardian: asking = group
        case .needsSignIn: notice = "Sign in on the Profile tab to join groups."
        case .failed(let message): notice = message
        }
    }
}

/// Explains the guardian step and sends the PermissionKit request.
private struct GuardianRequestView: View {
    let group: RockGroup
    let done: (GuardianApproval.AskResult) -> Void
    @State private var sending = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.badge.key").font(.largeTitle).foregroundStyle(.tint)
            Text("Ask to join \(group.name)").font(.title3.bold())
            Text("A parent or guardian approves joining groups. They'll get your request in Messages.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                sending = true
                Task { done(await GuardianApproval.ask(for: group)) }
            } label: {
                Label("Ask a parent or guardian", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sending)
        }
        .padding(24)
    }
}
