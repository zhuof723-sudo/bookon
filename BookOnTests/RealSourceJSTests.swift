import XCTest
@testable import BookOn

/// 用真实书源（🍅木里番茄0922[GO聚合版]）验证 jsLib 加载与 this/java/source 作用域
final class RealSourceJSTests: XCTestCase {

    private func source() throws -> BookSource {
        let url = Bundle(for: Self.self).url(forResource: "fanqie_go", withExtension: "json")!
        return try LegadoJSON.decoder().decode([BookSource].self, from: Data(contentsOf: url))[0]
    }

    func testSourceDecodes() throws {
        let s = try source()
        XCTAssertEqual(s.bookSourceName, "🍅木里番茄0922[GO聚合版]")
        XCTAssertFalse((s.jsLib ?? "").isEmpty)
        XCTAssertTrue((s.searchUrl ?? "").hasPrefix("@js:"))
        XCTAssertNotNil(s.ruleContent?.content)
    }

    /// jsLib 里的纯函数应可调用（验证 jsLib 已注入当前作用域）
    func testJsLibPureHelpers() throws {
        let s = try source()
        let js = JSCoreEvaluator.shared
        XCTAssertEqual(try js.eval("queryValue('http://x/api?book_id=123&q=45','book_id')", bindings: ["source": s]) as? String, "123")
        XCTAssertEqual(JSValueFormat.string(try js.eval("moduleFromUrl('http://x?ys_module=8', 3)", bindings: ["source": s])), "8")
        XCTAssertEqual(JSValueFormat.string(try js.eval("bookTypeForModule(8)", bindings: ["source": s])), "64")
    }

    /// this.java / this.source 作用域：GET/SET 依赖它们
    func testThisScopeBindings() throws {
        let s = try source()
        let js = JSCoreEvaluator.shared
        // this 在全局应为全局对象，this.java / this.source 可访问
        XCTAssertEqual(try js.eval("(typeof this.java)", bindings: ["source": s]) as? String, "object")
        XCTAssertEqual(try js.eval("(typeof this.source)", bindings: ["source": s]) as? String, "object")
        XCTAssertEqual(try js.eval("(typeof GET)", bindings: ["source": s]) as? String, "function", "jsLib 的 GET 未注入")
        XCTAssertEqual(try js.eval("(typeof java.sleep)", bindings: ["source": s]) as? String, "function", "java.sleep 缺失")
        XCTAssertEqual(try js.eval("(typeof java.getThemeConfig)", bindings: ["source": s]) as? String, "function")
    }

    /// GET/SET 变量存取应通过 source.getVariable/setVariable 正常工作
    func testGetSetVariable() throws {
        let s = try source()
        let js = JSCoreEvaluator.shared
        _ = try js.eval("SET('module', 8)", bindings: ["source": s])
        XCTAssertEqual(JSValueFormat.string(try js.eval("GET('module')", bindings: ["source": s])), "8")
    }
}
