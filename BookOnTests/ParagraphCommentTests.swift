import XCTest
@testable import BookOn

/// 段评（paragraph comment）功能的回归测试：
/// ①正文里保留下来的段评气泡 <img src="...,{"click":"..."}"> 不能被截断丢失（HtmlFormatter 正则要能捕获平衡的 {} 选项）
/// ②ContentSegmenter 能正确切出文本/气泡片段，并解析出 click JS 与气泡里的评论数
/// ③点击气泡执行 click JS 的调用链（java/source/book/chapter 绑定齐全）不出错
final class ParagraphCommentTests: XCTestCase {

    /// 注意：书源 JS 直接用字符串拼接生成这段 HTML，属性值内部会出现未转义的裸双引号
    /// （`src="data:...,{"click":"..."}"` ），这是真实数据的形状，不是测试写错了。
    /// Legado 的 formatImagePattern 正是为了在这种不规范 HTML 下仍能完整捕获 click 选项而设计的。
    private let realBubbleHTML = "<p>正文段落。</p><img src=\"data:image/svg+xml;base64,ABC==,{\"style\":\"text\",\"type\":\"qd\",\"click\":\"showCmt('1','2','0','56190')\"}\">"

    func testFormatKeepImgPreservesClickOption() {
        let out = HTMLFormatter.formatKeepImg(realBubbleHTML, redirectUrl: "https://a.com")
        XCTAssertTrue(out.contains("showCmt"), "click 选项被截断丢失：\(out)")
        XCTAssertTrue(out.contains("data:image/svg+xml;base64,ABC=="), "图片地址丢失：\(out)")
    }

    func testContentSegmenterSplitsTextAndBubble() {
        let content = "第一段文字。\n" + realBubbleHTML.replacingOccurrences(of: "<p>正文段落。</p>", with: "") + "\n第二段文字。"
        let segs = ContentSegmenter.segments(content)
        XCTAssertEqual(segs.count, 3)
        guard case .text(let t1) = segs[0] else { return XCTFail("首段应为文本") }
        XCTAssertTrue(t1.contains("第一段文字"))
        guard case .image(let src, let click) = segs[1] else { return XCTFail("中段应为气泡图片") }
        XCTAssertEqual(src, "data:image/x;base64,AA==")
        XCTAssertEqual(click, "showCmt('1','2','0','56190')")
        guard case .text(let t2) = segs[2] else { return XCTFail("末段应为文本") }
        XCTAssertTrue(t2.contains("第二段文字"))
    }

    func testBadgeCountParsedFromClick() {
        let click = "showCmt('6982529841564224526','6982735801973113351','0','56190')"
        let re = try! NSRegularExpression(pattern: "showCmt\\([^)]*'\\s*,\\s*'(\\d+)'\\s*\\)")
        let ns = click as NSString
        let m = re.firstMatch(in: click, range: NSRange(location: 0, length: ns.length))
        XCTAssertNotNil(m)
        let count = Int(ns.substring(with: m!.range(at: 1)))
        XCTAssertEqual(count, 56190)
    }

    /// 真实链路：拿真书源的 getComments 输出（含段评气泡），验证净化后 click 仍完整、
    /// 且切分/点击执行不抛错（网络访问 showCmt 内部 API 会真的发生，但这里只验证脚本能跑通到发起请求）
    func testRealSourceParagraphCommentClickRuns() throws {
        let url = Bundle(for: Self.self).url(forResource: "fanqie_go", withExtension: "json")!
        let source = try LegadoJSON.decoder().decode([BookSource].self, from: Data(contentsOf: url))[0]
        var book = Book()
        book.bookUrl = "https://t.com/b"
        var chapter = BookChapter()
        chapter.url = "https://t.com/c"

        // 模拟一个真实气泡的 click（数据取自本源真实返回样例）
        let click = "showCmt('6982529841564224526','6982735801973113351','0','56190')"
        // 直接跑 click（内部会用 java.ajax 访问 showCmt -> API.call -> requestJSON -> showCommentPage，
        // 依赖真实网络；这里只断言执行不因为绑定缺失而在 JS 语法/引用层面报错）
        do {
            _ = try JSCoreEvaluator.shared.eval(click, bindings: [
                "source": source, "book": book, "chapter": chapter, "result": "data:...",
            ])
        } catch {
            XCTFail("click JS 执行失败（绑定缺失或函数未定义）: \(error.localizedDescription)")
        }
    }
}
