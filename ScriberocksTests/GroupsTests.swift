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

    /// Guardian approval is per author (PermissionKit's model: who a child
    /// communicates with), not per group.
    @Test func aGuardedReaderSeesOnlyApprovedAuthors() {
        #expect(Moderation.visibility(of: post(author: "a"), viewer: "kid", blocked: [], reportsToHide: 2, approvedAuthors: []) == .needsGuardian)
        #expect(Moderation.visibility(of: post(author: "a"), viewer: "kid", blocked: [], reportsToHide: 2, approvedAuthors: ["a"]) == .shown)
        #expect(Moderation.visibility(of: post(author: "kid"), viewer: "kid", blocked: [], reportsToHide: 2, approvedAuthors: []) == .shown, "your own posts")
        #expect(Moderation.visibility(of: post(author: "a"), viewer: "adult", blocked: [], reportsToHide: 2, approvedAuthors: nil) == .shown, "no guardian filter")
    }

    @Test func reportsAndBlocksStillHideApprovedAuthors() {
        #expect(Moderation.visibility(of: post(author: "a", reportedBy: ["kid"]), viewer: "kid", blocked: [], reportsToHide: 2, approvedAuthors: ["a"]) == .hidden)
        #expect(Moderation.visibility(of: post(author: "a"), viewer: "kid", blocked: ["a"], reportsToHide: 2, approvedAuthors: []) == .hidden)
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
struct GuardedFeedTests {
    private let group = RockGroup(id: "g", name: "Commons", about: "", reportsToHide: 2)

    private func service() -> InMemoryGroupService {
        let s = InMemoryGroupService()
        s.seed(post("1", author: "ana"))
        s.seed(post("2", author: "ben"))
        s.seed(post("3", author: "ana"))
        return s
    }

    @Test func unapprovedAuthorsAreCollapsedIntoOneRequest() async {
        let vm = GroupFeedViewModel(group: group, service: service(), userId: "kid", displayName: "Kid", filter: StubFilter(),
                                    requiresGuardianApproval: true, approvedAmong: { $0.intersection(["ben"]) })
        await vm.load()
        #expect(vm.visiblePosts.map(\.post.id) == ["2"])
        #expect(vm.authorsAwaitingApproval.map(\.id) == ["ana"], "each hidden author once")
        #expect(vm.hiddenForGuardianCount == 2)
    }

    @Test func approvalShowsThatAuthorsPosts() async {
        let vm = GroupFeedViewModel(group: group, service: service(), userId: "kid", displayName: "Kid", filter: StubFilter(),
                                    requiresGuardianApproval: true, approvedAmong: { _ in [] })
        await vm.load()
        #expect(vm.visiblePosts.isEmpty)
        vm.guardianApproved(["ana"])
        #expect(Set(vm.visiblePosts.map(\.post.id)) == ["1", "3"])
        #expect(vm.authorsAwaitingApproval.map(\.id) == ["ben"])
    }

    @Test func withoutCommunicationLimitsEverythingShows() async {
        let vm = GroupFeedViewModel(group: group, service: service(), userId: "kid", displayName: "Kid", filter: StubFilter(),
                                    requiresGuardianApproval: true, approvedAmong: { _ in [] })
        await vm.load()
        vm.guardianNotRequired()
        #expect(vm.visiblePosts.count == 3)
        #expect(vm.authorsAwaitingApproval.isEmpty)
    }

    @Test func adultsAreNotFiltered() async {
        let vm = GroupFeedViewModel(group: group, service: service(), userId: "me", displayName: "Me", filter: StubFilter())
        await vm.load()
        #expect(vm.visiblePosts.count == 3 && vm.authorsAwaitingApproval.isEmpty)
    }
}

@MainActor
struct GroupsViewModelTests {
    @Test func adultsJoinDirectly() async {
        let service = InMemoryGroupService()
        service.seedGroup(RockGroup(id: "g", name: "Commons", about: "", reportsToHide: 2))
        let vm = GroupsViewModel(service: service, userId: "me", displayName: "Me")
        await vm.load()
        #expect(await vm.join(vm.groups[0]) == .joined)
        #expect(vm.isMember("g"))
    }

    @Test func minorsJoinDirectlyToo() async {
        let service = InMemoryGroupService()
        service.seedGroup(RockGroup(id: "g", name: "Commons", about: "", reportsToHide: 1))
        let vm = GroupsViewModel(service: service, userId: "kid", displayName: "Kid")
        await vm.load()
        #expect(await vm.join(vm.groups[0]) == .joined)
        #expect(vm.isMember("g"))
    }

    @Test func joiningNeedsSignIn() async {
        let vm = GroupsViewModel(service: InMemoryGroupService(), userId: nil, displayName: nil)
        #expect(await vm.join(RockGroup(id: "g", name: "G", about: "", reportsToHide: 2)) == .needsSignIn)
    }
}

struct GuardianApprovalTests {
    @Test func authorHandlesAreAccountIdsNotNames() {
        #expect(GuardianApproval.authorId(fromHandle: GuardianApproval.handleValue(forAuthor: "uid123")) == "uid123")
        #expect(GuardianApproval.authorId(fromHandle: "+15555550100") == nil)
        #expect(GuardianApproval.handleValue(forAuthor: "uid123") != GuardianApproval.handleValue(forAuthor: "Ana"))
    }
}

/// Posting to a group needs one guardian approval of the capability for
/// readers under guardian controls; reading stays per author.
@MainActor
struct PostingApprovalGateTests {
    private let group = RockGroup(id: "g", name: "Commons", about: "", reportsToHide: 2)

    @Test func aGuardedWriterAsksOnceBeforeSharing() async {
        var approved = false
        let service = InMemoryGroupService()
        let vm = GroupFeedViewModel(group: group, service: service, userId: "kid", displayName: "Kid", filter: StubFilter(),
                                    requiresGuardianApproval: true, postingApproved: { approved })
        await vm.acceptTerms()
        #expect(await vm.share("hello") == .needsGuardianApproval)
        #expect(service.allPosts.isEmpty)
        approved = true
        #expect(await vm.share("hello") == .posted)
    }

    @Test func othersShareWithoutAsking() async {
        let vm = GroupFeedViewModel(group: group, service: InMemoryGroupService(), userId: "me", displayName: "Me", filter: StubFilter())
        await vm.acceptTerms()
        #expect(await vm.share("hello") == .posted)
    }

    @Test func theQuestionDescribesTheCapability() {
        #expect(PostingApproval.description.contains("groups"))
    }
}
