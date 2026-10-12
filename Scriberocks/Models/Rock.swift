//
//  Rock.swift
//  Scriberocks
//

import Foundation

/// One journal entry. A rock is a rough draft; marking it a diamond means
/// it's the final draft. (That distinction is what on-device Llama will
/// eventually help with — cutting rocks into diamonds.)
nonisolated struct Rock: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var isDiamond: Bool

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        isDiamond: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isDiamond = isDiamond
    }

    /// First line, for list rows and navigation titles.
    var title: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.trimmingCharacters(in: .whitespaces)
    }
}
