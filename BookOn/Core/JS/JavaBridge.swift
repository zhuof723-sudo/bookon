import Foundation
import JavaScriptCore
import SwiftSoup

// 说明：JSExport 不支持 Swift 重载与默认参数，所以每个 JS 可见方法都是唯一签名。
// JS 端多参数调用时缺省参数为 undefined → 这里用 JSValue 接收并判断。

@objc protocol JavaBridgeExport: JSExport {
    // 网络
    func ajax(_ url: JSValue) -> String
    func connect(_ url: String, _ header: JSValue, _ timeout: JSValue) -> StrResponseBridge
    func ajaxAll(_ urls: [String]) -> [StrResponseBridge]
    func get(_ url: String, _ headers: JSValue) -> ConnResponseBridge
    func post(_ url: String, _ body: String, _ headers: JSValue) -> ConnResponseBridge
    func head(_ url: String, _ headers: JSValue) -> ConnResponseBridge
    // 变量 / cookie / 缓存
    func put(_ key: String, _ value: String) -> String
    func get(_ key: String) -> String
    func getCookie(_ tag: String, _ key: JSValue) -> String
    func cacheFile(_ url: String, _ saveTime: JSValue) -> String
    func getString(_ rule: JSValue, _ isUrl: JSValue) -> String
    func getStringList(_ rule: JSValue, _ isUrl: JSValue) -> [String]
    func getElement(_ rule: String) -> Any?
    func getElements(_ rule: String) -> [Any]
    func setContent(_ content: JSValue, _ baseUrl: JSValue) -> JavaBridge
    // 编码
    func base64Encode(_ str: JSValue, _ flags: JSValue) -> String
    func base64Decode(_ str: JSValue, _ charset: JSValue) -> String
    func base64DecodeToByteArray(_ str: JSValue, _ flags: JSValue) -> [NSNumber]?
    func base64EncodeBytes(_ bytes: JSValue) -> String
    func hexDecodeToByteArray(_ hex: String) -> [NSNumber]?
    func hexDecodeToString(_ hex: String) -> String?
    func hexEncodeToString(_ str: String) -> String
    func strToBytes(_ str: String, _ charset: JSValue) -> [NSNumber]
    func bytesToStr(_ bytes: JSValue, _ charset: JSValue) -> String
    func encodeURI(_ str: String, _ enc: JSValue) -> String
    func htmlFormat(_ str: String) -> String
    // 摘要 / 加密
    func md5Encode(_ str: String) -> String
    func md5Encode16(_ str: String) -> String
    func digestHex(_ data: String, _ algorithm: String) -> String
    func digestBase64Str(_ data: String, _ algorithm: String) -> String
    func HMacHex(_ data: String, _ algorithm: String, _ key: String) -> String
    func HMacBase64(_ data: String, _ algorithm: String, _ key: String) -> String
    func createSymmetricCrypto(_ transformation: String, _ key: JSValue, _ iv: JSValue) -> SymmetricCryptoBridge
    func aesDecodeToString(_ str: String, _ key: String, _ transformation: String, _ iv: String) -> String?
    func aesBase64DecodeToString(_ str: String, _ key: String, _ transformation: String, _ iv: String) -> String?
    func aesEncodeToString(_ data: String, _ key: String, _ transformation: String, _ iv: String) -> String?
    func aesEncodeToBase64String(_ data: String, _ key: String, _ transformation: String, _ iv: String) -> String?
    func desDecodeToString(_ data: String, _ key: String, _ transformation: String, _ iv: String) -> String?
    func desBase64DecodeToString(_ data: String, _ key: String, _ transformation: String, _ iv: String) -> String?
    func desEncodeToString(_ data: String, _ key: String, _ transformation: String, _ iv: String) -> String?
    func desEncodeToBase64String(_ data: String, _ key: String, _ transformation: String, _ iv: String) -> String?
    func tripleDESDecodeStr(_ data: String, _ key: String, _ mode: String, _ padding: String, _ iv: String) -> String?
    func tripleDESEncodeBase64Str(_ data: String, _ key: String, _ mode: String, _ padding: String, _ iv: String) -> String?
    // 时间 / 文本
    func timeFormat(_ time: JSValue) -> String
    func timeFormatUTC(_ time: JSValue, _ format: String, _ sh: JSValue) -> String
    func t2s(_ text: String) -> String
    func s2t(_ text: String) -> String
    func toNumChapter(_ s: JSValue) -> String?
    func randomUUID() -> String
    func androidId() -> String
    func getWebViewUA() -> String
    func toURL(_ url: String, _ baseUrl: JSValue) -> JsURLBridge
    // 调试
    func log(_ msg: JSValue) -> JSValue
    func logType(_ any: JSValue)
    func toast(_ msg: JSValue)
    func longToast(_ msg: JSValue)
    // 尚未支持（占位，返回空并记录日志）
    func webView(_ html: JSValue, _ url: JSValue, _ js: JSValue) -> String?
    func startBrowser(_ url: String, _ title: String)
    func importScript(_ path: String) -> String
    func getVerificationCode(_ imageUrl: String) -> String
}

