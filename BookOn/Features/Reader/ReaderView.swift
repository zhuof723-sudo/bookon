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
        let (src, bk) = (source, book)
        Task {
            defer { loading = false }
            do {
                // 关键：书源 JS 里可能有 java.sleep 等阻塞调用（如轮询冷目录/正文，最长可达 90 秒）。
                // 本方法所在的 ReaderViewModel 是 @MainActor，若直接在这里 await，
                // Task 会继承主线程执行环境，阻塞调用会冻结整个 App 界面。
                // 用 Task.detached 把真正耗时的工作丢到后台线程，这里只 await 结果。
                let text = try await Task.detached {
                    try await WebBook.content(source: src, book: bk, chapter: chapter, nextChapterUrl: nextUrl)
                }.value
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

    /// 对应 Legado `ReadBookActivity.clickImg`：执行图片 `click` 里的 JS，
    /// 绑定 java/source/book/chapter，`result` = 图片地址（这里是段评气泡等场景的入口）。
    func clickImage(_ click: String, src: String) {
        let (s, bk) = (source, book)
        let ch = current
        Task.detached {
            do {
                _ = try JSCoreEvaluator.shared.eval(click, bindings: [
                    "source": s, "book": bk, "chapter": ch, "result": src,
                ])
            } catch {
                AppLog.put("执行图片 click 出错: \(error.localizedDescription)")
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

    @ObservedObject private var browser = BrowserPresenter.shared

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            content
            if showBars { topBar; bottomBar }
        }
        .navigationBarHidden(true)
        .onAppear { if vm.content.isEmpty { vm.loadCurrent() } }
        .onTapGesture { withAnimation { showBars.toggle() } }
        // 点段评气泡时 JS 会调用 java.showBrowser -> BrowserPresenter，在阅读器这一层直接弹出，
        // 保证 push 在导航栈里时也能正常展示评论页。
        .sheet(item: $browser.request) { req in
            BottomWebView(title: req.title, html: req.html, url: req.url)
        }
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
                    contentBody
                }
                chapterNav
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    /// 正文渲染：按段落逐段显示；段评气泡（`<img ...,{"click":"..."}>`）紧跟在**它所属段落的末尾**，
    /// 与原版一致（getComments 是 `comcont[段号] += '<img...>'`，即拼在该段文字后面），
    /// 而不是单独占一行。点击气泡按 Legado `clickImg` 语义执行 click JS。
    private var contentBody: some View {
        let paragraphs = ContentParagraph.parse(vm.content)
        return VStack(alignment: .leading, spacing: fontSize * 0.7) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                paragraphView(para)
            }
        }
    }

    @ViewBuilder
    private func paragraphView(_ para: ContentParagraph) -> some View {
        if para.bubbles.isEmpty {
            // 纯文本段落
            if !para.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(para.text)
                    .font(.system(size: fontSize))
                    .lineSpacing(fontSize * 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // 文本 + 尾部气泡：用自动换行的流式排布，气泡跟在文字后
            FlowLayout(spacing: 4, lineSpacing: fontSize * 0.5) {
                Text(para.text)
                    .font(.system(size: fontSize))
                ForEach(Array(para.bubbles.enumerated()), id: \.offset) { _, b in
                    CommentBubble(count: b.click.flatMap(parseBadgeCount)) {
                        if let c = b.click { vm.clickImage(c, src: b.src) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 段评气泡的数字是画在 SVG 位图里的，原生端拿不到画面像素；
    /// 退而求其次从 click 里 `showCmt('bookId','itemId','para','count')` 的第 4 个参数取回数量显示。
    private func parseBadgeCount(_ click: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: "showCmt\\([^)]*'\\s*,\\s*'(\\d+)'\\s*\\)"),
              let m = re.firstMatch(in: click, range: NSRange(click.startIndex..., in: click)),
              let r = Range(m.range(at: 1), in: click) else { return nil }
        return Int(click[r])
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
