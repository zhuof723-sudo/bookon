import SwiftUI

@MainActor
final class BookSourceStore: ObservableObject {
    @Published var sources: [BookSource] = []
    @Published var searchText = ""
    @Published var selectedGroup: String? = nil

    private let db = AppDatabase.shared

    func reload() {
        sources = db.allBookSources()
    }

    var groups: [String] {
        var set = Set<String>()
        sources.forEach { set.formUnion($0.groups) }
        return set.sorted()
    }

    var filtered: [BookSource] {
        sources.filter { s in
            if let g = selectedGroup, !s.groups.contains(g) { return false }
            if searchText.isEmpty { return true }
            let q = searchText.lowercased()
            return s.bookSourceName.lowercased().contains(q)
                || s.bookSourceUrl.lowercased().contains(q)
                || (s.bookSourceGroup ?? "").lowercased().contains(q)
        }
    }

    func toggle(_ s: BookSource) {
        var copy = s
        copy.enabled.toggle()
        try? db.upsert(copy)
        reload()
    }

    func delete(_ list: [BookSource]) {
        try? db.deleteBookSources(urls: list.map(\.bookSourceUrl))
        reload()
    }

    func setEnabled(_ list: [BookSource], _ enabled: Bool) {
        try? db.setBookSourcesEnabled(urls: list.map(\.bookSourceUrl), enabled: enabled)
        reload()
    }

    func exportJSON(_ list: [BookSource]) -> URL? {
        guard let data = try? LegadoJSON.encoder().encode(list) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bookSource.json")
        try? data.write(to: url)
        return url
    }
}

struct BookSourceListView: View {
    @StateObject private var store = BookSourceStore()
    @State private var showImport = false
    @State private var shareURL: URL?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()

    var body: some View {
        Group {
            if store.sources.isEmpty {
                emptyView
            } else {
                list
            }
        }
        .navigationTitle("书源管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.searchText, prompt: "搜索书源")
        .toolbar { toolbar }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showImport, onDismiss: { store.reload() }) {
            ImportBookSourceView()
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .onAppear { store.reload() }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("还没有书源").font(.headline)
            Text("软件本身不提供内容，请自行导入书源。\n支持网址、JSON 文本、剪贴板。")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button {
                showImport = true
            } label: {
                Label("导入书源", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var list: some View {
        List(selection: $selection) {
            if !store.groups.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            groupChip(nil, "全部")
                            ForEach(store.groups, id: \.self) { g in groupChip(g, g) }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            Section(footer: Text("共 \(store.filtered.count) 个书源").font(.footnote)) {
                ForEach(store.filtered) { s in
                    BookSourceRow(source: s) { store.toggle(s) }
                        .tag(s.bookSourceUrl)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.delete([s]) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func groupChip(_ g: String?, _ title: String) -> some View {
        let active = store.selectedGroup == g
        return Button { store.selectedGroup = g } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? Color.accentColor : Color(.secondarySystemFill))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if editMode.isEditing {
                Menu {
                    Button("全选") { selection = Set(store.filtered.map(\.bookSourceUrl)) }
                    Button("启用所选") { store.setEnabled(selected, true) }
                    Button("禁用所选") { store.setEnabled(selected, false) }
                    Button("导出所选") { shareURL = store.exportJSON(selected) }
                    Button("删除所选", role: .destructive) { store.delete(selected); selection.removeAll() }
                } label: { Image(systemName: "ellipsis.circle") }
                Button("完成") { editMode = .inactive; selection.removeAll() }
            } else {
                Button { showImport = true } label: { Image(systemName: "plus") }
                Menu {
                    Button { editMode = .active } label: { Label("批量管理", systemImage: "checklist") }
                    Button { shareURL = store.exportJSON(store.sources) } label: { Label("导出全部", systemImage: "square.and.arrow.up") }
                        .disabled(store.sources.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private var selected: [BookSource] {
        store.sources.filter { selection.contains($0.bookSourceUrl) }
    }
}

struct BookSourceRow: View {
    let source: BookSource
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.bookSourceName.isEmpty ? source.bookSourceUrl : source.bookSourceName)
                        .font(.body)
                        .lineLimit(1)
                    if source.sourceType != .text {
                        Text(source.sourceType.label)
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }
                    if source.hasExplore {
                        Image(systemName: "safari").font(.caption2).foregroundColor(.secondary)
                    }
                    if source.hasLogin {
                        Image(systemName: "person.badge.key").font(.caption2).foregroundColor(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    if let g = source.bookSourceGroup, !g.isEmpty {
                        Text(g).font(.caption).foregroundColor(.accentColor)
                    }
                    Text(source.bookSourceUrl).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { source.enabled }, set: { _ in onToggle() }))
                .labelsHidden()
        }
        .opacity(source.enabled ? 1 : 0.55)
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
