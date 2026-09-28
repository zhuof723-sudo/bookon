import SwiftUI

@MainActor
final class BookDetailViewModel: ObservableObject {
    @Published var book: Book
    @Published var loading = false
    @Published var error: String?
    @Published var chapters: [BookChapter] = []
    @Published var inShelf = false

    let source: BookSource?

    init(search: SearchBook) {
        book = WebBook.toBook(search)
        source = AppDatabase.shared.bookSource(url: search.origin)
        inShelf = AppDatabase.shared.book(url: search.bookUrl) != nil
    }

    init(book: Book) {
        self.book = book
        source = AppDatabase.shared.bookSource(url: book.origin)
        inShelf = AppDatabase.shared.book(url: book.bookUrl) != nil
        chapters = AppDatabase.shared.chapters(bookUrl: book.bookUrl)
    }

    func load() {
        guard let source else { error = "找不到对应书源（可能已删除）"; return }
        loading = true; error = nil
        let src = source
        let bk = book
        Task {
            defer { loading = false }
            do {
                // 同阅读器：详情/目录抓取里可能有 java.sleep 阻塞轮询（本源目录冷启动最长 90 秒），
                // 必须放到 Task.detached 的后台线程执行，避免冻结主线程 UI。
                let (info, toc) = try await Task.detached {
                    let info = try await WebBook.bookInfo(source: src, book: bk)
                    let toc = try await WebBook.chapterList(source: src, book: info)
                    return (info, toc)
                }.value
                book = info
                chapters = toc
                if inShelf { persist() }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func toggleShelf() {
        if inShelf {
            try? AppDatabase.shared.deleteBook(url: book.bookUrl)
            inShelf = false
        } else {
            book.type = BookType.text
            book.durChapterTime = Date.nowMillis
            book.totalChapterNum = chapters.count
            persist()
            inShelf = true
        }
    }

    private func persist() {
        try? AppDatabase.shared.upsert(book)
        if !chapters.isEmpty { try? AppDatabase.shared.replaceChapters(bookUrl: book.bookUrl, chapters) }
    }
}

struct BookDetailView: View {
    @StateObject private var vm: BookDetailViewModel

    init(search: SearchBook) { _vm = StateObject(wrappedValue: BookDetailViewModel(search: search)) }
    init(book: Book) { _vm = StateObject(wrappedValue: BookDetailViewModel(book: book)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let e = vm.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.footnote)
                }
                actions
                if let intro = vm.book.displayIntro, !intro.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("简介").font(.headline)
                        IntroView(text: intro)
                    }
                }
                tocSection
            }
            .padding()
        }
        .navigationTitle(vm.book.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if vm.chapters.isEmpty { vm.load() } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCoverView(url: vm.book.displayCover, size: CGSize(width: 90, height: 122))
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.book.name).font(.title3).bold().lineLimit(2)
                if !vm.book.author.isEmpty { Text(vm.book.author).foregroundColor(.secondary) }
                if let k = vm.book.kind, !k.isEmpty {
                    Text(k.replacingOccurrences(of: ",", with: " · ")).font(.caption).foregroundColor(.accentColor).lineLimit(2)
                }
                if let last = vm.book.latestChapterTitle, !last.isEmpty {
                    Text("最新：\(last)").font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Text("来源：\(vm.book.originName)").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            NavigationLink {
                if let source = vm.source, let first = vm.chapters.first {
                    ReaderView(book: vm.book, chapters: vm.chapters, startIndex: vm.book.durChapterIndex < vm.chapters.count ? vm.book.durChapterIndex : 0, source: source)
                }
            } label: {
                Label(vm.book.durChapterIndex > 0 ? "继续阅读" : "开始阅读", systemImage: "book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.chapters.isEmpty)

            Button {
                vm.toggleShelf()
            } label: {
                Label(vm.inShelf ? "已在书架" : "加入书架", systemImage: vm.inShelf ? "checkmark" : "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var tocSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("目录").font(.headline)
                Spacer()
                if vm.loading { ProgressView().scaleEffect(0.8) }
                else if !vm.chapters.isEmpty { Text("\(vm.chapters.count) 章").font(.caption).foregroundColor(.secondary) }
            }
            if let source = vm.source, !vm.chapters.isEmpty {
                NavigationLink {
                    ChapterListView(book: vm.book, chapters: vm.chapters, source: source)
                } label: {
                    HStack {
                        Text("查看全部章节")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                ForEach(Array(vm.chapters.prefix(8))) { c in
                    Text(c.title).font(.subheadline).lineLimit(1).foregroundColor(.primary.opacity(0.85))
                }
            } else if !vm.loading {
                Text("暂无目录").foregroundColor(.secondary).font(.subheadline)
            }
        }
    }
}
