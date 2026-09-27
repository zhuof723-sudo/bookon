import XCTest
@testable import BookOn

final class JSEngineTests: XCTestCase {

    let js = JSCoreEvaluator.shared

    func testBasicEval() throws {
        XCTAssertEqual(JSValueFormat.string(try js.eval("1 + 41", bindings: [:])), "42")
        XCTAssertEqual(try js.eval("'a' + key", bindings: ["key": "b"]) as? String, "ab")
        XCTAssertEqual(try js.eval("result.toUpperCase()", bindings: ["result": "x"]) as? String, "X")
        XCTAssertEqual(JSValueFormat.string(try js.eval("page + 1", bindings: ["page": 2])), "3")
    }

    func testJsErrorIsThrown() {
        XCTAssertThrowsError(try js.eval("undefinedFn()", bindings: [:])) { e in
            XCTAssertTrue(e.localizedDescription.contains("undefinedFn"), e.localizedDescription)
        }
    }

    func testJavaEncoding() throws {
        XCTAssertEqual(try js.eval("java.md5Encode('abc')", bindings: [:]) as? String, "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(try js.eval("java.md5Encode16('abc')", bindings: [:]) as? String, "3cd24fb0d6963f7d")
        XCTAssertEqual(try js.eval("java.base64Encode('斗破')", bindings: [:]) as? String, "5paX56C0")
        XCTAssertEqual(try js.eval("java.base64Decode('5paX56C0')", bindings: [:]) as? String, "斗破")
        XCTAssertEqual(try js.eval("java.hexEncodeToString('ab')", bindings: [:]) as? String, "6162")
        XCTAssertEqual(try js.eval("java.hexDecodeToString('6162')", bindings: [:]) as? String, "ab")
        XCTAssertEqual(try js.eval("java.encodeURI('斗 破')", bindings: [:]) as? String, "%E6%96%97+%E7%A0%B4")
        XCTAssertEqual(try js.eval("java.digestHex('abc','SHA-256')", bindings: [:]) as? String,
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try js.eval("java.HMacHex('abc','HmacSHA256','k')", bindings: [:]) as? String,
                       "342e519ce0ad6c03a36b98eeb3f1d130db4813b9df4d1160eda488d712dc78ee")
        XCTAssertEqual((try js.eval("java.strToBytes('ab')", bindings: [:]) as? [NSNumber])?.map(\.intValue), [97, 98])
        XCTAssertEqual(try js.eval("java.bytesToStr([97,98])", bindings: [:]) as? String, "ab")
    }

    func testAES() throws {
        // AES/CBC/PKCS5Padding，key/iv 16 字节，往返一致
        let script = """
        var c = java.createSymmetricCrypto('AES/CBC/PKCS5Padding', '1234567890abcdef', 'abcdef1234567890');
        var enc = c.encryptBase64('hello 斗破');
        c.decryptStr(enc)
        """
        XCTAssertEqual(try js.eval(script, bindings: [:]) as? String, "hello 斗破")

        // 已知向量：AES-128-ECB, key "1234567890abcdef", plaintext "hello" → base64
        let ecb = "java.createSymmetricCrypto('AES/ECB/PKCS5Padding', '1234567890abcdef').encryptBase64('hello')"
        let out = try js.eval(ecb, bindings: [:]) as? String
        XCTAssertEqual(out, "OuG/HtvQGRTDeeep6ZO/WQ==")
        XCTAssertEqual(try js.eval("java.aesBase64DecodeToString('OuG/HtvQGRTDeeep6ZO/WQ==','1234567890abcdef','AES/ECB/PKCS5Padding','')", bindings: [:]) as? String, "hello")
        // hex 输入自动识别
        XCTAssertEqual(try js.eval("java.createSymmetricCrypto('AES/ECB/PKCS5Padding', '1234567890abcdef').decryptStr('3ae1bf1edbd01914c379e7a9e993bf59')", bindings: [:]) as? String, "hello")
    }

    func testDES() throws {
        let script = """
        var c = java.createSymmetricCrypto('DESede/CBC/PKCS5Padding', '123456789012345678901234', '12345678');
        c.decryptStr(c.encryptHex('abc'))
        """
        XCTAssertEqual(try js.eval(script, bindings: [:]) as? String, "abc")
    }

    func testPutGetAndSource() throws {
        var s = BookSource()
        s.bookSourceUrl = "https://js.test"
        s.bookSourceName = "JS测试"
        let r = AnalyzeRule(ruleData: RuleData(), source: s, js: js)
        r.setContent("<a>x</a>")
        XCTAssertEqual(try r.getString("@js:java.put('k','v'); java.get('k') + source.bookSourceName"), "vJS测试")
        XCTAssertEqual(try r.getString("<js>source.putLoginHeader('{\"Authorization\":\"Bearer t\"}'); source.getLoginHeader()</js>"),
                       "{\"Authorization\":\"Bearer t\"}")
        XCTAssertEqual(try r.getString("@js:source.getLoginHeaderMap().Authorization"), "Bearer t")
        XCTAssertEqual(try r.getString("@js:cache.put('ck','cv'); cache.get('ck')"), "cv")
        XCTAssertEqual(try r.getString("@js:cookie.setCookie('https://js.test','a=1; b=2'); cookie.getKey('https://js.test','b')"), "2")
    }

    func testJsInRuleChain() throws {
        let r = AnalyzeRule(js: js)
        r.setContent("<div><a href='/b/1'>斗破苍穹</a></div>", baseUrl: "https://a.com")
        r.setRedirectUrl("https://a.com")
        XCTAssertEqual(try r.getString("tag.a@text@js:result + '!'"), "斗破苍穹!")
        XCTAssertEqual(try r.getString("tag.a@href@js:'https://a.com' + result"), "https://a.com/b/1")
        XCTAssertEqual(try r.getString("tag.a@text##(.+)##<$1>"), "<斗破苍穹>")
        // java.getString 在 JS 内再取规则
        XCTAssertEqual(try r.getString("@js:java.getString('tag.a@text') + '/' + java.getString('tag.a@href', true)"), "斗破苍穹/https://a.com/b/1")
    }

    func testJsLibInjected() throws {
        var s = BookSource()
        s.bookSourceUrl = "https://lib.test"
        s.jsLib = "function double(x){ return x * 2 } var K = 'lib';"
        let r = AnalyzeRule(source: s, js: js)
        r.setContent("x")
        XCTAssertEqual(try r.getString("@js:double(21) + K"), "42lib")
    }

    func testAnalyzeUrlWithRealJS() throws {
        let a = try AnalyzeUrl("https://a.com/{{java.md5Encode(key)}}?p={{page*2}}", key: "a", page: 3, js: js)
        XCTAssertEqual(a.url, "https://a.com/0cc175b9c0f1b6a831c399e269772661?p=6")
        let b = try AnalyzeUrl("@js:'https://a.com/s?k=' + java.encodeURI(key) + '&t=' + java.md5Encode('x').length", key: "斗", js: js)
        XCTAssertEqual(b.url, "https://a.com/s?k=%E6%96%97&t=32")
        let c = try AnalyzeUrl("https://a.com/x,{\"method\":\"POST\",\"body\":\"sign={{java.md5Encode('k'+page)}}\"}", page: 1, js: js)
        XCTAssertEqual(c.encodedForm, "sign=\(CryptoUtils.hex(CryptoUtils.md5(Data("k1".utf8))))")
    }

    func testHelpers() throws {
        XCTAssertEqual(try js.eval("java.toNumChapter('第一百二十章 试炼')", bindings: [:]) as? String, "第120章 试炼")
        XCTAssertEqual(try js.eval("java.t2s('龍門')", bindings: [:]) as? String, "龙门")
        XCTAssertEqual(try js.eval("java.s2t('龙门')", bindings: [:]) as? String, "龍門")
        XCTAssertEqual(try js.eval("java.htmlFormat('<p>一</p><p>二&nbsp;三</p>')", bindings: [:]) as? String, "　　一\n　　二 三")
        XCTAssertEqual(try js.eval("java.toURL('https://a.com:8080/p/q?x=1&y=2').getQuery('y')", bindings: [:]) as? String, "2")
        XCTAssertEqual(try js.eval("java.toURL('/p', 'https://a.com/x/').href", bindings: [:]) as? String, "https://a.com/p")
        XCTAssertEqual((try js.eval("java.randomUUID()", bindings: [:]) as? String)?.count, 36)
        XCTAssertEqual(try js.eval("java.timeFormatUTC(0, 'yyyy-MM-dd HH:mm', 8)", bindings: [:]) as? String, "1970-01-01 08:00")
        XCTAssertEqual(ChineseNumber.toInt("一千零二十五"), 1025)
        XCTAssertEqual(ChineseNumber.toInt("两百"), 200)
        XCTAssertEqual(ChineseNumber.toInt("十二"), 12)
        XCTAssertEqual(ChineseNumber.toInt("一二三"), 123)
        XCTAssertEqual(ChineseNumber.toInt("１２"), 12)
    }

    func testDefaultSourceExploreJsShape() throws {
        // 默认书源（消消乐听书）的 exploreUrl 是纯 JS，依赖网络。这里只验证脚本能被正确切分识别，不真正联网。
        let data = try Data(contentsOf: Bundle(for: Self.self).url(forResource: "legado_default_sources", withExtension: "json")!)
        let s = try LegadoJSON.decoder().decode([BookSource].self, from: data)[0]
        XCTAssertTrue(s.exploreUrl!.hasPrefix("@js:"))
        let ns = s.exploreUrl! as NSString
        let m = AnalyzeUrl.jsRegex.firstMatch(in: s.exploreUrl!, range: NSRange(location: 0, length: ns.length))
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.range.location, 0)
    }
}
