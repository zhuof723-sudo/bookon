import XCTest
@testable import BookOn

final class AnalyzeRuleTests: XCTestCase {

    let html = """
    <html><head><title>搜索结果</title></head><body>
    <div class="result-list">
      <div class="result-item" data-id="1">
        <h3><a href="/book/1.html">斗破苍穹</a></h3>
        <span class="author">天蚕土豆</span>
        <p class="intro">这是简介 &amp; 说明</p>
        <span class="update">2024-01-01</span>
        <a class="last" href="/book/1/999.html">第999章 大结局</a>
      </div>
      <div class="result-item" data-id="2">
        <h3><a href="https://other.com/book/2.html">武动乾坤</a></h3>
        <span class="author">天蚕土豆</span>
        <p class="intro">简介二</p>
        <span class="update">2024-02-02</span>
        <a class="last" href="/book/2/10.html">第10章</a>
      </div>
      <div class="ad">广告</div>
    </div>
    <div id="content">
      第一段<br>第二段<script>alert(1)</script>
      <p>第三段</p>
    </div>
    <ul class="toc"><li><a href="/c/1">第一章</a></li><li><a href="/c/2">第二章</a></li><li><a href="/c/3">第三章</a></li></ul>
    </body></html>
    """

    let json = """
    {"code":0,"data":{"list":[
      {"id":1,"title":"斗破苍穹","author":"天蚕土豆","tags":["玄幻","热血"],"cover":"/img/1.jpg","words":1234567,"vip":true},
      {"id":2,"title":"武动乾坤","author":"天蚕土豆","tags":["玄幻"],"cover":"/img/2.jpg","words":800000,"vip":false},
      {"id":3,"title":"大主宰","author":"天蚕土豆","tags":[],"cover":null,"words":1500000,"vip":true}
    ],"total":3}}
    """

    private func rule(_ content: Any, base: String = "https://a.com/search") -> AnalyzeRule {
        let r = AnalyzeRule()
        r.setContent(content, baseUrl: base)
        r.setRedirectUrl(base)
        return r
    }

    // MARK: - 默认语法（JSoup 风格）

    func testJSoupBookListAndFields() throws {
        let r = rule(html)
        let items = try r.getElements("class.result-item")
        XCTAssertEqual(items.count, 2)
        r.setContent(items[0])
        XCTAssertEqual(try r.getString("tag.h3@tag.a@text"), "斗破苍穹")
        XCTAssertEqual(try r.getString("class.author@text"), "天蚕土豆")
        XCTAssertEqual(try r.getString("tag.h3@tag.a@href", isUrl: true), "https://a.com/book/1.html")
        XCTAssertEqual(try r.getString("class.intro@text"), "这是简介 & 说明")
        XCTAssertEqual(try r.getString("@data-id"), "1")
        XCTAssertEqual(try r.getString("class.last@text##第|章.*##"), "999")
    }

    func testCssPrefixAndIndexes() throws {
        let r = rule(html)
        XCTAssertEqual(try r.getString("@css:.result-item h3 a@text"), "斗破苍穹\n武动乾坤")
        XCTAssertEqual(try r.getString("class.result-item.0@class.author@text"), "天蚕土豆")
        XCTAssertEqual(try r.getString("class.result-item.-1@tag.h3@text"), "武动乾坤")
        XCTAssertEqual(try r.getString("class.result-item!0@tag.h3@text"), "武动乾坤")
        XCTAssertEqual(try r.getStringList("class.toc@tag.li[1:2]@tag.a@text"), ["第二章", "第三章"])
        XCTAssertEqual(try r.getStringList("tag.li[-1:0]@text"), ["第三章", "第二章", "第一章"], "反向")
        XCTAssertEqual(try r.getString("id.content@tag.p@text"), "第三段")
    }

