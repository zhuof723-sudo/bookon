import Foundation
import JavaScriptCore

/// JavaScriptCore 引擎，实现 `JSEvaluator`。
/// 每次 eval 创建独立 JSContext（与 Legado 每次新建 scope 一致），jsLib 结果按 md5 缓存后注入。
final class JSCoreEvaluator: JSEvaluator {
    static let shared = JSCoreEvaluator()

    private let vm = JSVirtualMachine()!
    private var jsLibCache: [String: String] = [:]   // md5(jsLib) -> 合并后的脚本
    private let lock = NSLock()

    func eval(_ script: String, bindings: [String: Any?]) throws -> Any? {
        let ctx = JSContext(virtualMachine: vm)!
        ctx.name = "BookOn"
        var thrown: JSValue?
        ctx.exceptionHandler = { _, e in thrown = e }

        // 注入基础对象
        let source = bindings["source"] as? BookSource
        let java: JavaBridge
        if let j = bindings["java"] as? AnalyzeRule { java = JavaBridge(analyzer: j, source: source) }
        else { java = JavaBridge(analyzer: nil, source: source) }
        ctx.setObject(java, forKeyedSubscript: "java" as NSString)
        ctx.setObject(CookieBridge.shared, forKeyedSubscript: "cookie" as NSString)
        ctx.setObject(CacheBridge.shared, forKeyedSubscript: "cache" as NSString)
        if let s = source { ctx.setObject(SourceBridge(s), forKeyedSubscript: "source" as NSString) }
        if let b = bindings["book"] as? Book { ctx.setObject(BookBridge(b, rule: (bindings["java"] as? AnalyzeRule)?.ruleData), forKeyedSubscript: "book" as NSString) }
        if let c = bindings["chapter"] as? BookChapter { ctx.setObject(ChapterBridge(c, rule: (bindings["java"] as? AnalyzeRule)?.chapterData), forKeyedSubscript: "chapter" as NSString) }

        for (k, v) in bindings where !["java", "source", "book", "chapter"].contains(k) {
            ctx.setObject(Self.toJS(v), forKeyedSubscript: k as NSString)
        }
        // Java 常用全局的兼容垫片
        ctx.evaluateScript(Self.prelude)

        // jsLib
        if let lib = source?.jsLib?.trimmingCharacters(in: .whitespacesAndNewlines), !lib.isEmpty {
            ctx.evaluateScript(try loadJsLib(lib))
            if let e = thrown { thrown = nil; AppLog.put("jsLib 执行出错: \(String(describing: e))") }
        }

        let result = ctx.evaluateScript(script)
        if let e = thrown {
            let msg = e.toString() ?? "JS 错误"
            let line = e.forProperty("line")?.toInt32() ?? 0
            let head = script.split(separator: "\n").prefix(3).joined(separator: " ").prefix(80)
            AppLog.put("JS 错误: \(msg) line \(line) — 脚本: \(head)")
            throw JSError(message: "\(msg)\(line > 0 ? " (line \(line))" : "")")
        }
        return Self.fromJS(result)
    }

    // MARK: - jsLib

    private func loadJsLib(_ lib: String) throws -> String {
        let key = CryptoUtils.hex(CryptoUtils.md5(Data(lib.utf8)))
        lock.lock(); if let c = jsLibCache[key] { lock.unlock(); return c }; lock.unlock()
        var script = lib
        if lib.hasPrefix("{"), let map = JSONLoose.parseObject(lib) {
            var parts: [String] = []
            for (_, v) in map.sorted(by: { $0.key < $1.key }) {
                guard let url = v as? String else { continue }
                if NetworkUtils.isAbsUrl(url) {
                    let fileKey = "jslib::" + CryptoUtils.hex(CryptoUtils.md5(Data(url.utf8)))
                    if let cached = AppDatabase.shared.cacheGet(fileKey) { parts.append(cached); continue }
                    let a = try AnalyzeUrl(url)
                    let res = try Self.blocking { try await HTTPClient.shared.strResponse(a) }
                    AppDatabase.shared.cachePut(fileKey, res.body)
                    parts.append(res.body)
                } else {
                    parts.append(url)
                }
            }
            script = parts.joined(separator: "\n;\n")
        }
        lock.lock(); jsLibCache[key] = script; lock.unlock()
        return script
    }

    // MARK: - 类型转换

    static func toJS(_ v: Any?) -> Any {
        guard let v else { return NSNull() }
        if let d = v as? Data { return Array(d).map { NSNumber(value: $0) } }
        return v
    }

    static func fromJS(_ v: JSValue?) -> Any? {
        guard let v, !v.isUndefined, !v.isNull else { return nil }
        if v.isString { return v.toString() }
        if v.isBoolean { return v.toBool() }
        if v.isNumber { return v.toDouble() }
        if v.isArray {
            let arr = v.toArray() ?? []
            // 字节数组（全为 0-255 整数）保留为 [NSNumber]，其它转字符串数组
            return arr
        }
        if v.isObject {
            if let s = v.toObject() as? String { return s }
            return v.toObject()
        }
        return v.toString()
    }

    /// 在 JS 同步调用中执行 async 任务（JS 线程会阻塞，与 Rhino 行为一致）
    static func blocking<T>(_ body: @escaping () async throws -> T) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!
        Task.detached {
            do { result = .success(try await body()) } catch { result = .failure(error) }
            sem.signal()
        }
        sem.wait()
        return try result.get()
    }

    /// 兼容垫片：Java 端常见的全局
    static let prelude = """
    var String = String; var JSON = JSON;
    if (typeof console === 'undefined') { var console = {}; }
    console.log = function() { var a = Array.prototype.slice.call(arguments).map(function(x){ return typeof x === 'object' ? JSON.stringify(x) : String(x); }); java.log(a.join(' ')); };
    // Java 的 String.valueOf / new java.lang.String 等在书源里偶见，做最小映射
    var Packages = {}; var javaImporter = function(){};
    function importPackage(){}
    """
}

/// 简单日志（后续接入界面的日志页）
enum AppLog {
    static var lines: [String] = []
    static func put(_ msg: String) {
        lines.append("\(Date()): \(msg)")
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        #if DEBUG
        print("[BookOn] \(msg)")
        #endif
    }
}
