import SwiftUI

/// 书源调试（第 2 步版本）：只到“解析 URL → 发请求 → 看原始响应”。
/// 后续步骤会接上规则引擎，显示解析出的书籍列表。
struct SourceDebugView: View {
    let source: BookSource

    @State private var keyword = "我的"
    @State private var page = 1
    @State private var running = false
    @State private var log: [String] = []
    @State private var responsePreview = ""
    @State private var books: [SearchBook] = []

    var body: some View {
        Form {
            Section("搜索地址规则") {
                Text(source.searchUrl ?? "（无）")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Section {
                TextField("关键字", text: $keyword)
                Stepper("页码：\(page)", value: $page, in: 1...99)
                Button {
                    run()
                } label: {
                    HStack {
                        if running { ProgressView().padding(.trailing, 6) }
                        Text(running ? "请求中…" : "解析并请求")
                    }
                }
                .disabled(running || !source.hasSearch)
            }
            if !log.isEmpty {
                Section("解析结果") {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            if !books.isEmpty {
                Section("解析出的书籍（\(books.count)）") {
                    ForEach(books) { b in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(b.name).bold()
                                if !b.author.isEmpty { Text(b.author).foregroundColor(.secondary) }
                            }
                            if let k = b.kind, !k.isEmpty { Text(k).font(.caption).foregroundColor(.accentColor) }
                            if let l = b.latestChapterTitle { Text("最新：\(l)").font(.caption).foregroundColor(.secondary) }
                            Text(b.bookUrl).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            if let c = b.coverUrl { Text("封面：\(c)").font(.caption2).foregroundColor(.secondary).lineLimit(1) }
                        }
                        .font(.footnote)
                    }
                }
            }
            if !responsePreview.isEmpty {
                Section("响应正文（前 3000 字）") {
                    Text(responsePreview)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        guard let rule = source.searchUrl else { return }
        running = true
        log = []
        books = []
        responsePreview = ""
        Task {
            defer { running = false }
            do {
                let a = try AnalyzeUrl(rule, key: keyword, page: page, baseUrl: source.bookSourceUrl, source: source)
                log.append("URL: \(a.url)")
                log.append("Method: \(a.method.rawValue)")
                if let q = a.encodedQuery { log.append("Query: \(q)") }
                if let f = a.encodedForm { log.append("Form: \(f)") }
                else if let b = a.body { log.append("Body: \(b)") }
                if let c = a.charset { log.append("Charset: \(c)") }
                log.append("Headers: \(a.headerMap.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; "))")
                if a.useWebView { log.append("⚠️ 该规则需要 WebView（后续支持）") }

                let t0 = Date()
                let res = try await HTTPClient.shared.strResponse(a)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                log.append("状态: \(res.statusCode)  耗时: \(ms)ms  大小: \(res.data.count) 字节  编码: \(res.encodingUsed)")
                if res.url != a.url { log.append("重定向到: \(res.url)") }
                responsePreview = String(res.body.prefix(3000))

                // 用 ruleSearch 解析书籍列表
                let t1 = Date()
                let list = try BookListParser.parse(source: source, body: res.body, baseUrl: a.baseUrl,
                                                    redirectUrl: res.url, isSearch: true)
                let ms2 = Int(Date().timeIntervalSince(t1) * 1000)
                log.append("解析到 \(list.count) 本书  耗时: \(ms2)ms")
                books = list
            } catch {
                log.append("❌ \(error.localizedDescription)")
            }
            let recent = AppLog.lines.suffix(20)
            if !recent.isEmpty { log.append("—— 日志 ——"); log += recent }
        }
    }
}
