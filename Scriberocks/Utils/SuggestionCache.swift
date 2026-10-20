import Foundation

/// A small least-recently-used cache keyed by text.
nonisolated struct SuggestionCache<Value> {
    let capacity: Int
    private var values: [String: Value] = [:]
    /// Keys, least recently used first.
    private var order: [String] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { values.count }

    subscript(key: String) -> Value? {
        mutating get {
            guard let v = values[key] else { return nil }
            touch(key)
            return v
        }
        set {
            guard let newValue else {
                values[key] = nil
                order.removeAll { $0 == key }
                return
            }
            values[key] = newValue
            touch(key)
            while order.count > capacity {
                values[order.removeFirst()] = nil
            }
        }
    }

    /// Without updating recency.
    func peek(_ key: String) -> Value? { values[key] }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
