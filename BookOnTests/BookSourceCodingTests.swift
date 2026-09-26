import XCTest
@testable import BookOn

final class BookSourceCodingTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")!
        return try Data(contentsOf: url)
    }

    func testDecodeLegadoDefaultSources() throws {
        let data = try fixture("legado_default_sources")
        let list = try LegadoJSON.decoder().decode([BookSource].self, from: data)
        XCTAssertEqual(list.count, 1)
        let s = list[0]
        XCTAssertEqual(s.bookSourceName, "消消乐听书")
        XCTAssertEqual(s.bookSourceUrl, "https://www.kaixin7days.com")
        XCTAssertEqual(s.sourceType, .audio)
        XCTAssertEqual(s.ruleSearch?.bookList, "$.content.content")
        XCTAssertEqual(s.ruleToc?.chapterName, "$.chapterTitle")
        XCTAssertNotNil(s.ruleContent?.payAction)
        XCTAssertTrue(s.hasExplore)
        XCTAssertTrue(s.hasLogin)
        XCTAssertEqual(s.lastUpdateTime, 1630656684531)
    }

    func testRoundTripKeepsAllFields() throws {
        let data = try fixture("legado_default_sources")
        let list = try LegadoJSON.decoder().decode([BookSource].self, from: data)
        let encoded = try LegadoJSON.encoder().encode(list)
        let again = try LegadoJSON.decoder().decode([BookSource].self, from: encoded)
        XCTAssertEqual(again[0].bookSourceUrl, list[0].bookSourceUrl)
        XCTAssertEqual(again[0].ruleSearch, list[0].ruleSearch)
        XCTAssertEqual(again[0].ruleToc, list[0].ruleToc)
        XCTAssertEqual(again[0].ruleContent, list[0].ruleContent)
        XCTAssertEqual(again[0].exploreUrl, list[0].exploreUrl)

        // 原始 JSON 中的每个顶层键，在导出时都应存在
        let original = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let exported = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        for key in original[0].keys {
            XCTAssertNotNil(exported[0][key], "缺少字段 \(key)")
        }
    }

    func testLenientVariants() throws {
        // 数值写成字符串、布尔写成 0/1、规则对象写成字符串——都应能解析
        let json = """
        {
          "bookSourceUrl": "https://a.com",
          "bookSourceName": "A",
          "bookSourceType": "1",
          "enabled": 0,
          "enabledExplore": "true",
          "customOrder": "5",
          "lastUpdateTime": 1.7e12,
          "ruleSearch": "{\\"bookList\\":\\"@css:li\\",\\"name\\":\\"a@text\\"}",
          "ruleToc": {}
        }
        """
        let s = try LegadoJSON.decoder().decode(BookSource.self, from: Data(json.utf8))
        XCTAssertEqual(s.bookSourceType, 1)
        XCTAssertFalse(s.enabled)
        XCTAssertTrue(s.enabledExplore)
        XCTAssertEqual(s.customOrder, 5)
        XCTAssertEqual(s.lastUpdateTime, 1_700_000_000_000)
        XCTAssertEqual(s.ruleSearch?.bookList, "@css:li")
        XCTAssertEqual(s.ruleSearch?.name, "a@text")
        XCTAssertNotNil(s.ruleToc)
    }

    func testFailableArraySkipsBadItems() throws {
        let json = """
        [ {"bookSourceUrl":"https://ok.com","bookSourceName":"ok"}, 123, "garbage", {"bookSourceName":"no url"} ]
        """
        let items = try LegadoJSON.decoder().decode([Failable<BookSource>].self, from: Data(json.utf8))
        let valid = items.compactMap(\.value).filter { !$0.bookSourceUrl.isEmpty }
        XCTAssertEqual(valid.count, 1)
        XCTAssertEqual(valid[0].bookSourceName, "ok")
    }

    func testGroupsSplit() {
        var s = BookSource()
        s.bookSourceGroup = "小说, 精品；听书;女频，"
        XCTAssertEqual(s.groups, ["小说", "精品", "听书", "女频"])
    }
}
