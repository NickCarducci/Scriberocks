import Foundation
import Testing
@testable import Scriberocks

private func post(_ id: String = "p1", author: String = "a", reportedBy: [String] = [], review: GroupPost.Review? = nil) -> GroupPost {
    GroupPost(id: id, groupId: "g", authorId: author, authorName: "A", text: "hello", createdAt: .now, reportedBy: reportedBy, review: review)
}

/// Who sees a post: reports hide it (immediately for the reporter, for
/// everyone at the group's threshold) until the moderator keeps it; blocked
/// authors are hidden; authors see their own hidden posts as awaiting review.
struct ModerationTests {
    @Test func anOrdinaryPostIsShown() {
        #expect(Moderation.visibility(of: post(), viewer: "v", blocked: [], reportsToHide: 2) == .shown)
    }

    @Test func theReporterStopsSeeingItAtOnce() {
        #expect(Moderation.visibility(of: post(reportedBy: ["v"]), viewer: "v", blocked: [], reportsToHide: 2) == .hidden)
        #expect(Moderation.visibility(of: post(reportedBy: ["v"]), viewer: "w", blocked: [], reportsToHide: 2) == .shown)
    }

    @Test func enoughReportsHideItForEveryone() {
        #expect(Moderation.visibility(of: post(reportedBy: ["x", "y"]), viewer: "w", blocked: [], reportsToHide: 2) == .hidden)
        #expect(Moderation.visibility(of: post(reportedBy: ["x"]), viewer: "w", blocked: [], reportsToHide: 1) == .hidden)
    }

    @Test func theAuthorSeesTheirHiddenPostAsAwaitingReview() {
        #expect(Moderation.visibility(of: post(author: "a", reportedBy: ["x", "y"]), viewer: "a", blocked: [], reportsToHide: 2) == .awaitingReview)
    }

    @Test func aKeptPostIsShownDespiteReports() {
        #expect(Moderation.visibility(of: post(reportedBy: ["x", "y"], review: .kept), viewer: "w", blocked: [], reportsToHide: 2) == .shown)
        #expect(Moderation.visibility(of: post(reportedBy: ["w"], review: .kept), viewer: "w", blocked: [], reportsToHide: 2) == .hidden, "the reporter still chose not to see it")
    }

    @Test func blockedAuthorsAreHidden() {
        #expect(Moderation.visibility(of: post(author: "troll"), viewer: "w", blocked: ["troll"], reportsToHide: 2) == .hidden)
    }

    @Test func joiningAsksAGuardianOnlyWhenNeededAndNotYetApproved() {
        #expect(Moderation.joinStep(requiresGuardianApproval: false, guardianApproved: false) == .join)
        #expect(Moderation.joinStep(requiresGuardianApproval: true, guardianApproved: false) == .askGuardian)
        #expect(Moderation.joinStep(requiresGuardianApproval: true, guardianApproved: true) == .join)
    }
}

/// The word list: whole words and phrases, case- and obfuscation-insensitive,
/// without flagging innocent words that contain a listed one.
struct WordListFilterTests {
    let filter = WordListFilter(terms: ["kys", "kill yourself", "slurword"])

    @Test func flagsListedWordsAndPhrases() async {
        #expect(await filter.check("you should kys") != .allowed)
        #expect(await filter.check("Just KILL   yourself.") != .allowed)
        #expect(await filter.check("what a slurword") != .allowed)
    }

    @Test func seesThroughCommonObfuscation() async {
        #expect(await filter.check("k1ll y0urself") != .allowed)
        #expect(await filter.check("s l u r w o r d") == .allowed, "spaced letters aren't joined: too many false positives")
        #expect(await filter.check("$lurw0rd") != .allowed)
    }

    @Test func leavesInnocentTextAlone() async {
        #expect(await filter.check("The river was loud and the evening warm.") == .allowed)
        #expect(await filter.check("the skillet sat by the sky window") == .allowed)
    }

    @Test func theDefaultListIsNotEmpty() {
        #expect(!WordListFilter.defaultTerms.isEmpty)
    }
}

private struct StubFilter: ContentFilter {
    var verdict: FilterVerdict = .allowed
    func check(_ text: String) async -> FilterVerdict { verdict }
}

/// Layered filter: the word list first; the on-device model only when the
/// word list passes and the model is available.
struct LayeredFilterTests {
    @Test func theWordListWinsFirst() async {
        let f = LayeredFilter(layers: [StubFilter(verdict: .flagged("word list")), StubFilter(verdict: .allowed)])
        #expect(await f.check("x") == .flagged("word list"))
    }

    @Test func laterLayersCanFlag() async {
        let f = LayeredFilter(layers: [StubFilter(), StubFilter(verdict: .flagged("model"))])
        #expect(await f.check("x") == .flagged("model"))
    }

    @Test func allClearIsAllowed() async {
        #expect(await LayeredFilter(layers: [StubFilter(), StubFilter()]).check("x") == .allowed)
    }
}

@MainActor
struct GroupFeedViewModelTests {
    private let group = RockGroup(id: "g", name: "Commons", about: "", reportsToHide: 2)

