import SwiftUI
import UniformTypeIdentifiers

struct ImportBookSourceView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var loading = false
    @State private var error: String?
    @State private var items: [ImportedSource] = []
    @State private var showFilePicker = false
    @State private var doneCount: Int?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    inputView
                } else {
                    previewView
                }
            }
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("导入失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好") {}
            } message: { Text(error ?? "") }
            .alert("导入完成", isPresented: Binding(get: { doneCount != nil }, set: { if !$0 { doneCount = nil } })) {
                Button("好") { dismiss() }
            } message: { Text("已保存 \(doneCount ?? 0) 个书源") }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(allowsMultiple: true) { urls in
                    showFilePicker = false
                    loadFiles(urls)
                } onCancel: {
                    showFilePicker = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: 输入

    private var inputView: some View {
        Form {
            Section(footer: Text("粘贴书源网址（http/https）或书源 JSON。也支持含 sourceUrls 的订阅格式。")) {
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section {
                Button {
                    if let s = UIPasteboard.general.string { text = s; start() }
                    else { error = "剪贴板为空" }
                } label: { Label("从剪贴板导入", systemImage: "doc.on.clipboard") }
                Button { showFilePicker = true } label: { Label("从文件导入", systemImage: "folder") }
            }
            Section {
                Button {
                    start()
                } label: {
                    HStack {
                        Spacer()
                        if loading { ProgressView().padding(.trailing, 6) }
                        Text(loading ? "正在解析…" : "开始导入").bold()
                        Spacer()
                    }
                }
                .disabled(loading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func loadFiles(_ urls: [URL]) {
        // 多个文件：各自解析后合并
        var texts: [String] = []
        for url in urls {
            if let t = DocumentPicker.readText(url) { texts.append(t) }
        }
        guard !texts.isEmpty else { error = "无法读取文件"; return }
        if texts.count == 1 {
            text = texts[0]
            start()
            return
        }
        loading = true
        Task {
            defer { loading = false }
            var all: [BookSource] = []
            var errors: [String] = []
            for t in texts {
                do { all += try await BookSourceImporter.importText(t) }
                catch { errors.append(error.localizedDescription) }
            }
            if all.isEmpty {
                self.error = errors.first ?? "没有可导入的书源"
            } else {
                items = BookSourceImporter.compare(all)
            }
        }
    }

    private func start() {
        loading = true
        Task {
            defer { loading = false }
            do {
                let list = try await BookSourceImporter.importText(text)
                items = BookSourceImporter.compare(list)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: 预览

    private var selectedCount: Int { items.filter(\.selected).count }
    private var newCount: Int { items.filter(\.isNew).count }
    private var updateCount: Int { items.filter(\.isUpdate).count }

    private var previewView: some View {
        VStack(spacing: 0) {
            List {
                Section(header: Text("共 \(items.count) 个 · 新增 \(newCount) · 更新 \(updateCount)")) {
                    ForEach($items) { $item in
                        Toggle(isOn: $item.selected) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(item.source.bookSourceName).lineLimit(1)
                                    if item.isNew {
                                        badge("新增", .green)
                                    } else if item.isUpdate {
                                        badge("更新", .orange)
                                    } else {
                                        badge("已有", .gray)
                                    }
                                }
                                Text(item.source.bookSourceUrl).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            HStack {
                Menu("选择") {
                    Button("全选") { items.indices.forEach { items[$0].selected = true } }
                    Button("全不选") { items.indices.forEach { items[$0].selected = false } }
                    Button("仅新增") { items.indices.forEach { items[$0].selected = items[$0].isNew } }
                    Button("新增和更新") { items.indices.forEach { items[$0].selected = items[$0].isNew || items[$0].isUpdate } }
                }
                Spacer()
                Button {
                    save()
                } label: {
                    Text("导入所选 (\(selectedCount))").bold()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0)
            }
            .padding()
            .background(.bar)
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(c.opacity(0.15)).foregroundColor(c).cornerRadius(3)
    }

    private func save() {
        var toSave = items.filter(\.selected).map(\.source)
        // 保留本地已有的排序号 / 启用状态，与 Legado 一致
        for i in toSave.indices {
            if let old = items.first(where: { $0.id == toSave[i].bookSourceUrl })?.existing {
                toSave[i].customOrder = old.customOrder
                toSave[i].enabled = old.enabled
            }
        }
        do {
            try AppDatabase.shared.upsert(toSave)
            doneCount = toSave.count
        } catch {
            self.error = error.localizedDescription
        }
    }
}
