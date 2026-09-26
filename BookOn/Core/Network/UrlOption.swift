import Foundation

/// 对应 Legado `AnalyzeUrl.UrlOption`：`url,{...}` 逗号后的 JSON 选项
struct UrlOption {
    var method: String?
    var charset: String?
    var headers: [String: String]?
    var body: String?
    var origin: String?
    var retry: Int = 0
    var type: String?
    var webView: Bool = false
    var webJs: String?
    var dnsIp: String?
    var js: String?
    var bodyJs: String?
    var serverID: Int64?
    var webViewDelayTime: Int64 = 0

    /// 解析选项 JSON。Legado 先严格解析，失败再宽松解析（允许单引号/尾逗号等）
    static func parse(_ text: String) -> UrlOption? {
        guard let obj = JSONLoose.parseObject(text) else { return nil }
        var o = UrlOption()
        o.method = str(obj["method"])
        o.charset = str(obj["charset"])
        o.origin = str(obj["origin"])
        o.type = str(obj["type"])
        o.webJs = str(obj["webJs"])
        o.dnsIp = str(obj["dnsIp"])
        o.js = str(obj["js"])
        o.bodyJs = str(obj["bodyJs"])
        if let r = obj["retry"] { o.retry = Int(str(r) ?? "") ?? 0 }
        if let s = obj["serverID"] { o.serverID = Int64(str(s) ?? "") }
        if let d = obj["webViewDelayTime"] { o.webViewDelayTime = max(0, Int64(str(d) ?? "") ?? 0) }

        switch obj["webView"] ?? NSNull() {
        case is NSNull: o.webView = false
        case let s as String: o.webView = !(s.isEmpty || s == "false")
        case let n as NSNumber: o.webView = n.boolValue
        default: o.webView = true
        }

        // headers：对象或含 JSON 的字符串
        if let h = obj["headers"] as? [String: Any] {
            o.headers = h.reduce(into: [:]) { $0[$1.key] = str($1.value) ?? "" }
        } else if let hs = obj["headers"] as? String, let h = JSONLoose.parseObject(hs) {
            o.headers = h.reduce(into: [:]) { $0[$1.key] = str($1.value) ?? "" }
        }

        // body：字符串原样；对象/数组 → 紧凑 JSON
        let rawBody = obj["body"] ?? NSNull()
        switch rawBody {
        case is NSNull: o.body = nil
        case let s as String: o.body = s.isEmpty ? nil : s
        default:
            if JSONSerialization.isValidJSONObject(rawBody),
               let d = try? JSONSerialization.data(withJSONObject: rawBody, options: [.withoutEscapingSlashes]) {
                o.body = String(decoding: d, as: UTF8.self)
            }
        }
        return o
    }

    private static func str(_ v: Any?) -> String? {
        guard let v, !(v is NSNull) else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber {
            if n.doubleValue == n.doubleValue.rounded() { return String(n.int64Value) }
            return n.stringValue
        }
        if let b = v as? Bool { return b ? "true" : "false" }
        return String(describing: v)
    }
}

/// 宽松 JSON 解析：先标准解析，失败则尝试修复常见不规范写法
/// （单引号、未加引号的 key、尾逗号、注释）。近似 Gson 的 lenient 模式。
enum JSONLoose {
    static func parseObject(_ text: String) -> [String: Any]? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = t.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) as? [String: Any] {
            return o
        }
        let fixed = repair(t)
        if let d = fixed.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return o
        }
        return nil
    }

    /// 简单修复器：状态机逐字符处理
    static func repair(_ s: String) -> String {
        var out = ""
        let chars = Array(s)
        var i = 0
        var inString = false
        var quote: Character = "\""
        while i < chars.count {
            let c = chars[i]
            if inString {
                if c == "\\" && i + 1 < chars.count {
                    let n = chars[i + 1]
                    if n == quote && quote == "'" { out.append("'") }
                    else { out.append(c); out.append(n) }
                    i += 2; continue
                }
                if c == quote { inString = false; out.append("\""); i += 1; continue }
                if c == "\"" { out += "\\\""; i += 1; continue }
                out.append(c); i += 1; continue
            }
            // 注释
            if c == "/" && i + 1 < chars.count {
                if chars[i + 1] == "/" {
                    while i < chars.count && chars[i] != "\n" { i += 1 }
                    continue
                }
                if chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i += 2; continue
                }
            }
            if c == "\"" || c == "'" { inString = true; quote = c; out.append("\""); i += 1; continue }
            // 尾逗号
            if c == "," {
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" { i += 1; continue }
            }
            // 未加引号的 key
            if c.isLetter || c == "_" || c == "$" {
                var j = i
                var word = ""
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "$" {
                    word.append(chars[j]); j += 1
                }
                var k = j
                while k < chars.count, chars[k].isWhitespace { k += 1 }
                if k < chars.count, chars[k] == ":", !["true", "false", "null"].contains(word) {
                    out += "\"\(word)\""
                } else {
                    out += word
                }
                i = j; continue
            }
            out.append(c); i += 1
        }
        return out
    }
}
