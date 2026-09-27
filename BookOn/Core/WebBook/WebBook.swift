import Foundation

/// 对应 Legado `WebBook`：把「构造 URL → 请求 → 解析」串起来的高层接口
enum WebBook {
    private static let js: JSEvaluator = JSCoreEvaluator.shared

    // MARK: - 搜索

    static func search(source: BookSource, key: String, page: Int = 1) async throws -> [SearchBook] {
        guard let searchUrl = source.searchUrl, !searchUrl.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let a = try AnalyzeUrl(searchUrl, key: key, page: page, baseUrl: source.bookSourceUrl, source: source, js: js)
        let res = try await HTTPClient.shared.strResponse(a)
        return try BookListParser.parse(source: source, body: res.body, baseUrl: a.baseUrl,
                                        redirectUrl: res.url, isSearch: true, js: js)
    }

    // MARK: - 发现

    static func explore(source: BookSource, url: String, page: Int = 1) async throws -> [SearchBook] {
        let a = try AnalyzeUrl(url, page: page, baseUrl: source.bookSourceUrl, source: source, js: js)
        let res = try await HTTPClient.shared.strResponse(a)
        return try BookListParser.parse(source: source, body: res.body, baseUrl: a.baseUrl,
                                        redirectUrl: res.url, isSearch: false, js: js)
    }

    // MARK: - 详情

    static func bookInfo(source: BookSource, book: Book) async throws -> Book {
        var b = book
        let a = try AnalyzeUrl(book.bookUrl, baseUrl: source.bookSourceUrl, source: source, js: js)
        let res = try await HTTPClient.shared.strResponse(a)
        try BookInfoParser.parse(source: source, book: &b, baseUrl: book.bookUrl, redirectUrl: res.url, body: res.body, js: js)
        if b.tocUrl.isEmpty { b.tocUrl = res.url }
        return b
    }

    /// 从搜索结果生成一本可入库的 Book
    static func toBook(_ s: SearchBook) -> Book {
        var b = Book()
        b.bookUrl = s.bookUrl
        b.tocUrl = s.bookUrl
        b.origin = s.origin
        b.originName = s.originName
        b.name = s.name
        b.author = s.author
        b.kind = s.kind
        b.coverUrl = s.coverUrl
        b.intro = s.intro
        b.wordCount = s.wordCount
        b.latestChapterTitle = s.latestChapterTitle
        b.variable = s.variable
        b.type = BookType.text
        return b
    }

    // MARK: - 目录

    static func chapterList(source: BookSource, book: Book) async throws -> [BookChapter] {
        let tocUrl = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl
        let a = try AnalyzeUrl(tocUrl, baseUrl: source.bookSourceUrl, source: source, js: js)
        let res = try await HTTPClient.shared.strResponse(a)
        return try await BookChapterListParser.parse(source: source, book: book, baseUrl: tocUrl,
                                                     redirectUrl: res.url, body: res.body, js: js)
    }

    // MARK: - 正文

    static func content(source: BookSource, book: Book, chapter: BookChapter, nextChapterUrl: String?) async throws -> String {
        let a = try AnalyzeUrl(chapter.url, baseUrl: chapter.baseUrl.isEmpty ? source.bookSourceUrl : chapter.baseUrl,
                               source: source, js: js, bindings: ["book": book, "chapter": chapter, "nextChapterUrl": nextChapterUrl])
        // 正文页可能需要执行 content.webJs（这里作为 @js 附加，简化处理）
        let res = try await HTTPClient.shared.strResponse(a)
        return try await BookContentParser.parse(source: source, book: book, chapter: chapter, baseUrl: chapter.url,
                                                redirectUrl: res.url, body: res.body, nextChapterUrl: nextChapterUrl, js: js)
    }
}
