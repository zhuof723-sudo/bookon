import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword = ""
    @Published var results: [SearchBook] = []
    @Published var searching = false
    @Published var progress = ""

    private var task: Task<Void, Never>?

    func search() {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        task?.cancel()
        results = []
        searching = true
        progress = ""
        let sources = AppDatabase.shared.enabledBookSources().filter { $0.hasSearch }
        task = Task {
            await runSearch(key: key, sources: sources)
        }
    }

    func cancel() {
        task?.cancel()
        searching = false
    }

    private func runSearch(key: String, sources: [BookSource]) async {
        guard !sources.isEmpty else {
            progress = "没有启用的可搜索书源"
            searching = false
            return
        }
        var done = 0
        let total = sources.count
        // 限制并发数，避免一次打开太多连接
        let batchSize = 6
        var index = 0
        while index < sources.count {
            if Task.isCancelled { break }
            let batch = Array(sources[index..<min(index + batchSize, sources.count)])
            await withTaskGroup(of: [SearchBook].self) { group in
                for s in batch {
                    group.addTask { (try? await WebBook.search(source: s, key: key, page: 1)) ?? [] }
                }
                for await books in group {
                    done += 1
                    if Task.isCancelled { continue }
                    merge(books, key: key)
                    progress = "已搜索 \(done)/\(total) 个书源，\(results.count) 条结果"
                }
            }
            index += batchSize
        }
        if !Task.isCancelled { searching = false; if results.isEmpty { progress = "没有找到「\(key)」" } }
    }

    /// 合并结果：同名同作者的书聚合到一起（这里简单按 name+author 去重，保留第一个来源）
    private func merge(_ books: [SearchBook], key: String) {
        for b in books {
            // 精确度优先：书名或作者包含关键字的排前面
            if !results.contains(where: { $0.name == b.name && $0.author == b.author && $0.origin == b.origin }) {
                results.append(b)
            }
        }
        results.sort { lhs, rhs in
            func score(_ x: SearchBook) -> Int {
                if x.name == key { return 0 }
                if x.name.contains(key) { return 1 }
                if x.author.contains(key) { return 2 }
                return 3
            }
            return score(lhs) < score(rhs)
        }
    }
}

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.results.isEmpty && !vm.searching {
                    placeholder
                } else {
                    List {
                        if !vm.progress.isEmpty {
                            Text(vm.progress).font(.caption).foregroundColor(.secondary)
                        }
                        ForEach(vm.results) { b in
                            NavigationLink { BookDetailView(search: b) } label: { SearchBookRow(book: b) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $vm.keyword, prompt: "搜索书名或作者")
            .onSubmit(of: .search) { vm.search() }
            .toolbar {
                if vm.searching {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("停止") { vm.cancel() }
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 44)).foregroundColor(.secondary)
            Text("输入书名或作者，从已启用书源搜索").foregroundColor(.secondary).font(.subheadline)
            let n = AppDatabase.shared.enabledBookSources().filter { $0.hasSearch }.count
            Text("当前 \(n) 个可搜索书源").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}

struct SearchBookRow: View {
    let book: SearchBook
    var body: some View {
        HStack(spacing: 10) {
            BookCoverView(url: book.coverUrl, size: CGSize(width: 44, height: 60))
            VStack(alignment: .leading, spacing: 3) {
                Text(book.name).font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    if !book.author.isEmpty { Text(book.author).font(.caption).foregroundColor(.secondary) }
                    Text(book.originName).font(.caption2).foregroundColor(.accentColor).lineLimit(1)
                }
                if let last = book.latestChapterTitle, !last.isEmpty {
                    Text(last).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
