import SwiftUI

/// All your rocks: pick one to open it on the home screen.
struct RockLibraryView: View {
    @StateObject private var viewModel: RocksViewModel
    let pick: (Rock.ID) -> Void

    init(store: RockStore, pick: @escaping (Rock.ID) -> Void) {
        _viewModel = StateObject(wrappedValue: RocksViewModel(store: store))
        self.pick = pick
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $viewModel.filter) {
                    ForEach(RocksViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                ForEach(viewModel.visibleRocks) { rock in
                    Button { pick(rock.id) } label: { LibraryRow(rock: rock) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button {
                                viewModel.toggleDiamond(rock)
                            } label: {
                                if rock.isDiamond {
                                    Label("Back to rock", image: "rock")
                                } else {
                                    Label("Diamond", systemImage: "diamond")
                                }
                            }
                            .tint(.accentColor)
                        }
                }
                .onDelete(perform: viewModel.delete(at:))
            }
            .overlay {
                if viewModel.isEmpty {
                    ContentUnavailableView("No rocks yet", image: "rock", description: Text("Tap ＋ to drop your first one."))
                }
            }
            .navigationTitle("Rocks")
            .toolbar {
                if !viewModel.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: viewModel.csvExport, preview: SharePreview("scriberocks.csv", image: Image(systemName: "tablecells"))) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}

private struct LibraryRow: View {
    let rock: Rock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(rock.title).font(.headline).lineLimit(1)
                Spacer()
                if rock.isDiamond {
                    Image(systemName: "diamond.fill").foregroundStyle(.tint).accessibilityLabel("Diamond")
                }
            }
            Text(rock.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Text(rock.createdAt, format: .dateTime.month().day().year()).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}
