//
//  Rock.swift
//  Scriberocks
//

import Foundation

/// One version of a rock's text.
nonisolated struct Revision: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        /// First written.
        case written
        /// Typed by the person.
        case edited
        /// An accepted suggestion (variant).
        case suggestion
    }

    var text: String
    var createdAt: Date
    var source: Source
}

/// One journal entry. Every change is kept as a revision; `text` is the
/// revision currently shown. (Rocks saved with the old `isDiamond` flag still
/// decode; the flag is ignored and dropped on the next save.)
nonisolated struct Rock: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    /// Oldest first. Never empty.
    var revisions: [Revision]
    /// Which revision `text` shows.
    var revisionIndex: Int

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        revisions: [Revision]? = nil,
        revisionIndex: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        let history = revisions.flatMap { $0.isEmpty ? nil : $0 } ?? [Revision(text: text, createdAt: createdAt, source: .written)]
        self.revisions = history
        self.revisionIndex = min(max(revisionIndex ?? history.count - 1, 0), history.count - 1)
    }

    /// Rocks saved before revisions existed decode with a one-revision history.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            text: try c.decode(String.self, forKey: .text),
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt),
            revisions: try c.decodeIfPresent([Revision].self, forKey: .revisions),
            revisionIndex: try c.decodeIfPresent(Int.self, forKey: .revisionIndex)
        )
    }

    /// First line, for list rows and navigation titles.
    var title: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.trimmingCharacters(in: .whitespaces)
    }

    var canGoBack: Bool { revisionIndex > 0 }
    var canGoForward: Bool { revisionIndex < revisions.count - 1 }

    /// Adds a new revision at the end of the history and shows it. History is
    /// never truncated: revising from an older revision still appends.
    mutating func revise(to newText: String, source: Revision.Source, at date: Date = .now) {
        guard newText != text else { return }
        revisions.append(Revision(text: newText, createdAt: date, source: source))
        revisionIndex = revisions.count - 1
        text = newText
    }

    /// Shows another revision (‹ ›).
    mutating func show(revision index: Int) {
        guard revisions.indices.contains(index) else { return }
        revisionIndex = index
        text = revisions[index].text
    }
}