@objc final class JavaBridge: NSObject, JavaBridgeExport {
    weak var analyzer: AnalyzeRule?
    let source: BookSource?
    private lazy var ownAnalyzer = AnalyzeRule(ruleData: RuleData(), source: source, js: JSCoreEvaluator.shared)

    init(analyzer: AnalyzeRule?, source: BookSource?) {
        self.analyzer = analyzer
        self.source = source
    }

    private var rule: AnalyzeRule { analyzer ?? ownAnalyzer }

    private func str(_ v: JSValue?) -> String? {
        guard let v, !v.isUndefined, !v.isNull else { return nil }
        return v.toString()
    }
    private func map(_ v: JSValue?) -> [String: String]? {
        guard let v, !v.isUndefined, !v.isNull else { return nil }
        if v.isString, let o = JSONLoose.parseObject(v.toString()) { return o.mapValues { JSONPath.stringOf($0) } }
        if let d = v.toDictionary() as? [String: Any] { return d.mapValues { JSONPath.stringOf($0) } }
        return nil
    }
    private func bytes(_ v: JSValue?) -> Data? {
        guard let v, !v.isUndefined, !v.isNull else { return nil }
        if v.isString { return v.toString().data(using: .utf8) }
        if let arr = v.toArray() as? [NSNumber] { return Data(arr.map { UInt8(truncatingIfNeeded: $0.intValue) }) }
        return nil
    }
    private func encoding(_ v: JSValue?) -> String.Encoding {
        NetworkUtils.encoding(named: str(v)) ?? .utf8
    }

    // MARK: 网络

