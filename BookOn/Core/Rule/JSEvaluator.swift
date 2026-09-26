import Foundation

/// JS 执行器协议。第 4 步用 JavaScriptCore 实现；此处先定义接口，
/// 让 AnalyzeUrl / 规则引擎可以先写完并测试。
protocol JSEvaluator {
    /// 执行脚本，`bindings` 注入为全局变量（java/source/book/result/key/page/baseUrl…）
    func eval(_ script: String, bindings: [String: Any?]) throws -> Any?
}

struct JSError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 未接入引擎前的占位：遇到脚本直接报错，避免静默产生错误 URL
struct UnavailableJSEvaluator: JSEvaluator {
    func eval(_ script: String, bindings: [String: Any?]) throws -> Any? {
        throw JSError(message: "JS 引擎尚未接入（第 4 步）")
    }
}

/// 将 JS 结果转成字符串（与 Legado 处理一致：整数型 Double 不带 .0）
enum JSValueFormat {
    static func string(_ v: Any?) -> String {
        guard let v else { return "" }
        if let s = v as? String { return s }
        if let d = v as? Double {
            if d.truncatingRemainder(dividingBy: 1) == 0, abs(d) < 1e15 { return String(Int64(d)) }
            return String(d)
        }
        if let i = v as? Int { return String(i) }
        if let b = v as? Bool { return b ? "true" : "false" }
        if v is NSNull { return "" }
        return String(describing: v)
    }
}
