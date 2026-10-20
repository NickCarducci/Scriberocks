//
//  ChildSafetyManager.swift
//  Scriberocks
//
//  Mirrors Populist's ChildSafetyManager. Today it only learns the user's
//  age bracket (on device, never uploaded); when Groups ship, minors'
//  join requests will go to a guardian via PermissionKit.
//

import Foundation
import Combine
import DeclaredAgeRange

nonisolated enum AgeBracket: String, Codable, Sendable {
    case under13
    case teen13to15
    case teen16to17
    case adult
    case declined
    case unknown

    var label: String {
        switch self {
        case .under13: "Under 13"
        case .teen13to15: "13–15"
        case .teen16to17: "16–17"
        case .adult: "18+"
        case .declined: "Not shared"
        case .unknown: "Not asked yet"
        }
    }

    var isMinor: Bool {
        self == .under13 || self == .teen13to15 || self == .teen16to17
    }

    /// Age gates passed to `requestAgeRange` must line up with these cases.
    static let ageGates = (13, 16, 18)

    /// Maps the range Apple shares (bounds come from `ageGates`) to a bracket.
    static func from(lowerBound: Int?, upperBound: Int?) -> AgeBracket {
        switch (lowerBound, upperBound) {
        case (nil, nil): .unknown
        case (nil, _?): .under13
        case (let lower?, _) where lower < 13: .under13
        case (let lower?, _) where lower < 16: .teen13to15
        case (let lower?, _) where lower < 18: .teen16to17
        default: .adult
        }
    }
}

final class ChildSafetyManager: ObservableObject {
    @Published private(set) var ageBracket: AgeBracket
    @Published private(set) var hasCommunicationLimits: Bool

    private let defaults: UserDefaults
    private static let bracketKey = "ageBracket"
    private static let limitsKey = "hasCommunicationLimits"
    private static let postingKey = "postingApproved"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ageBracket = defaults.string(forKey: Self.bracketKey).flatMap(AgeBracket.init) ?? .unknown
        hasCommunicationLimits = defaults.bool(forKey: Self.limitsKey)
        postingApproved = defaults.bool(forKey: Self.postingKey)
    }

    /// A guardian approved posting to groups (PostingApproval), on this device.
    @Published private(set) var postingApproved: Bool

    /// Posting asks a guardian first, once.
    var needsPostingApproval: Bool { requiresGuardianApproval && !postingApproved }

    func markPostingApproved() {
        postingApproved = true
        defaults.set(true, forKey: Self.postingKey)
    }

    /// Group features will need a guardian's OK for these users.
    var requiresGuardianApproval: Bool {
        ageBracket.isMinor || hasCommunicationLimits
    }

    /// Asks Apple for the age range (gates 13, 16, 18).
    typealias AgeRequest = (Int, Int?, Int?) async throws -> AgeRangeService.Response

    enum AgeRangeOutcome: Equatable {
        case shared
        case declined
        /// Apple didn't answer, or answered with an error; the bracket is unchanged.
        case failed(String)
    }

    /// The request in progress, so overlapping callers (the launch refresh and
    /// the Profile button) share one call to Apple instead of stacking sheets.
    private var inFlight: Task<AgeRangeOutcome, Never>?

    /// Re-reads the age range (each launch while signed in). Apple caches the
    /// answer: with Always Share this returns the current range without a
    /// prompt, updated on the declaration's anniversary or when the person
    /// taps Share Age Range for this app in Settings; parental controls come
    /// with every answer. So turning 18 or lifted Communication Limits reach
    /// the app on their own.
    @discardableResult
    func refreshAgeRange(using requestAgeRange: DeclaredAgeRangeAction) async -> AgeRangeOutcome? {
        await requestAgeRangeIfNeeded(using: requestAgeRange, force: true)
    }

    @discardableResult
    func requestAgeRangeIfNeeded(using requestAgeRange: DeclaredAgeRangeAction, force: Bool = false) async -> AgeRangeOutcome? {
        await requestAgeRangeIfNeeded(using: { try await requestAgeRange(ageGates: $0, $1, $2) }, force: force)
    }

    /// Asks if not yet known (or `force`). Returns nil when nothing was asked.
    /// One request at a time; gives up after `timeout` so a stuck system sheet
    /// can't leave the app waiting forever.
    @discardableResult
    func requestAgeRangeIfNeeded(using request: @escaping AgeRequest, force: Bool = false,
                                 timeout: Duration = .seconds(30)) async -> AgeRangeOutcome? {
        if let inFlight { return await inFlight.value }
        guard force || ageBracket == .unknown else { return nil }
        let task = Task { () -> AgeRangeOutcome in
            let gates = AgeBracket.ageGates
            do {
                let response = try await withThrowingTaskGroup(of: AgeRangeService.Response?.self) { group in
                    group.addTask { try await request(gates.0, gates.1, gates.2) }
                    group.addTask { try await Task.sleep(for: timeout); return nil }
                    let first = try await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
                switch response {
                case .sharing(let range):
                    store(AgeBracket.from(lowerBound: range.lowerBound, upperBound: range.upperBound),
                          limits: range.activeParentalControls.contains(.communicationLimits))
                    return .shared
                case .declinedSharing:
                    store(.declined, limits: false)
                    return .declined
                case nil:
                    return .failed("Apple's age range service didn't respond. Try again, or check Settings › Screen Time.")
                @unknown default:
                    return .failed("Unexpected answer from Apple's age range service.")
                }
            } catch {
                // e.g. .notAvailable (no Apple Account / unsupported region): stay as is, ask again later.
                return .failed(error.localizedDescription)
            }
        }
        inFlight = task
        defer { inFlight = nil }
        return await task.value
    }

    func reset() {
        store(.unknown, limits: false)
        postingApproved = false
        defaults.removeObject(forKey: Self.postingKey)
    }

    private func store(_ bracket: AgeBracket, limits: Bool) {
        ageBracket = bracket
        hasCommunicationLimits = limits
        defaults.set(bracket.rawValue, forKey: Self.bracketKey)
        defaults.set(limits, forKey: Self.limitsKey)
    }
}