    func ajax(_ url: JSValue) -> String {
        var u = url.toString() ?? ""
        if url.isArray, let first = url.toArray()?.first { u = String(describing: first) }
        do {
            let a = try AnalyzeUrl(u, source: source, js: JSCoreEvaluator.shared)
            return try JSCoreEvaluator.blocking { try await HTTPClient.shared.strResponse(a) }.body
        } catch {
            AppLog.put("ajax(\(u)) error: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    func connect(_ url: String, _ header: JSValue, _ timeout: JSValue) -> StrResponseBridge {
        do {
            let a = try AnalyzeUrl(url, source: source, headers: map(header), js: JSCoreEvaluator.shared)
            let r = try JSCoreEvaluator.blocking { try await HTTPClient.shared.strResponse(a) }
            return StrResponseBridge(r)
        } catch {
            AppLog.put("connect(\(url)) error: \(error.localizedDescription)")
            return StrResponseBridge(url: url, body: error.localizedDescription, code: 0, headers: [:])
        }
    }

    func ajaxAll(_ urls: [String]) -> [StrResponseBridge] {
        urls.map { connect($0, JSValue(undefinedIn: JSContext.current()), JSValue(undefinedIn: JSContext.current())) }
    }

    private func simple(_ method: String, _ url: String, _ body: String?, _ headers: JSValue) -> ConnResponseBridge {
        var opt: [String: Any] = ["method": method]
        if let h = map(headers) { opt["headers"] = h }
        if let b = body { opt["body"] = b }
        let optStr = (try? JSONSerialization.data(withJSONObject: opt)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let r = connect("\(url),\(optStr)", JSValue(undefinedIn: JSContext.current()), JSValue(undefinedIn: JSContext.current()))
        return ConnResponseBridge(r)
    }
    func get(_ url: String, _ headers: JSValue) -> ConnResponseBridge { simple("GET", url, nil, headers) }
    func post(_ url: String, _ body: String, _ headers: JSValue) -> ConnResponseBridge { simple("POST", url, body, headers) }
    func head(_ url: String, _ headers: JSValue) -> ConnResponseBridge { simple("HEAD", url, nil, headers) }

    // MARK: 变量

    func put(_ key: String, _ value: String) -> String { rule.put(key, value) }
    func get(_ key: String) -> String { rule.get(key) }

    func getCookie(_ tag: String, _ key: JSValue) -> String {
        if let k = str(key), !k.isEmpty { return CookieStore.shared.getKey(tag, k) }
        return CookieStore.shared.cookieHeader(for: tag) ?? ""
    }

    func cacheFile(_ url: String, _ saveTime: JSValue) -> String {
        let key = "cacheFile::" + CryptoUtils.hex(CryptoUtils.md5(Data(url.utf8)))
        if let c = AppDatabase.shared.cacheGet(key) { return c }
        let body = ajax(JSValue(object: url, in: JSContext.current()))
        let ttl = saveTime.isNumber ? Int(saveTime.toInt32()) : 0
        AppDatabase.shared.cachePut(key, body, ttlSeconds: ttl)
        return body
    }

    func getString(_ r: JSValue, _ isUrl: JSValue) -> String {
        (try? rule.getString(str(r), isUrl: isUrl.isBoolean && isUrl.toBool())) ?? ""
    }
    func getStringList(_ r: JSValue, _ isUrl: JSValue) -> [String] {
        (try? rule.getStringList(str(r), isUrl: isUrl.isBoolean && isUrl.toBool())) ?? []
    }
    func getElement(_ r: String) -> Any? { JavaBridge.jsSafe(try? rule.getElement(r)) }
    func getElements(_ r: String) -> [Any] { ((try? rule.getElements(r)) ?? []).map { JavaBridge.jsSafe($0) ?? NSNull() } }

    /// SwiftSoup Element / libxml 节点无法直接进 JS，转为 HTML 字符串；JSON 对象原样
    static func jsSafe(_ v: Any?) -> Any? {
        guard let v else { return nil }
        if let e = v as? SwiftSoup.Element { return (try? e.outerHtml()) ?? "" }
        if let n = v as? XMLDoc.Node { return n.asString }
        if let arr = v as? [Any] { return arr.map { jsSafe($0) ?? NSNull() } }
        return v
    }
    func setContent(_ content: JSValue, _ baseUrl: JSValue) -> JavaBridge {
        if let c = JSCoreEvaluator.fromJS(content) { rule.setContent(c, baseUrl: str(baseUrl)) }
        return self
    }

    // MARK: 编码

    func base64Encode(_ s: JSValue, _ flags: JSValue) -> String {
        guard let d = bytes(s) else { return "" }
        var out = d.base64EncodedString()
        if flags.isNumber, flags.toInt32() & 8 != 0 { // URL_SAFE
            out = out.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        if flags.isNumber, flags.toInt32() & 1 != 0 { // NO_PADDING
            out = out.replacingOccurrences(of: "=", with: "")
        }
        return out
    }
    func base64Decode(_ s: JSValue, _ charset: JSValue) -> String {
        guard let t = str(s), let d = CryptoUtils.base64Decode(t) else { return "" }
        return String(data: d, encoding: encoding(charset)) ?? String(decoding: d, as: UTF8.self)
    }
    func base64DecodeToByteArray(_ s: JSValue, _ flags: JSValue) -> [NSNumber]? {
        guard let t = str(s), let d = CryptoUtils.base64Decode(t) else { return nil }
        return d.map { NSNumber(value: $0) }
    }
    func base64EncodeBytes(_ b: JSValue) -> String { bytes(b)?.base64EncodedString() ?? "" }
    func hexDecodeToByteArray(_ hex: String) -> [NSNumber]? { CryptoUtils.fromHex(hex)?.map { NSNumber(value: $0) } }
    func hexDecodeToString(_ hex: String) -> String? { CryptoUtils.fromHex(hex).map { String(decoding: $0, as: UTF8.self) } }
    func hexEncodeToString(_ s: String) -> String { CryptoUtils.hex(Data(s.utf8)) }
    func strToBytes(_ s: String, _ charset: JSValue) -> [NSNumber] {
        (s.data(using: encoding(charset)) ?? Data()).map { NSNumber(value: $0) }
    }
    func bytesToStr(_ b: JSValue, _ charset: JSValue) -> String {
        guard let d = bytes(b) else { return "" }
        return String(data: d, encoding: encoding(charset)) ?? String(decoding: d, as: UTF8.self)
    }
    func encodeURI(_ s: String, _ enc: JSValue) -> String { NetworkUtils.urlEncode(s, encoding: encoding(enc)) }
    func htmlFormat(_ s: String) -> String { HTMLFormatter.format(s) }

    // MARK: 摘要 / 加密

    func md5Encode(_ s: String) -> String { CryptoUtils.hex(CryptoUtils.md5(Data(s.utf8))) }
    func md5Encode16(_ s: String) -> String { String(md5Encode(s).dropFirst(8).prefix(16)) }
    func digestHex(_ data: String, _ algorithm: String) -> String {
        CryptoUtils.digest(algorithm, Data(data.utf8)).map(CryptoUtils.hex) ?? ""
    }
    func digestBase64Str(_ data: String, _ algorithm: String) -> String {
        CryptoUtils.digest(algorithm, Data(data.utf8))?.base64EncodedString() ?? ""
    }
    func HMacHex(_ data: String, _ algorithm: String, _ key: String) -> String {
        CryptoUtils.hmac(algorithm, key: Data(key.utf8), Data(data.utf8)).map(CryptoUtils.hex) ?? ""
    }
    func HMacBase64(_ data: String, _ algorithm: String, _ key: String) -> String {
        CryptoUtils.hmac(algorithm, key: Data(key.utf8), Data(data.utf8))?.base64EncodedString() ?? ""
    }
    func createSymmetricCrypto(_ transformation: String, _ key: JSValue, _ iv: JSValue) -> SymmetricCryptoBridge {
        SymmetricCryptoBridge(transformation, key: bytes(key) ?? Data(), iv: bytes(iv))
    }
    private func sym(_ t: String, _ key: String, _ iv: String) -> SymmetricCryptoBridge {
        SymmetricCryptoBridge(t, key: Data(key.utf8), iv: iv.isEmpty ? nil : Data(iv.utf8))
    }
    func aesDecodeToString(_ s: String, _ key: String, _ t: String, _ iv: String) -> String? { sym(t, key, iv).decryptStr(s) }
    func aesBase64DecodeToString(_ s: String, _ key: String, _ t: String, _ iv: String) -> String? { sym(t, key, iv).decryptStr(s) }
    func aesEncodeToString(_ d: String, _ key: String, _ t: String, _ iv: String) -> String? { sym(t, key, iv).encryptHex(d) }
    func aesEncodeToBase64String(_ d: String, _ key: String, _ t: String, _ iv: String) -> String? { sym(t, key, iv).encryptBase64(d) }
    func desDecodeToString(_ d: String, _ key: String, _ t: String, _ iv: String) -> String? { sym(t, key, iv).decryptStr(d) }
    func desBase64DecodeToString(_ d: String, _ key: String, _ t: String, _ iv: String) -> String? { sym(t, key, iv).decryptStr(d) }
    func desEncodeToString(_ d: String, _ key: String, _ t: String, _ iv: String) -> String? { sym(t, key, iv).encryptHex(d) }
    func desEncodeToBase64String(_ d: String, _ key: String, _ t: String, _ iv: String) -> String? { sym(t, key, iv).encryptBase64(d) }
    func tripleDESDecodeStr(_ d: String, _ key: String, _ mode: String, _ padding: String, _ iv: String) -> String? {
        sym("DESede/\(mode)/\(padding)", key, iv).decryptStr(d)
    }
    func tripleDESEncodeBase64Str(_ d: String, _ key: String, _ mode: String, _ padding: String, _ iv: String) -> String? {
        sym("DESede/\(mode)/\(padding)", key, iv).encryptBase64(d)
    }

    // MARK: 时间 / 文本

    func timeFormat(_ time: JSValue) -> String {
        let ms = time.isNumber ? time.toDouble() : Double(time.toString() ?? "") ?? 0
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
    func timeFormatUTC(_ time: JSValue, _ format: String, _ sh: JSValue) -> String {
        let ms = time.isNumber ? time.toDouble() : Double(time.toString() ?? "") ?? 0
        let f = DateFormatter(); f.dateFormat = format
        f.timeZone = TimeZone(secondsFromGMT: (sh.isNumber ? Int(sh.toInt32()) : 0) * 3600)
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
    func t2s(_ text: String) -> String { ChineseConverter.toSimplified(text) }
    func s2t(_ text: String) -> String { ChineseConverter.toTraditional(text) }
    func toNumChapter(_ s: JSValue) -> String? {
        guard let t = str(s) else { return nil }
        return ChineseNumber.convertChapterTitle(t)
    }
    func randomUUID() -> String { UUID().uuidString.lowercased() }
    func androidId() -> String { DeviceID.value }
    func getWebViewUA() -> String { HTTPClient.defaultUA }
    func toURL(_ url: String, _ baseUrl: JSValue) -> JsURLBridge { JsURLBridge(url, base: str(baseUrl)) }

    // MARK: 调试

    func log(_ msg: JSValue) -> JSValue { AppLog.put("JS: \(msg.toString() ?? "")"); return msg }
    func logType(_ any: JSValue) { AppLog.put("JS type: \(any.isString ? "string" : any.isNumber ? "number" : any.isArray ? "array" : any.isObject ? "object" : "?")") }
    func toast(_ msg: JSValue) { AppLog.put("toast: \(msg.toString() ?? "")"); Toast.show(msg.toString() ?? "") }
    func longToast(_ msg: JSValue) { toast(msg) }

    // MARK: 未支持

    func webView(_ html: JSValue, _ url: JSValue, _ js: JSValue) -> String? {
        AppLog.put("java.webView 暂未支持"); return nil
    }
    func startBrowser(_ url: String, _ title: String) { AppLog.put("java.startBrowser 暂未支持: \(url)") }
    func importScript(_ path: String) -> String {
        if NetworkUtils.isAbsUrl(path) { return cacheFile(path, JSValue(undefinedIn: JSContext.current())) }
        return ""
    }
    func getVerificationCode(_ imageUrl: String) -> String { AppLog.put("java.getVerificationCode 暂未支持"); return "" }
}

// MARK: - 辅助桥接对象

@objc protocol StrResponseExport: JSExport {
    func body() -> String
    func code() -> Int
    func url() -> String
    func headers() -> [String: String]
    func header(_ name: String) -> String?
    func isSuccessful() -> Bool
    func message() -> String
    func toString() -> String
}

@objc final class StrResponseBridge: NSObject, StrResponseExport {
    private let _url: String, _body: String, _code: Int, _headers: [String: String]
    init(_ r: StrResponse) { _url = r.url; _body = r.body; _code = r.statusCode; _headers = r.headers }
    init(url: String, body: String, code: Int, headers: [String: String]) { _url = url; _body = body; _code = code; _headers = headers }
    func body() -> String { _body }
    func code() -> Int { _code }
    func url() -> String { _url }
    func headers() -> [String: String] { _headers }
    func header(_ name: String) -> String? { _headers.first { $0.key.lowercased() == name.lowercased() }?.value }
    func isSuccessful() -> Bool { (200..<300).contains(_code) }
    func message() -> String { HTTPURLResponse.localizedString(forStatusCode: _code) }
    func toString() -> String { _body }
}

/// Jsoup Connection.Response 的子集（java.get/post/head 返回）
@objc protocol ConnResponseExport: JSExport {
    func body() -> String
    func statusCode() -> Int
    func url() -> String
    func header(_ name: String) -> String?
    func headers() -> [String: String]
    func cookies() -> [String: String]
    func cookie(_ name: String) -> String?
}

@objc final class ConnResponseBridge: NSObject, ConnResponseExport {
    private let r: StrResponseBridge
    init(_ r: StrResponseBridge) { self.r = r }
    func body() -> String { r.body() }
    func statusCode() -> Int { r.code() }
    func url() -> String { r.url() }
    func header(_ name: String) -> String? { r.header(name) }
    func headers() -> [String: String] { r.headers() }
    func cookies() -> [String: String] {
        var m: [String: String] = [:]
        for part in (CookieStore.shared.cookieHeader(for: r.url()) ?? "").components(separatedBy: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if let eq = p.firstIndex(of: "=") { m[String(p[..<eq])] = String(p[p.index(after: eq)...]) }
        }
        return m
    }
    func cookie(_ name: String) -> String? { cookies()[name] }
}

@objc protocol SymmetricCryptoExport: JSExport {
    func setIv(_ iv: JSValue) -> SymmetricCryptoBridge
    func encrypt(_ data: JSValue) -> [NSNumber]?
    func encryptHex(_ data: JSValue) -> String?
    func encryptBase64(_ data: JSValue) -> String?
    func decrypt(_ data: JSValue) -> [NSNumber]?
    func decryptStr(_ data: JSValue) -> String?
}

@objc final class SymmetricCryptoBridge: NSObject, SymmetricCryptoExport {
    private let transformation: String
    private let key: Data
    private var iv: Data?

    init(_ transformation: String, key: Data, iv: Data?) {
        self.transformation = transformation; self.key = key; self.iv = iv
    }

    private func input(_ v: JSValue) -> Data? {
        if v.isString { return v.toString().data(using: .utf8) }
        if let arr = v.toArray() as? [NSNumber] { return Data(arr.map { UInt8(truncatingIfNeeded: $0.intValue) }) }
        return nil
    }
    /// hutool decrypt(String)：hex 或 base64 自动识别
    private func cipherInput(_ v: JSValue) -> Data? {
        if v.isString {
            let s = v.toString() ?? ""
            if CryptoUtils.isHex(s), let d = CryptoUtils.fromHex(s) { return d }
            return CryptoUtils.base64Decode(s)
        }
        return input(v)
    }

    func setIv(_ v: JSValue) -> SymmetricCryptoBridge { iv = input(v); return self }

    // Swift 内部便捷方法（不导出给 JS）
    @nonobjc func decryptStr(_ s: String) -> String? {
        let data: Data? = CryptoUtils.isHex(s) ? CryptoUtils.fromHex(s) : CryptoUtils.base64Decode(s)
        guard let i = data, let o = CryptoUtils.symmetric(transformation, key: key, iv: iv, encrypt: false, data: i) else { return nil }
        return String(data: o, encoding: .utf8) ?? String(decoding: o, as: UTF8.self)
    }
    @nonobjc func encryptHex(_ s: String) -> String? {
        CryptoUtils.symmetric(transformation, key: key, iv: iv, encrypt: true, data: Data(s.utf8)).map(CryptoUtils.hex)
    }
    @nonobjc func encryptBase64(_ s: String) -> String? {
        CryptoUtils.symmetric(transformation, key: key, iv: iv, encrypt: true, data: Data(s.utf8))?.base64EncodedString()
    }
    func encrypt(_ d: JSValue) -> [NSNumber]? {
        guard let i = input(d) else { return nil }
        return CryptoUtils.symmetric(transformation, key: key, iv: iv, encrypt: true, data: i)?.map { NSNumber(value: $0) }
    }
    func encryptHex(_ d: JSValue) -> String? {
        guard let i = input(d), let o = CryptoUtils.symmetric(transformation, key: key, iv: iv, encrypt: true, data: i) else { return nil }
        return CryptoUtils.hex(o)
    }
    func encryptBase64(_ d: JSValue) -> String? {
        guard let i = input(d), let o = CryptoUtils.symmetric(transformation, key: key, iv: iv, encrypt: true, data: i) else { return nil }
        return o.base64EncodedString()
    }
    func decrypt(_ d: JSValue) -> [NSNumber]? {
        guard let i = cipherInput(d) else { return nil }
        return CryptoUtils.symmetric(transformation, key: key, iv: iv, encrypt: false, data: i)?.map { NSNumber(value: $0) }
    }
    func decryptStr(_ d: JSValue) -> String? {
        guard let i = cipherInput(d), let o = CryptoUtils.symmetric(transformation, key: key, iv: iv, encrypt: false, data: i) else { return nil }
        return String(data: o, encoding: .utf8) ?? String(decoding: o, as: UTF8.self)
    }
}

@objc protocol JsURLExport: JSExport {
    var host: String { get }
    var path: String { get }
    var query: String { get }
    var `protocol`: String { get }
    var port: Int { get }
    var origin: String { get }
    var href: String { get }
    func toString() -> String
    func getQuery(_ name: String) -> String?
}

@objc final class JsURLBridge: NSObject, JsURLExport {
    private let url: URL?
    init(_ s: String, base: String?) {
        if let base, let b = URL(string: base) { url = URL(string: s, relativeTo: b)?.absoluteURL } else { url = URL(string: s) }
    }
    var host: String { url?.host ?? "" }
    var path: String { url?.path ?? "" }
    var query: String { url?.query ?? "" }
    var `protocol`: String { (url?.scheme ?? "") + ":" }
    var port: Int { url?.port ?? -1 }
    var origin: String { url.flatMap { NetworkUtils.getBaseUrl($0.absoluteString) } ?? "" }
    var href: String { url?.absoluteString ?? "" }
    func toString() -> String { href }
    func getQuery(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == name }?.value
    }
}

// MARK: - cookie / cache / source / book / chapter

@objc protocol CookieExport: JSExport {
    func getCookie(_ url: String) -> String
    func setCookie(_ url: String, _ cookie: String)
    func replaceCookie(_ url: String, _ cookie: String)
    func removeCookie(_ url: String)
    func getKey(_ url: String, _ key: String) -> String
}

@objc final class CookieBridge: NSObject, CookieExport {
    static let shared = CookieBridge()
    func getCookie(_ url: String) -> String { CookieStore.shared.cookieHeader(for: url) ?? "" }
    func setCookie(_ url: String, _ cookie: String) { CookieStore.shared.setCookie(url, cookie) }
    func replaceCookie(_ url: String, _ cookie: String) { CookieStore.shared.setCookie(url, cookie) }
    func removeCookie(_ url: String) { CookieStore.shared.removeCookie(url) }
    func getKey(_ url: String, _ key: String) -> String { CookieStore.shared.getKey(url, key) }
}

@objc protocol CacheExport: JSExport {
    func put(_ key: String, _ value: JSValue, _ saveTime: JSValue)
    func get(_ key: String) -> String?
    func getInt(_ key: String) -> NSNumber?
    func delete(_ key: String)
    func putMemory(_ key: String, _ value: JSValue)
    func getFromMemory(_ key: String) -> Any?
    func deleteMemory(_ key: String)
}

@objc final class CacheBridge: NSObject, CacheExport {
    static let shared = CacheBridge()
    private var memory: [String: Any] = [:]
    func put(_ key: String, _ value: JSValue, _ saveTime: JSValue) {
        AppDatabase.shared.cachePut(key, value.toString() ?? "", ttlSeconds: saveTime.isNumber ? Int(saveTime.toInt32()) : 0)
    }
    func get(_ key: String) -> String? { AppDatabase.shared.cacheGet(key) }
    func getInt(_ key: String) -> NSNumber? { AppDatabase.shared.cacheGet(key).flatMap(Int.init).map { NSNumber(value: $0) } }
    func delete(_ key: String) { AppDatabase.shared.cacheDelete(key) }
    func putMemory(_ key: String, _ value: JSValue) { memory[key] = JSCoreEvaluator.fromJS(value) }
    func getFromMemory(_ key: String) -> Any? { memory[key] }
    func deleteMemory(_ key: String) { memory.removeValue(forKey: key) }
}

@objc protocol SourceExport: JSExport {
    var bookSourceUrl: String { get }
    var bookSourceName: String { get }
    var bookSourceGroup: String? { get }
    var header: String? { get }
    var loginUrl: String? { get }
    func getKey() -> String
    func getTag() -> String
    func getVariable() -> String
    func setVariable(_ v: JSValue)
    func put(_ key: String, _ value: String) -> String
    func get(_ key: String) -> String
    func getLoginHeader() -> String?
    func getLoginHeaderMap() -> [String: String]?
    func putLoginHeader(_ header: String)
    func removeLoginHeader()
    func getLoginInfo() -> String?
    func getLoginInfoMap() -> [String: String]?
    func putLoginInfo(_ info: String) -> Bool
    func removeLoginInfo()
}

@objc final class SourceBridge: NSObject, SourceExport {
    private let s: BookSource
    init(_ s: BookSource) { self.s = s }
    private func k(_ x: String) -> String { "\(x)_\(s.bookSourceUrl)" }
    var bookSourceUrl: String { s.bookSourceUrl }
    var bookSourceName: String { s.bookSourceName }
    var bookSourceGroup: String? { s.bookSourceGroup }
    var header: String? { s.header }
    var loginUrl: String? { s.loginUrl }
    func getKey() -> String { s.bookSourceUrl }
    func getTag() -> String { s.bookSourceName }
    func getVariable() -> String { AppDatabase.shared.cacheGet(k("sourceVariable")) ?? "" }
    func setVariable(_ v: JSValue) {
        if v.isUndefined || v.isNull { AppDatabase.shared.cacheDelete(k("sourceVariable")) }
        else { AppDatabase.shared.cachePut(k("sourceVariable"), v.toString()) }
    }
    func put(_ key: String, _ value: String) -> String { AppDatabase.shared.cachePut("var::\(s.bookSourceUrl)::\(key)", value); return value }
    func get(_ key: String) -> String { AppDatabase.shared.cacheGet("var::\(s.bookSourceUrl)::\(key)") ?? "" }
    func getLoginHeader() -> String? { AppDatabase.shared.cacheGet(k("loginHeader")) }
    func getLoginHeaderMap() -> [String: String]? { getLoginHeader().flatMap(JSONLoose.parseObject)?.mapValues { JSONPath.stringOf($0) } }
    func putLoginHeader(_ header: String) { AppDatabase.shared.cachePut(k("loginHeader"), header) }
    func removeLoginHeader() { AppDatabase.shared.cacheDelete(k("loginHeader")) }
    func getLoginInfo() -> String? { AppDatabase.shared.cacheGet(k("userInfo")) }
    func getLoginInfoMap() -> [String: String]? { getLoginInfo().flatMap(JSONLoose.parseObject)?.mapValues { JSONPath.stringOf($0) } }
    func putLoginInfo(_ info: String) -> Bool { AppDatabase.shared.cachePut(k("userInfo"), info); return true }
    func removeLoginInfo() { AppDatabase.shared.cacheDelete(k("userInfo")) }
}

@objc protocol BookExport: JSExport {
    var name: String { get }
    var author: String { get }
    var bookUrl: String { get }
    var tocUrl: String { get }
    var origin: String { get }
    var originName: String { get }
    var kind: String? { get }
    var coverUrl: String? { get }
    var intro: String? { get }
    var totalChapterNum: Int { get }
    var durChapterIndex: Int { get }
    var durChapterTitle: String? { get }
    var latestChapterTitle: String? { get }
    var wordCount: String? { get }
    var type: Int { get }
    func getName() -> String
    func getAuthor() -> String
    func getBookUrl() -> String
    func getTocUrl() -> String
    func getCoverUrl() -> String?
    func getTotalChapterNum() -> Int
    func getVariable(_ key: String) -> String
    func putVariable(_ key: String, _ value: JSValue) -> Bool
    func getVariableMap() -> [String: String]
}

@objc final class BookBridge: NSObject, BookExport {
    private let b: Book
    private let rule: RuleData?
    init(_ b: Book, rule: RuleData?) { self.b = b; self.rule = rule ?? RuleData(variable: b.variable) }
    var name: String { b.name }
    var author: String { b.author }
    var bookUrl: String { b.bookUrl }
    var tocUrl: String { b.tocUrl }
    var origin: String { b.origin }
    var originName: String { b.originName }
    var kind: String? { b.kind }
    var coverUrl: String? { b.coverUrl }
    var intro: String? { b.intro }
    var totalChapterNum: Int { b.totalChapterNum }
    var durChapterIndex: Int { b.durChapterIndex }
    var durChapterTitle: String? { b.durChapterTitle }
    var latestChapterTitle: String? { b.latestChapterTitle }
    var wordCount: String? { b.wordCount }
    var type: Int { b.type }
    func getName() -> String { b.name }
    func getAuthor() -> String { b.author }
    func getBookUrl() -> String { b.bookUrl }
    func getTocUrl() -> String { b.tocUrl }
    func getCoverUrl() -> String? { b.coverUrl }
    func getTotalChapterNum() -> Int { b.totalChapterNum }
    func getVariable(_ key: String) -> String { rule?.getVariable(key) ?? "" }
    func putVariable(_ key: String, _ value: JSValue) -> Bool { rule?.putVariable(key, value.isNull || value.isUndefined ? nil : value.toString()) ?? false }
    func getVariableMap() -> [String: String] { rule?.variableMap ?? [:] }
}

@objc protocol ChapterExport: JSExport {
    var title: String { get }
    var url: String { get }
    var index: Int { get }
    var isVip: Bool { get }
    var isPay: Bool { get }
    var isVolume: Bool { get }
    var baseUrl: String { get }
    var bookUrl: String { get }
    var tag: String? { get }
    func getTitle() -> String
    func getUrl() -> String
    func getIndex() -> Int
    func getAbsoluteURL() -> String
    func getVariable(_ key: String) -> String
    func putVariable(_ key: String, _ value: JSValue) -> Bool
}

@objc final class ChapterBridge: NSObject, ChapterExport {
    private let c: BookChapter
    private let rule: RuleData?
    init(_ c: BookChapter, rule: RuleData?) { self.c = c; self.rule = rule ?? RuleData(variable: c.variable) }
    var title: String { c.title }
    var url: String { c.url }
    var index: Int { c.index }
    var isVip: Bool { c.isVip }
    var isPay: Bool { c.isPay }
    var isVolume: Bool { c.isVolume }
    var baseUrl: String { c.baseUrl }
    var bookUrl: String { c.bookUrl }
    var tag: String? { c.tag }
    func getTitle() -> String { c.title }
    func getUrl() -> String { c.url }
    func getIndex() -> Int { c.index }
    func getAbsoluteURL() -> String { NetworkUtils.getAbsoluteURL(c.baseUrl, c.url) }
    func getVariable(_ key: String) -> String { rule?.getVariable(key) ?? "" }
    func putVariable(_ key: String, _ value: JSValue) -> Bool { rule?.putVariable(key, value.isNull || value.isUndefined ? nil : value.toString()) ?? false }
}
