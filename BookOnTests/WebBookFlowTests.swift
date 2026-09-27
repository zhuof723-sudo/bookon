import XCTest
@testable import BookOn

final class WebBookFlowTests: XCTestCase {

    private func source() -> BookSource {
        let json = """
        {
          "bookSourceUrl": "https://t.com",
          "bookSourceName": "测试源",
          "bookSourceType": 0,
          "searchUrl": "https://t.com/search?q={{key}}&p={{page}}",
          "ruleSearch": {
            "bookList": "@css:.result .item",
            "name": "@css:h3 a@text",
            "author": "@css:.author@text",
            "bookUrl": "@css:h3 a@href",
            "coverUrl": "@css:img@src",
            "lastChapter": "@css:.last@text"
          },
          "ruleBookInfo": {
            "name": "@css:.info h1@text",
            "author": "@css:.info .author@text",
            "intro": "@css:.info .intro@text",
            "coverUrl": "@css:.info img@src",
            "kind": "@css:.info .tag@text",
            "lastChapter": "@css:.info .last@text",
            "tocUrl": "@css:.info .toc-link@href"
          },
          "ruleToc": {
            "chapterList": "@css:.chapter-list li",
            "chapterName": "@css:a@text",
            "chapterUrl": "@css:a@href"
          },
          "ruleContent": {
            "content": "@css:#content@html"
          }
        }
        """
        return try! LegadoJSON.decoder().decode(BookSource.self, from: Data(json.utf8))
    }

    func testSearchListParsing() throws {
        let html = """
        <div class="result">
          <div class="item"><h3><a href="/book/1">斗破苍穹</a></h3><span class="author">天蚕土豆</span><img src="/c/1.jpg"><span class="last">第100章</span></div>
          <div class="item"><h3><a href="https://t.com/book/2">武动乾坤</a></h3><span class="author">天蚕土豆</span><img src="/c/2.jpg"><span class="last">第50章</span></div>
        </div>
        """
        let list = try BookListParser.parse(source: source(), body: html, baseUrl: "https://t.com",
                                            redirectUrl: "https://t.com/search", isSearch: true, js: UnavailableJSEvaluator())
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].name, "斗破苍穹")
        XCTAssertEqual(list[0].author, "天蚕土豆")
        XCTAssertEqual(list[0].bookUrl, "https://t.com/book/1")
        XCTAssertEqual(list[0].coverUrl, "https://t.com/c/1.jpg")
        XCTAssertEqual(list[0].latestChapterTitle, "第100章")
        XCTAssertEqual(list[1].bookUrl, "https://t.com/book/2")
    }

    func testBookInfoParsing() throws {
        let html = """
        <div class="info">
          <h1>斗破苍穹</h1><span class="author">天蚕土豆</span>
          <span class="tag">玄幻</span><span class="last">第1623章 大结局</span>
          <img src="/cover.jpg"><p class="intro">少年闯荡斗气大陆。</p>
          <a class="toc-link" href="/book/1/toc">目录</a>
        </div>
        """
        var book = Book(); book.bookUrl = "https://t.com/book/1"; book.origin = "https://t.com"
        try BookInfoParser.parse(source: source(), book: &book, baseUrl: "https://t.com/book/1",
                                 redirectUrl: "https://t.com/book/1", body: html, js: UnavailableJSEvaluator())
        XCTAssertEqual(book.name, "斗破苍穹")
        XCTAssertEqual(book.author, "天蚕土豆")
        XCTAssertEqual(book.kind, "玄幻")
        XCTAssertEqual(book.latestChapterTitle, "第1623章 大结局")
        XCTAssertEqual(book.coverUrl, "https://t.com/cover.jpg")
        XCTAssertEqual(book.intro, "少年闯荡斗气大陆。")
        XCTAssertEqual(book.tocUrl, "https://t.com/book/1/toc")
    }

    func testChapterListParsing() async throws {
        let html = """
        <ul class="chapter-list">
          <li><a href="/c/1">第一章 陨落的天才</a></li>
          <li><a href="/c/2">第二章 斗气大陆</a></li>
          <li><a href="/c/3">第三章 客卿</a></li>
        </ul>
        """
        var book = Book(); book.bookUrl = "https://t.com/book/1"
        let toc = try await BookChapterListParser.parse(source: source(), book: book, baseUrl: "https://t.com/book/1/toc",
                                                        redirectUrl: "https://t.com/book/1/toc", body: html, js: UnavailableJSEvaluator())
        XCTAssertEqual(toc.count, 3)
        XCTAssertEqual(toc[0].title, "第一章 陨落的天才")
        XCTAssertEqual(toc[0].url, "https://t.com/c/1")
        XCTAssertEqual(toc[0].index, 0)
        XCTAssertEqual(toc[2].index, 2)
    }

    func testChapterListReverse() async throws {
        var s = source()
        s.ruleToc?.chapterList = "-@css:.chapter-list li"   // 反转
        let html = "<ul class='chapter-list'><li><a href='/c/1'>一</a></li><li><a href='/c/2'>二</a></li></ul>"
        var book = Book(); book.bookUrl = "https://t.com/b"
        let toc = try await BookChapterListParser.parse(source: s, book: book, baseUrl: "https://t.com",
                                                        redirectUrl: "https://t.com", body: html, js: UnavailableJSEvaluator())
        XCTAssertEqual(toc.map(\.title), ["二", "一"])
    }

    func testContentParsing() async throws {
        let html = """
        <div id="content"><p>第一段内容。</p><p>第二段内容。</p><script>ad()</script></div>
        """
        var book = Book(); book.bookUrl = "https://t.com/book/1"
        var chapter = BookChapter(); chapter.url = "https://t.com/c/1"; chapter.title = "第一章"
        let text = try await BookContentParser.parse(source: source(), book: book, chapter: chapter,
                                                     baseUrl: "https://t.com/c/1", redirectUrl: "https://t.com/c/1",
                                                     body: html, nextChapterUrl: nil, js: UnavailableJSEvaluator())
        XCTAssertTrue(text.contains("第一段内容。"))
        XCTAssertTrue(text.contains("第二段内容。"))
        XCTAssertFalse(text.contains("ad()"), "应去除 script")
    }

    func testContentReplaceRegex() async throws {
        var s = source()
        s.ruleContent?.replaceRegex = "##广告.*?章节##"
        let html = "<div id='content'>正文开始广告插入这里章节正文结束</div>"
        var book = Book(); book.bookUrl = "https://t.com/b"
        var chapter = BookChapter(); chapter.url = "https://t.com/c"
        let text = try await BookContentParser.parse(source: s, book: book, chapter: chapter,
                                                     baseUrl: "https://t.com/c", redirectUrl: "https://t.com/c",
                                                     body: html, nextChapterUrl: nil, js: UnavailableJSEvaluator())
        XCTAssertFalse(text.contains("广告"))
        XCTAssertTrue(text.contains("正文开始"))
        XCTAssertTrue(text.contains("正文结束"))
    }
}