    func testCombinators() throws {
        let r = rule(html)
        XCTAssertEqual(try r.getString("class.nothing@text||class.author.0@text"), "天蚕土豆")
        XCTAssertEqual(try r.getStringList("class.author@text&&class.update@text"),
                       ["天蚕土豆", "天蚕土豆", "2024-01-01", "2024-02-02"])
        XCTAssertEqual(try r.getStringList("class.author@text%%class.update@text"),
                       ["天蚕土豆", "2024-01-01", "天蚕土豆", "2024-02-02"])
    }

    func testHtmlAndTextNodes() throws {
        let r = rule(html)
        let h = try r.getString("id.content@html")
        XCTAssertTrue(h.contains("第一段"))
        XCTAssertFalse(h.contains("script"), "html 模式应移除 script")
        let tn = try r.getString("id.content@textNodes")
        XCTAssertEqual(tn, "第一段\n第二段")
    }

    func testRegexReplaceAndFirst() throws {
        let r = rule(html)
        XCTAssertEqual(try r.getString("class.update.0@text##-##/"), "2024/01/01")
        XCTAssertEqual(try r.getString("class.last.0@text##第(\\d+)章.*##$1###"), "999")
        XCTAssertEqual(try r.getString("class.update.0@text##\\d{4}##YEAR###"), "YEAR")
    }

    func testPutGet() throws {
        let r = rule(html)
        r.ruleData = RuleData()
        _ = try r.getString("class.author.0@text@put:{author:class.author.0@text, year:class.update.0@text##-.*##}")
        XCTAssertEqual(r.get("author"), "天蚕土豆")
        XCTAssertEqual(r.get("year"), "2024")
        XCTAssertEqual(try r.getString("@get:{author}-@get:{year}"), "天蚕土豆-2024")
    }

    // MARK: - XPath

    func testXPath() throws {
        let r = rule(html)
        XCTAssertEqual(try r.getString("//div[@class='result-item'][1]/h3/a/text()"), "斗破苍穹")
        XCTAssertEqual(try r.getString("@XPath:(//span[@class='author'])[1]/text()"), "天蚕土豆")
        XCTAssertEqual(try r.getString("//span[@class='author'][1]/text()"), "天蚕土豆\n天蚕土豆", "标准 XPath：每个父节点下的第一个")
        XCTAssertEqual(try r.getString("//div[@class='result-item'][2]/h3/a/@href", isUrl: true), "https://other.com/book/2.html")
        XCTAssertEqual(try r.getElements("//div[@class='result-item']").count, 2)
        XCTAssertEqual(try r.getString("@XPath:count(//li)"), "3")
        let items = try r.getElements("//ul[@class='toc']/li")
        r.setContent(items[1])
        XCTAssertEqual(try r.getString("@XPath:./a/text()"), "第二章")
        XCTAssertEqual(try r.getString("//span[@class='none']/text()||//title/text()"), "搜索结果")
    }

    // MARK: - JSONPath

    func testJsonPath() throws {
        let r = rule(json)
        let list = try r.getElements("$.data.list[*]")
        XCTAssertEqual(list.count, 3)
        r.setContent(list[0])
        XCTAssertEqual(try r.getString("$.title"), "斗破苍穹")
        XCTAssertEqual(try r.getString("$.words"), "1234567", "整数不应带 .0")
        XCTAssertEqual(try r.getString("$.vip"), "true")
        XCTAssertEqual(try r.getString("$.tags"), "玄幻\n热血")
        XCTAssertEqual(try r.getString("$.cover", isUrl: true), "https://a.com/img/1.jpg")
        XCTAssertEqual(try r.getString("@json:$.author"), "天蚕土豆")
        XCTAssertEqual(try r.getString("$.missing||$.author"), "天蚕土豆")
    }

