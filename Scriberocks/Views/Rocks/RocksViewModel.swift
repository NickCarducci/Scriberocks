import Foundation
import Combine

final class RocksViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case rocks = "Rocks"
        case diamonds = "Diamonds"
        var id: Self { self }
    }

    @Published var filter: Filter = .all

    let store: RockStore
    private var cancellables = Set<AnyCancellable>()

    init(store: RockStore) {
        self.store = store
        // Re-render whenever the store changes.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var visibleRocks: [Rock] {
        switch filter {
        case .all: store.rocks
        case .rocks: store.rocks.filter { !$0.isDiamond }
        case .diamonds: store.rocks.filter(\.isDiamond)
        }
    }

    var isEmpty: Bool { store.rocks.isEmpty }
    var csvExport: RocksCSV { RocksCSV(rocks: store.rocks) }

    func toggleDiamond(_ rock: Rock) {
        store.toggleDiamond(rock)
    }

    func delete(_ rock: Rock) {
        store.delete([rock.id])
    }

    func delete(at offsets: IndexSet) {
        let rocks = visibleRocks
        store.delete(Set(offsets.map { rocks[$0].id }))
    }
}
