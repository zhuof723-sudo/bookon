import Foundation

/// 搜索结果条目（对应 Legado `SearchBook` 的核心字段）
struct SearchBook: Identifiable, Equatable {
    var id: String { bookUrl }
    var bookUrl: String
    var origin: String
    var originName: String
    var name: String
    var author: String
    var kind: String?
    var coverUrl: String?
    var intro: String?
    var wordCount: String?
    var latestChapterTitle: String?
    var variable: String?
}

/// 对应 Legado `BookList.analyzeBookList`：用 ruleSearch / ruleExplore 从页面解析出书籍列表
enum BookListParser {

    static func parse(source: BookSource, body: String, baseUrl: String, redirectUrl: String,
                      isSearch: Bool, js: JSEvaluator = UnavailableJSEvaluator()) throws -> [SearchBook] {
        let listRule: String?
        var fields: (name: String?, author: String?, kind: String?, intro: String?, cover: String?, url: String?, words: String?, last: String?)
        if isSearch, let r = source.ruleSearch {
            listRule = r.bookList
            fields = (r.name, r.author, r.kind, r.intro, r.coverUrl, r.bookUrl, r.wordCount, r.lastChapter)
        } else if let r = source.ruleExplore {
            listRule = r.bookList
            fields = (r.name, r.author, r.kind, r.intro, r.coverUrl, r.bookUrl, r.wordCount, r.lastChapter)
        } else {
            return []
        }
        guard var listR = listRule, !listR.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let analyzer = AnalyzeRule(ruleData: RuleData(), source: source, js: js)
        analyzer.setContent(body, baseUrl: baseUrl)
        analyzer.setRedirectUrl(redirectUrl)

        // Legado：以 "-" 开头表示反转列表；"+" 开头表示 allInOne（正则一次取全部字段）
        var reverse = false
        if listR.hasPrefix("-") { reverse = true; listR.removeFirst() }
        var allInOne = false
        if listR.hasPrefix("+") { allInOne = true; listR.removeFirst() }

        let elements = try analyzer.getElements(listR)
        var books: [SearchBook] = []

        if allInOne, let rows = elements as? [[String]] {
            // 正则 allInOne：每行 [全文, $1, $2...]
            for row in rows {
                let a = AnalyzeRule(ruleData: RuleData(), source: source, js: js)
                a.setContent(row, baseUrl: baseUrl); a.setRedirectUrl(redirectUrl)
                if let b = try make(a, fields, source) { books.append(b) }
            }
        } else {
            for el in elements {
                let a = AnalyzeRule(ruleData: RuleData(), source: source, js: js)
                a.setContent(el, baseUrl: baseUrl); a.setRedirectUrl(redirectUrl)
                if let b = try make(a, fields, source) { books.append(b) }
            }
        }
        // 去重（按 bookUrl）
        var seen = Set<String>()
        books = books.filter { seen.insert($0.bookUrl).inserted }
        return reverse ? books.reversed() : books
    }

    private static func make(_ a: AnalyzeRule,
                             _ f: (name: String?, author: String?, kind: String?, intro: String?, cover: String?, url: String?, words: String?, last: String?),
                             _ source: BookSource) throws -> SearchBook? {
        let name = try a.getString(f.name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let url = try a.getString(f.url, isUrl: true)
        guard !url.isEmpty else { return nil }
        var b = SearchBook(bookUrl: url, origin: source.bookSourceUrl, originName: source.bookSourceName,
                           name: name, author: try a.getString(f.author).trimmingCharacters(in: .whitespacesAndNewlines))
        let kinds = try a.getStringList(f.kind) ?? []
        b.kind = kinds.isEmpty ? nil : kinds.joined(separator: ",")
        b.intro = try a.getString(f.intro).nilIfEmpty
        b.coverUrl = try a.getString(f.cover, isUrl: true).nilIfEmpty
        b.wordCount = try a.getString(f.words).nilIfEmpty
        b.latestChapterTitle = try a.getString(f.last).nilIfEmpty
        b.variable = a.ruleData?.variable
        return b
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
