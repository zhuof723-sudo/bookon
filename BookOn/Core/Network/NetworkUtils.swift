import Foundation

/// 对应 Legado `utils/NetworkUtils.kt` 中 URL 相关工具
enum NetworkUtils {

    static func isAbsUrl(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.hasPrefix("http://") || l.hasPrefix("https://")
    }

    static func isDataUrl(_ s: String) -> Bool {
        s.lowercased().hasPrefix("data:")
    }

    /// 取 scheme://host[:port]，非 http(s) 返回 nil
    static func getBaseUrl(_ url: String?) -> String? {
        guard let url, isAbsUrl(url) else { return nil }
        // "https://".count == 8，从第 9 个字符开始找 "/"
        let start = url.index(url.startIndex, offsetBy: min(9, url.count))
        if let slash = url[start...].firstIndex(of: "/") {
            return String(url[..<slash])
        }
        return url
    }

    /// 相对地址 → 绝对地址。baseURL 里若含 ",{...}" 只取前半段。
    static func getAbsoluteURL(_ baseURL: String?, _ relativePath: String) -> String {
        let rel = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL, !baseURL.isEmpty else { return rel }
        if isAbsUrl(rel) || isDataUrl(rel) { return rel }
        if rel.lowercased().hasPrefix("javascript") { return "" }
        let basePart = baseURL.components(separatedBy: ",").first ?? baseURL
        guard let base = URL(string: basePart.trimmingCharacters(in: .whitespaces)) else { return rel }
        // 允许中文等未编码字符：先尝试直接拼，失败再对相对路径做宽松编码
        if let u = URL(string: rel, relativeTo: base) { return u.absoluteString }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#[]{}|\\^`")
        if let enc = rel.addingPercentEncoding(withAllowedCharacters: allowed),
           let u = URL(string: enc, relativeTo: base) {
            return u.absoluteString
        }
        return rel
    }

    /// 域名（不带端口）。供 cookie 存取；解析失败返回原串
    static func getSubDomain(_ url: String) -> String {
        guard let base = getBaseUrl(url), let host = URL(string: base)?.host else { return url }
        if isIPAddress(host) { return host }
        // 简化版 eTLD+1：常见二级公共后缀特殊处理
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return host }
        let secondLevel: Set<String> = ["com", "net", "org", "gov", "edu", "co", "ac"]
        let tld = parts[parts.count - 1]
        let sld = parts[parts.count - 2]
        if tld.count == 2, secondLevel.contains(sld), parts.count >= 3 {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }

    static func isIPAddress(_ s: String) -> Bool {
        let v4 = s.split(separator: ".")
        if v4.count == 4, v4.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) { return true }
        return s.contains(":") && s.allSatisfy { $0.isHexDigit || $0 == ":" }
    }

    // MARK: - 编码判断（与 Legado encodedQuery / encodedForm 一致）

    private static let queryNoEncode: Set<Character> = {
        var s = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        s.formUnion("!$&()*+,-./:;=?@[\\]^_`{|}~")
        return s
    }()

    private static let formNoEncode: Set<Character> = {
        var s = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        s.formUnion("*-._")
        return s
    }()

    /// 已经是合法编码的 query（含正确 %XX 且没有需要编码的字符）返回 true
    static func encodedQuery(_ str: String) -> Bool { isEncoded(str, allowed: queryNoEncode) }
    static func encodedForm(_ str: String) -> Bool { isEncoded(str, allowed: formNoEncode) }

    private static func isEncoded(_ str: String, allowed: Set<Character>) -> Bool {
        let chars = Array(str)
        var i = 0
        var needEncode = false
        while i < chars.count {
            let c = chars[i]
            if allowed.contains(c) { i += 1; continue }
            if c == "%", i + 2 < chars.count, chars[i + 1].isHexDigit, chars[i + 2].isHexDigit {
                i += 3
                continue
            }
            needEncode = true
            break
        }
        return !needEncode
    }

    // MARK: - 字符集

    static func encoding(named name: String?) -> String.Encoding? {
        guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return nil }
        switch name {
        case "utf-8", "utf8": return .utf8
        case "gbk", "gb2312", "gb18030", "gb-2312", "gb_2312":
            let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            return String.Encoding(rawValue: cf)
        case "big5", "big-5":
            let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
            return String.Encoding(rawValue: cf)
        case "iso-8859-1", "latin1": return .isoLatin1
        case "utf-16", "utf16": return .utf16
        case "shift_jis", "shift-jis", "sjis": return .shiftJIS
        case "euc-kr": return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            }
            return nil
        }
    }

    // MARK: - 编码器

    /// Java URLEncoder.encode 语义：字母数字与 *-._ 保留，空格 → +，其他按 charset 转 %XX
    static func urlEncode(_ s: String, encoding: String.Encoding = .utf8) -> String {
        var out = ""
        for ch in s {
            if formNoEncode.contains(ch) { out.append(ch); continue }
            if ch == " " { out.append("+"); continue }
            let data = String(ch).data(using: encoding) ?? String(ch).data(using: .utf8) ?? Data()
            for b in data { out += String(format: "%%%02X", b) }
        }
        return out
    }

    private static let queryCodecSafe: Set<Character> = {
        var s = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        s.formUnion("!$%&()*+,/:;=?@[\\]^`{|}")
        return s
    }()

    /// Legado queryEncoder：RFC3986 unreserved + "!$%&()*+,/:;=?@[\]^`{|}" 保留，其余 %XX（空格 → %20）
    static func queryEncode(_ s: String, encoding: String.Encoding = .utf8) -> String {
        var out = ""
        for ch in s {
            if queryCodecSafe.contains(ch) { out.append(ch); continue }
            let data = String(ch).data(using: encoding) ?? String(ch).data(using: .utf8) ?? Data()
            for b in data { out += String(format: "%%%02X", b) }
        }
        return out
    }

    /// JavaScript escape()：字母数字与 @*_+-./ 保留，<256 → %XX，否则 %uXXXX
    static func jsEscape(_ s: String) -> String {
        let keep = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@*_+-./")
        var out = ""
        for u in s.utf16 {
            let ch = Character(UnicodeScalar(u) ?? " ")
            if u < 128, keep.contains(ch) { out.append(ch); continue }
            if u < 256 { out += String(format: "%%%02X", u) } else { out += String(format: "%%u%04X", u) }
        }
        return out
    }
}
