import Foundation
import Combine

final class RocksViewModel: ObservableObject {
    let store: RockStore
    private var cancellables = Set<AnyCancellable>()

    init(store: RockStore) {
        self.store = store
        // Re-render whenever the store changes.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var visibleRocks: [Rock] { store.rocks }

    var isEmpty: Bool { store.rocks.isEmpty }
    var csvExport: RocksCSV { RocksCSV(rocks: store.rocks) }

    func delete(_ rock: Rock) {
        store.delete([rock.id])
    }

    func delete(at offsets: IndexSet) {
        let rocks = visibleRocks
        store.delete(Set(offsets.map { rocks[$0].id }))
    }
}
