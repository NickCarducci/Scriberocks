import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Exports rocks as a CSV via ShareLink.
nonisolated struct RocksCSV: Transferable, Sendable {
    let rocks: [Rock]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.csv.utf8)
        }
        .suggestedFileName("scriberocks.csv")
    }

    var csv: String {
        let formatter = ISO8601DateFormatter()
        let header = "created_at,updated_at,text"
        let rows = rocks.map { rock in
            [
                formatter.string(from: rock.createdAt),
                formatter.string(from: rock.updatedAt),
                Self.escape(rock.text),
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
