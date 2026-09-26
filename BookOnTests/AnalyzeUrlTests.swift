import XCTest
@testable import BookOn

final class AnalyzeUrlTests: XCTestCase {

    func testSimpleGetWithKeyAndPage() throws {
        let a = try AnalyzeUrl("https://a.com/search?q={{key}}&p={{page}}", key: "斗破", page: 2)
        XCTAssertEqual(a.method, .get)
        XCTAssertEqual(a.urlNoQuery, "https://a.com/search")
        XCTAssertEqual(a.encodedQuery, "q=%E6%96%97%E7%A0%B4&p=2")
        let req = try a.makeRequest()
        XCTAssertEqual(req.url?.absoluteString, "https://a.com/search?q=%E6%96%97%E7%A0%B4&p=2")
    }

    func testPostFormWithOptions() throws {
        let rule = "https://a.com/s,{\"method\":\"POST\",\"body\":\"searchkey={{key}}&page={{page}}\",\"charset\":\"gbk\"}"
        let a = try AnalyzeUrl(rule, key: "斗破", page: 1)
        XCTAssertEqual(a.method, .post)
        XCTAssertEqual(a.url, "https://a.com/s")
        XCTAssertEqual(a.charset, "gbk")
        // 斗破 GBK: B6 B7 C6 C6
        XCTAssertEqual(a.encodedForm, "searchkey=%B6%B7%C6%C6&page=1")
        let req = try a.makeRequest()
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: req.httpBody!, encoding: .utf8), "searchkey=%B6%B7%C6%C6&page=1")
    }

    func testPostJsonBody() throws {
        let rule = "https://a.com/api,{\"method\":\"POST\",\"body\":{\"title\":\"{{key}}\",\"pageNum\":{{page}}}}"
        let a = try AnalyzeUrl(rule, key: "abc", page: 3)
        XCTAssertEqual(a.method, .post)
        XCTAssertNil(a.encodedForm)
        let body = try XCTUnwrap(a.body)
        let obj = try JSONSerialization.jsonObject(with: Data(body.utf8)) as! [String: Any]
        XCTAssertEqual(obj["title"] as? String, "abc")
        XCTAssertEqual(obj["pageNum"] as? Int, 3)
        XCTAssertEqual(try a.makeRequest().value(forHTTPHeaderField: "Content-Type"), "application/json; charset=UTF-8")
    }

    func testHeadersOptionAndRetry() throws {
        let rule = "https://a.com/x,{\"headers\":{\"Referer\":\"https://a.com\",\"X-Token\":\"t\"},\"retry\":2,\"webView\":true}"
        let a = try AnalyzeUrl(rule)
        XCTAssertEqual(a.headerMap["Referer"], "https://a.com")
        XCTAssertEqual(a.headerMap["X-Token"], "t")
        XCTAssertEqual(a.retry, 2)
        XCTAssertTrue(a.useWebView)
        XCTAssertNotNil(a.headerMap["User-Agent"])
    }

    func testLooseOptionJson() throws {
        // 单引号 + 未加引号 key，Legado 宽松模式能解析
        let rule = "https://a.com/x,{method:'POST', body:'a=1',}"
        let a = try AnalyzeUrl(rule)
        XCTAssertEqual(a.method, .post)
        XCTAssertEqual(a.encodedForm, "a=1")
    }

    func testRelativeUrlAndBaseUrl() throws {
        let a = try AnalyzeUrl("/search.html?k={{key}}", key: "x", baseUrl: "https://b.com/dir/page.html,{\"x\":1}")
        XCTAssertEqual(a.url, "https://b.com/search.html?k=x")
        XCTAssertEqual(a.baseUrl, "https://b.com")
    }

    func testPagePattern() throws {
        let a1 = try AnalyzeUrl("https://a.com/list_<1,2,3>.html", page: 1)
        XCTAssertEqual(a1.url, "https://a.com/list_1.html")
        let a3 = try AnalyzeUrl("https://a.com/list_<1,2,3>.html", page: 3)
        XCTAssertEqual(a3.url, "https://a.com/list_3.html")
        let a9 = try AnalyzeUrl("https://a.com/list_<1,2,3>.html", page: 9)
        XCTAssertEqual(a9.url, "https://a.com/list_3.html", "超出范围取最后一个")
    }

    func testPageArithmetic() throws {
        let a = try AnalyzeUrl("https://a.com/p/{{page-1}}?n={{page+10}}", page: 5)
        XCTAssertEqual(a.url, "https://a.com/p/4?n=15")
    }

    func testAlreadyEncodedQueryNotDoubleEncoded() throws {
        let a = try AnalyzeUrl("https://a.com/s?q=%E6%96%97&x=1")
        XCTAssertEqual(a.encodedQuery, "q=%E6%96%97&x=1")
    }

    func testEscapeCharset() throws {
        let rule = "https://a.com/s,{\"method\":\"POST\",\"body\":\"k={{key}}\",\"charset\":\"escape\"}"
        let a = try AnalyzeUrl(rule, key: "斗破 a")
        XCTAssertEqual(a.encodedForm, "k=%u6597%u7834%20a")
    }

    func testJsRequiresEngine() {
        // JS 引擎未接入时应明确报错而不是产生错误 URL
        XCTAssertThrowsError(try AnalyzeUrl("@js:'https://a.com/' + key", key: "k"))
        XCTAssertThrowsError(try AnalyzeUrl("https://a.com/{{java.md5Encode(key)}}", key: "k"))
    }

    func testJsWithStubEngine() throws {
        struct Stub: JSEvaluator {
            func eval(_ script: String, bindings: [String: Any?]) throws -> Any? {
                if script.contains("md5") { return "MD5X" }
                if script.trimmingCharacters(in: .whitespaces) == "'https://a.com/' + key" {
                    return "https://a.com/" + ((bindings["key"] ?? nil) as? String ?? "")
                }
                return Double(42)
            }
        }
        let a = try AnalyzeUrl("https://a.com/{{java.md5Encode(key)}}?n={{1+41}}", key: "k", js: Stub())
        XCTAssertEqual(a.url, "https://a.com/MD5X?n=42", "整数型 Double 不应带 .0")

        let b = try AnalyzeUrl("@js:'https://a.com/' + key", key: "zz", js: Stub())
        XCTAssertEqual(b.url, "https://a.com/zz")

        // Legado 语义：<js> 后若还有文本，需用 @result 引用脚本结果
        let c = try AnalyzeUrl("<js>'https://a.com/' + key</js>@result,{\"method\":\"POST\"}", key: "q", js: Stub())
        XCTAssertEqual(c.url, "https://a.com/q")
        XCTAssertEqual(c.method, .post)
    }

    func testSourceHeaderJson() throws {
        var s = BookSource()
        s.bookSourceUrl = "https://a.com"
        s.header = "{\"User-Agent\":\"MyUA\",\"Cookie\":\"a=b\"}"
        let a = try AnalyzeUrl("/x", baseUrl: s.bookSourceUrl, source: s)
        XCTAssertEqual(a.headerMap["User-Agent"], "MyUA")
        XCTAssertEqual(a.headerMap["Cookie"], "a=b")
        XCTAssertEqual(a.domain, "a.com")
    }

    func testCharsetDecodeGBK() {
        let gbk = Data([0xB6, 0xB7, 0xC6, 0xC6]) // 斗破
        let (s1, e1) = HTTPClient.decode(gbk, contentType: "text/html; charset=gbk", preferred: nil)
        XCTAssertEqual(s1, "斗破"); XCTAssertEqual(e1, "gbk")
        let html = "<html><head><meta charset=\"gb2312\"></head>".data(using: .utf8)! + gbk
        let (s2, e2) = HTTPClient.decode(html, contentType: "text/html", preferred: nil)
        XCTAssertTrue(s2.hasSuffix("斗破")); XCTAssertEqual(e2, "gb2312")
        let (s3, _) = HTTPClient.decode(gbk, contentType: nil, preferred: nil)
        XCTAssertEqual(s3, "斗破", "非法 UTF-8 应回退到 GB18030")
    }

    func testNetworkUtils() {
        XCTAssertEqual(NetworkUtils.getBaseUrl("https://a.com:8080/x/y?z"), "https://a.com:8080")
        XCTAssertEqual(NetworkUtils.getBaseUrl("https://a.com"), "https://a.com")
        XCTAssertNil(NetworkUtils.getBaseUrl("ftp://a.com"))
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("https://a.com/b/c.html", "../d.html"), "https://a.com/d.html")
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("https://a.com/b/", "//cdn.com/x.png"), "https://cdn.com/x.png")
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("https://a.com", "javascript:void(0)"), "")
        XCTAssertEqual(NetworkUtils.getSubDomain("https://www.x.com.cn/a"), "x.com.cn")
        XCTAssertEqual(NetworkUtils.getSubDomain("https://m.book.example.org/a"), "example.org")
        XCTAssertEqual(NetworkUtils.getSubDomain("http://192.168.1.1:8080/"), "192.168.1.1")
    }
}