    private func feed(user: String? = "me", filter: FilterVerdict = .allowed, service: InMemoryGroupService = InMemoryGroupService()) -> (GroupFeedViewModel, InMemoryGroupService) {
        (GroupFeedViewModel(group: group, service: service, userId: user, displayName: "Me", filter: StubFilter(verdict: filter)), service)
    }

    @Test func sharingNeedsSignIn() async {
        let (vm, service) = feed(user: nil)
        #expect(await vm.share("hi") == .needsSignIn)
        #expect(service.allPosts.isEmpty)
    }

    @Test func sharingNeedsTheTermsOnce() async {
        let (vm, service) = feed()
        await vm.load()
        #expect(await vm.share("hi") == .needsTerms)
        await vm.acceptTerms()
        #expect(await vm.share("hi") == .posted)
        #expect(service.allPosts.map(\.text) == ["hi"])
    }

    @Test func aFlaggedPostIsNotSent() async {
        let (vm, service) = feed(filter: .flagged("abusive"))
        await vm.acceptTerms()
        #expect(await vm.share("nasty") == .flagged("abusive"))
        #expect(service.allPosts.isEmpty)
    }

    @Test func reportingHidesThePostForTheReporterAtOnce() async throws {
        let service = InMemoryGroupService()
        service.seed(post("p1", author: "other"))
        let (vm, _) = feed(service: service)
        await vm.load()
        #expect(vm.visiblePosts.map(\.post.id) == ["p1"])
        await vm.report(try #require(vm.visiblePosts.first).post, reason: "abuse")
        #expect(vm.visiblePosts.isEmpty)
        #expect(service.allPosts.first?.reportedBy == ["me"])
        #expect(service.reports.count == 1)
    }

    @Test func blockingHidesTheAuthorsPosts() async {
        let service = InMemoryGroupService()
        service.seed(post("p1", author: "troll"))
        service.seed(post("p2", author: "friend"))
        let (vm, _) = feed(service: service)
        await vm.load()
        await vm.block("troll")
        #expect(vm.visiblePosts.map(\.post.id) == ["p2"])
        await vm.load()
        #expect(vm.visiblePosts.map(\.post.id) == ["p2"], "blocks persist")
    }

    @Test func onlyTheAuthorCanDelete() async throws {
        let service = InMemoryGroupService()
        service.seed(post("theirs", author: "other"))
        let (vm, _) = feed(service: service)
        await vm.acceptTerms()
        _ = await vm.share("mine")
        await vm.load()
        let mine = try #require(vm.visiblePosts.first { $0.post.authorId == "me" }).post
        let theirs = try #require(vm.visiblePosts.first { $0.post.authorId == "other" }).post
        #expect(vm.canDelete(theirs) == false)
        await vm.delete(theirs)
        #expect(service.allPosts.contains { $0.id == "theirs" })
        await vm.delete(mine)
        #expect(!service.allPosts.contains { $0.id == mine.id })
    }
}

@MainActor
struct GroupsViewModelTests {
    @Test func adultsJoinDirectly() async {
        let service = InMemoryGroupService()
        service.seedGroup(RockGroup(id: "g", name: "Commons", about: "", reportsToHide: 2))
        let vm = GroupsViewModel(service: service, userId: "me", displayName: "Me")
        await vm.load()
        #expect(await vm.join(vm.groups[0], requiresGuardianApproval: false) == .joined)
        #expect(vm.isMember("g"))
    }

    @Test func minorsAskAGuardianUnlessAlreadyApproved() async {
        let service = InMemoryGroupService()
        service.seedGroup(RockGroup(id: "g", name: "Commons", about: "", reportsToHide: 1))
        let vm = GroupsViewModel(service: service, userId: "me", displayName: "Me", guardianApproved: { _ in false })
        await vm.load()
        #expect(await vm.join(vm.groups[0], requiresGuardianApproval: true) == .askGuardian)
        #expect(!vm.isMember("g"))
        await vm.guardianApproved(groupId: "g")
        #expect(vm.isMember("g"))
        #expect(service.members["g"]?["me"] == true, "joined with guardian approval recorded")

        let approved = GroupsViewModel(service: InMemoryGroupService(), userId: "me", displayName: "Me", guardianApproved: { _ in true })
        #expect(await approved.join(RockGroup(id: "h", name: "H", about: "", reportsToHide: 1), requiresGuardianApproval: true) == .joined)
    }

    @Test func joiningNeedsSignIn() async {
        let vm = GroupsViewModel(service: InMemoryGroupService(), userId: nil, displayName: nil)
        #expect(await vm.join(RockGroup(id: "g", name: "G", about: "", reportsToHide: 2), requiresGuardianApproval: false) == .needsSignIn)
    }
}

struct GuardianApprovalTests {
    @Test func groupHandlesRoundTrip() {
        #expect(GuardianApproval.groupId(fromHandle: GuardianApproval.handleValue(for: "commons")) == "commons")
        #expect(GuardianApproval.groupId(fromHandle: "+15555550100") == nil)
    }
}