    func testJsonPathAdvanced() throws {
        let r = rule(json)
        XCTAssertEqual(try r.getStringList("$.data.list[*].title"), ["斗破苍穹", "武动乾坤", "大主宰"])
        XCTAssertEqual(try r.getStringList("$.data.list[?(@.vip==true)].title"), ["斗破苍穹", "大主宰"])
        XCTAssertEqual(try r.getStringList("$.data.list[?(@.words>1000000 && @.id!=1)].title"), ["大主宰"])
        XCTAssertEqual(try r.getStringList("$.data.list[?(@.title=~/^武.*/)].id"), ["2"])
        XCTAssertEqual(try r.getStringList("$..title"), ["斗破苍穹", "武动乾坤", "大主宰"])
        XCTAssertEqual(try r.getString("$.data.list[-1].title"), "大主宰")
        XCTAssertEqual(try r.getStringList("$.data.list[0,2].id"), ["1", "3"])
        XCTAssertEqual(try r.getStringList("$.data.list[1:].id"), ["2", "3"])
        XCTAssertEqual(try r.getString("$.data.list.length()"), "3")
        XCTAssertEqual(try r.getString("$.data.total"), "3")
        XCTAssertEqual(try r.getString("$['data']['total']"), "3")
        XCTAssertEqual(try r.getString("$.data.list[2].cover"), "")
    }

    func testJsonInlineTemplate() throws {
        let r = rule(json)
        // {$.a} 内嵌拼接（Legado 的 {$.rule} 语法）
        XCTAssertEqual(try r.getString("{$.data.list[0].title}({$.data.list[0].author})"), "斗破苍穹(天蚕土豆)")
    }

    func testDictContentDirectKeyAccess() throws {
        // content 已经是字典（如 getElements 返回的元素）时，可直接用键名
        let r = rule(["title": "abc", "n": 5])
        XCTAssertEqual(try r.getString("title"), "abc")
        XCTAssertEqual(try r.getString("n"), "5")
    }

    // MARK: - 正则模式

    func testRegexMode() throws {
        let text = "<li>第一章|/c/1</li><li>第二章|/c/2</li>"
        let r = rule(text)
        let els = try r.getElements(":<li>(.*?)\\|(.*?)</li>")
        XCTAssertEqual(els.count, 2)
        let first = els[0] as! [String]
        XCTAssertEqual(first[1], "第一章")
        XCTAssertEqual(first[2], "/c/1")
        r.setContent(first)
        XCTAssertEqual(try r.getString("$1"), "第一章")
        XCTAssertEqual(try r.getString("$2", isUrl: true), "https://a.com/c/1")
        XCTAssertEqual(try r.getString("标题：$1"), "标题：第一章")
    }

    // MARK: - RuleAnalyzer

    func testSplitRuleRespectsBrackets() {
        var a = RuleAnalyzer("div[data-x='a||b']@text||span@text")
        XCTAssertEqual(a.splitRule("&&", "||", "%%"), ["div[data-x='a||b']@text", "span@text"])
        XCTAssertEqual(a.elementsType, "||")
        var b = RuleAnalyzer("$.a[?(@.x=='1&&2')].b&&$.c")
        XCTAssertEqual(b.splitRule("&&", "||", "%%"), ["$.a[?(@.x=='1&&2')].b", "$.c"])
        var c = RuleAnalyzer("@@div.a@span@text")
        c.trim()
        XCTAssertEqual(c.splitRule("@"), ["div.a", "span", "text"])
    }

    func testLooseJsonUnquotedValues() {
        let o = JSONLoose.parseObject("{author:class.author.0@text, year:class.update.0@text##-.*##, n:1, ok:true}")
        XCTAssertEqual(o?["author"] as? String, "class.author.0@text")
        XCTAssertEqual(o?["year"] as? String, "class.update.0@text##-.*##")
        XCTAssertEqual((o?["n"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(o?["ok"] as? Bool, true)
    }

    func testJavaRegexConversion() {
        XCTAssertEqual(AnalyzeRule.convertJavaRegex("\\p{Alpha}+\\p{Digit}"), "[a-zA-Z]+\\d")
    }
}
