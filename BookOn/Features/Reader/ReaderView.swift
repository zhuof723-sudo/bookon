import SwiftUI

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var index: Int
    @Published var content = ""
    @Published var loading = false
    @Published var error: String?

    let book: Book
    let chapters: [BookChapter]
    let source: BookSource

    init(book: Book, chapters: [BookChapter], startIndex: Int, source: BookSource) {
        self.book = book
        self.chapters = chapters
        self.source = source
        self.index = min(max(0, startIndex), max(0, chapters.count - 1))
    }

    var current: BookChapter? { chapters.indices.contains(index) ? chapters[index] : nil }
    var canPrev: Bool { index > 0 }
    var canNext: Bool { index < chapters.count - 1 }

    func loadCurrent() {
        guard let chapter = current else { return }
        // 先读缓存
        if let cached = AppDatabase.shared.cacheGet(contentKey(chapter)) {
            content = cached
            saveProgress()
            return
        }
        loading = true; error = nil; content = ""
        let nextUrl = chapters.indices.contains(index + 1) ? chapters[index + 1].url : nil
        Task {
            defer { loading = false }
            do {
                let text = try await WebBook.content(source: source, book: book, chapter: chapter, nextChapterUrl: nextUrl)
                content = text
                AppDatabase.shared.cachePut(contentKey(chapter), text)
                saveProgress()
                prefetchNext()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func go(_ delta: Int) {
        let target = index + delta
        guard chapters.indices.contains(target) else { return }
        index = target
        loadCurrent()
    }

    func jump(to i: Int) {
        guard chapters.indices.contains(i) else { return }
        index = i
        loadCurrent()
    }

    private func prefetchNext() {
        guard chapters.indices.contains(index + 1) else { return }
        let next = chapters[index + 1]
        if AppDatabase.shared.cacheGet(contentKey(next)) != nil { return }
        let afterUrl = chapters.indices.contains(index + 2) ? chapters[index + 2].url : nil
        let key = contentKey(next)
        Task.detached { [source, book] in
            if let text = try? await WebBook.content(source: source, book: book, chapter: next, nextChapterUrl: afterUrl) {
                AppDatabase.shared.cachePut(key, text)
            }
        }
    }

    private func saveProgress() {
        guard AppDatabase.shared.book(url: book.bookUrl) != nil else { return }
        var b = book
        b.durChapterIndex = index
        b.durChapterTitle = current?.title
        b.durChapterTime = Date.nowMillis
        try? AppDatabase.shared.upsert(b)
    }

    private func contentKey(_ c: BookChapter) -> String {
        "content::\(book.bookUrl)::\(c.index)::\(c.url)"
    }
}

struct ReaderView: View {
    @StateObject private var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showBars = false
    @AppStorage("reader.fontSize") private var fontSize = 19.0

    init(book: Book, chapters: [BookChapter], startIndex: Int, source: BookSource) {
        _vm = StateObject(wrappedValue: ReaderViewModel(book: book, chapters: chapters, startIndex: startIndex, source: source))
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            content
            if showBars { topBar; bottomBar }
        }
        .navigationBarHidden(true)
        .onAppear { if vm.content.isEmpty { vm.loadCurrent() } }
        .onTapGesture { withAnimation { showBars.toggle() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(vm.current?.title ?? "")
                    .font(.title3).bold()
                    .padding(.top, 60)
                if vm.loading {
                    HStack { Spacer(); ProgressView("加载中…"); Spacer() }.padding(.top, 40)
                } else if let e = vm.error {
                    VStack(spacing: 10) {
                        Text("加载失败").font(.headline)
                        Text(e).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("重试") { vm.loadCurrent() }.buttonStyle(.borderedProminent)
                        diagnostics
                    }.padding(.top, 40).frame(maxWidth: .infinity)
                } else if vm.content.isEmpty {
                    VStack(spacing: 10) {
                        Text("正文为空").font(.headline)
                        Button("重试") { vm.loadCurrent() }.buttonStyle(.borderedProminent)
                        diagnostics
                    }.padding(.top, 40).frame(maxWidth: .infinity)
                } else {
                    Text(vm.content)
                        .font(.system(size: fontSize))
                        .lineSpacing(fontSize * 0.5)
                }
                chapterNav
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    private var diagnostics: some View {
        let lines = AppLog.lines.suffix(12)
        return Group {
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("日志").font(.caption).foregroundColor(.secondary)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l).font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemFill))
                .cornerRadius(6)
            }
        }
    }

    private var chapterNav: some View {
        HStack {
            Button { vm.go(-1) } label: { Label("上一章", systemImage: "chevron.left") }
                .disabled(!vm.canPrev)
            Spacer()
            Text("\(vm.index + 1)/\(vm.chapters.count)").font(.caption).foregroundColor(.secondary)
            Spacer()
            Button { vm.go(1) } label: { Label("下一章", systemImage: "chevron.right") }
                .disabled(!vm.canNext)
        }
        .padding(.top, 30)
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").padding(8) }
                Spacer()
                Text(vm.book.name).font(.headline).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.left").padding(8).opacity(0)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .background(.bar)
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 20) {
                Button { vm.go(-1) } label: { Image(systemName: "backward.end") }.disabled(!vm.canPrev)
                Button { if fontSize > 12 { fontSize -= 1 } } label: { Image(systemName: "textformat.size.smaller") }
                Text("\(Int(fontSize))").font(.caption).frame(width: 24)
                Button { if fontSize < 32 { fontSize += 1 } } label: { Image(systemName: "textformat.size.larger") }
                Button { vm.go(1) } label: { Image(systemName: "forward.end") }.disabled(!vm.canNext)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}
