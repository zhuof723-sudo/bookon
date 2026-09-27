import XCTest
@testable import BookOn

/// 联网集成测试：用 App 的真实代码跑「🍅木里番茄0922[GO聚合版]」，定位运行时问题。
/// 需要在有网环境运行（CI）。失败信息里会打印阶段诊断。
final class LiveFanqieTests: XCTestCase {

    private var source: BookSource!

    override func setUpWithError() throws {
        let url = Bundle(for: Self.self).url(forResource: "fanqie_go", withExtension: "json")!
        source = try LegadoJSON.decoder().decode([BookSource].self, from: Data(contentsOf: url))[0]
    }

    func testFullFlow() async throws {
        // 1) 搜索
        let list = try await WebBook.search(source: source, key: "斩神", page: 1)
        XCTAssertFalse(list.isEmpty, "搜索无结果")
        let first = try XCTUnwrap(list.first)
        XCTAssertTrue(first.name.contains("斩神"), "搜索首条: \(first.name)")

        // 2) 详情
        var book = WebBook.toBook(first)
        let info = try await WebBook.bookInfo(source: source, book: book)
        book = info
        XCTAssertFalse(book.name.isEmpty)
        XCTAssertFalse(book.author.isEmpty, "作者为空")
        let intro = book.displayIntro ?? ""
        XCTAssertFalse(intro.isEmpty, "简介为空")
        XCTContext.runActivity(named: "intro head: \(intro.prefix(120))") { _ in }
        XCTAssertFalse(intro.hasPrefix("<div") && intro.contains("style="), "简介疑似 <useweb> 未渲染（前 80 字：\(intro.prefix(80))）")

        // 3) 目录
        let toc = try await WebBook.chapterList(source: source, book: book)
        XCTAssertFalse(toc.isEmpty, "目录为空")
        XCTAssertTrue(toc.count > 100, "目录数量异常: \(toc.count)")
        let ch0 = toc[0]
        XCTAssertFalse(ch0.title.isEmpty, "首章标题为空")
        XCTAssertTrue(ch0.url.hasPrefix("http"), "章节 URL 非绝对: \(ch0.url)")

        // 4) 正文（第 3 章）
        let ch = toc[min(2, toc.count - 1)]
        let next = toc.indices.contains(ch.index + 1) ? toc[ch.index + 1].url : nil
        let text = try await WebBook.content(source: source, book: book, chapter: ch, nextChapterUrl: next)
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "正文为空（chapter: \(ch.title)）")
        XCTAssertTrue(text.count > 200, "正文过短: \(text.count) 字")
        XCTAssertFalse(text.contains("<div style="), "正文疑似未净化 HTML（前 100 字：\(text.prefix(100))）")

        // 5) 再取一次（走缓存/一致性）
        let text2 = try await WebBook.content(source: source, book: book, chapter: ch, nextChapterUrl: next)
        XCTAssertEqual(text.count, text2.count, "两次正文长度不一致")
    }
}
