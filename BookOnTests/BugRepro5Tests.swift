import XCTest
@testable import BookOn

/// 针对用户报告的两个 bug：①简介乱码 ②正文加载不出来
final class BugRepro5Tests: XCTestCase {

    // ① 简介：HTML 实体 + <br> 混排，应正确显示，不出现 &amp;/&nbsp;/&#xxx; 残留
    func testIntroEntities() throws {
        let html = """
        <div class="intro">主角名叫&ldquo;萧炎&rdquo;，斗气&amp;斗技&nbsp;并存。<br>他&#30340;冒险开始了&hellip;</div>
        """
        let r = AnalyzeRule()
        r.setContent(html, baseUrl: "https://t.com")
        let intro = try r.getString("@css:.intro@text")
        // SwiftSoup text() 应已解码实体
        XCTAssertFalse(intro.contains("&amp;"), "残留 &amp;: \(intro)")
        XCTAssertFalse(intro.contains("&nbsp;"), "残留 &nbsp;: \(intro)")
        XCTAssertFalse(intro.contains("&#"), "残留数字实体: \(intro)")
        XCTAssertFalse(intro.contains("&ldquo;"), "残留 &ldquo;: \(intro)")
        XCTAssertTrue(intro.contains("萧炎"))
        XCTAssertTrue(intro.contains("的冒险"))

        // 经 HTMLFormatter.format（详情页实际走的路径）
        let formatted = HTMLFormatter.format(try r.getString("@css:.intro@html"))
        XCTAssertFalse(formatted.contains("&amp;"), "format 后残留 &amp;: \(formatted)")
        XCTAssertFalse(formatted.contains("&nbsp;"), "format 后残留 &nbsp;: \(formatted)")
        XCTAssertFalse(formatted.contains("<"), "format 后残留标签: \(formatted)")
    }

    // ② 正文：各种常见 content 规则写法都应取到正文
    func testContentRuleVariants() throws {
        let html = "<html><body><div class=\"box\"><div id=\"content\"><p>第一段</p><p>第二段</p></div></div></body></html>"
        let r = AnalyzeRule()
        r.setContent(html, baseUrl: "https://t.com")
        XCTAssertFalse(try r.getString("id.content@html").isEmpty, "id.content@html 空")
        XCTAssertFalse(try r.getString("id.content@textNodes").isEmpty, "id.content@textNodes 空")
        XCTAssertFalse(try r.getString("class.box@tag.div.0@html").isEmpty, "class 链 空")
        XCTAssertFalse(try r.getString("@css:#content@html").isEmpty, "@css:#content@html 空")
        XCTAssertFalse(try r.getString("@css:#content").isEmpty, "@css:#content 无后缀 空")
        XCTAssertEqual(try r.getString("id.content@text"), "第一段\n第二段")
    }

    // ② GBK 站点正文解码
    func testGBKContentDecode() {
        // "第一章 内容" 的 GBK 字节
        let gbkText = "第一章内容"
        let enc = NetworkUtils.encoding(named: "gbk")!
        let data = gbkText.data(using: enc)!
        let html = ("<html><head><meta charset=\"gbk\"></head><body><div id=\"content\">").data(using: .ascii)!
            + data + ("</div></body></html>").data(using: .ascii)!
        let (decoded, encName) = HTTPClient.decode(html, contentType: "text/html", preferred: nil)
        XCTAssertEqual(encName, "gbk")
        XCTAssertTrue(decoded.contains("第一章内容"), "GBK 解码失败: \(decoded)")
    }

    // ② content 规则为空 → 应取整个 body（部分书源如此配置）
    func testEmptyContentRuleFallsBackToBody() throws {
        let html = "<html><body>整本纯文本小说内容</body></html>"
        let r = AnalyzeRule()
        r.setContent(html, baseUrl: "https://t.com")
        let s = try r.getString("body@text")
        XCTAssertTrue(s.contains("整本纯文本"))
    }
}
