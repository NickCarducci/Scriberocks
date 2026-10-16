import SwiftUI

struct RocksListView: View {
    @StateObject private var viewModel: RocksViewModel
    @Binding private var path: [Rock.ID]

    init(store: RockStore, path: Binding<[Rock.ID]> = .constant([])) {
        _viewModel = StateObject(wrappedValue: RocksViewModel(store: store))
        _path = path
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isEmpty {
                    ContentUnavailableView(
                        "No rocks yet",
                        systemImage: "fossil.shell",
                        description: Text("Write something on the Write tab and it'll land here.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Rocks")
            .navigationDestination(for: Rock.ID.self) { id in
                RockEditorView(rockID: id, store: viewModel.store)
            }
            .toolbar {
                if !viewModel.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: viewModel.csvExport,
                            preview: SharePreview("scriberocks.csv", image: Image(systemName: "tablecells"))
                        ) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            Picker("Show", selection: $viewModel.filter) {
                ForEach(RocksViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            ForEach(viewModel.visibleRocks) { rock in
                NavigationLink(value: rock.id) {
                    RockRow(rock: rock)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        viewModel.toggleDiamond(rock)
                    } label: {
                        Label(rock.isDiamond ? "Back to rock" : "Diamond",
                              systemImage: rock.isDiamond ? "fossil.shell" : "diamond")
                    }
                    .tint(.accentColor)
                }
            }
            .onDelete(perform: viewModel.delete(at:))
        }
    }
}

private struct RockRow: View {
    let rock: Rock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(rock.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if rock.isDiamond {
                    Image(systemName: "diamond.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Diamond")
                }
            }
            Text(rock.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(rock.createdAt, format: .dateTime.month().day().year())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    RocksListView(store: .preview())
}
