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

    /// Re-reads the age range (each launch while signed in). Apple caches the
    /// answer: with Always Share this returns the current range without a
    /// prompt, updated on the declaration's anniversary or when the person
    /// taps Share Age Range for this app in Settings; parental controls come
    /// with every answer. So turning 18 or lifted Communication Limits reach
    /// the app on their own.
    func refreshAgeRange(using requestAgeRange: DeclaredAgeRangeAction) async {
        await requestAgeRangeIfNeeded(using: requestAgeRange, force: true)
    }

    /// Asks if not yet known; pass `force` to read it again (see refreshAgeRange).
    func requestAgeRangeIfNeeded(using requestAgeRange: DeclaredAgeRangeAction, force: Bool = false) async {
        guard force || ageBracket == .unknown else { return }
        do {
            let gates = AgeBracket.ageGates
            switch try await requestAgeRange(ageGates: gates.0, gates.1, gates.2) {
            case .sharing(let range):
                store(
                    AgeBracket.from(lowerBound: range.lowerBound, upperBound: range.upperBound),
                    limits: range.activeParentalControls.contains(.communicationLimits)
                )
            case .declinedSharing:
                store(.declined, limits: false)
            @unknown default:
                break
            }
        } catch {
            // .notAvailable (e.g. no Apple Account / unsupported region) — stay unknown and ask again later.
            print("Age range unavailable: \(error.localizedDescription)")
        }
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
