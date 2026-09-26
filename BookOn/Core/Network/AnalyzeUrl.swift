import Foundation

/// 对应 Legado `model/analyzeRule/AnalyzeUrl.kt`
///
/// 书源里的 URL 规则格式：
/// ```
/// https://x.com/search?q={{key}}&p={{page}},{"method":"POST","body":"a=1","charset":"gbk","headers":{...}}
/// ```
/// 处理顺序：`@js:` / `<js></js>` → `{{js}}` 内嵌 → `<1,2,3>` 分页 → 拆 `url,{option}` → 拼绝对地址 → 编码 query/form。
final class AnalyzeUrl {

    enum Method: String { case get = "GET", post = "POST", head = "HEAD" }

    // 输入
    let ruleUrlRaw: String
    let key: String?
    let page: Int?
    private(set) var baseUrl: String
    let source: BookSource?
    let js: JSEvaluator
    private var extraBindings: [String: Any?]

    // 输出
    private(set) var ruleUrl = ""
    private(set) var url = ""
    private(set) var urlNoQuery = ""
    private(set) var method: Method = .get
    private(set) var headerMap: [String: String] = [:]
    private(set) var body: String?
    private(set) var encodedForm: String?
    private(set) var encodedQuery: String?
    private(set) var charset: String?
    private(set) var type: String?
    private(set) var retry = 0
    private(set) var useWebView = false
    private(set) var webJs: String?
    private(set) var bodyJs: String?
    private(set) var dnsIp: String?
    private(set) var proxy: String?
    private(set) var serverID: Int64?
    private(set) var webViewDelayTime: Int64 = 0
    private(set) var domain = ""

    init(_ url: String,
         key: String? = nil,
         page: Int? = nil,
         baseUrl: String = "",
         source: BookSource? = nil,
         headers: [String: String]? = nil,
         js: JSEvaluator = UnavailableJSEvaluator(),
         bindings: [String: Any?] = [:]) throws {
        self.ruleUrlRaw = url
        self.key = key
        self.page = page
        self.source = source
        self.js = js
        self.extraBindings = bindings

        // baseUrl 里若带 ",{...}" 只保留前半
        var b = baseUrl
        if let r = Self.paramRegex.firstMatch(in: b, range: NSRange(b.startIndex..., in: b)),
           let rr = Range(r.range, in: b) {
            b = String(b[..<rr.lowerBound])
        }
        self.baseUrl = b

        // 书源请求头
        var h: [String: String] = [:]
        if let headers { h = headers }
        else if let source { h = try Self.sourceHeaders(source, js: js) }
        headerMap = h
        if let p = headerMap["proxy"] { proxy = p; headerMap.removeValue(forKey: "proxy") }
        if !headerMap.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            headerMap["User-Agent"] = HTTPClient.defaultUA
        }

        try initUrl()
        domain = NetworkUtils.getSubDomain(source?.bookSourceUrl ?? self.url)
    }

    // MARK: - 解析流程

    private func initUrl() throws {
        ruleUrl = ruleUrlRaw
        try analyzeJs()
        try replaceKeyPageJs()
        try analyzeUrl()
    }

    /// 执行 `@js:` 与 `<js></js>`
    private func analyzeJs() throws {
        let ns = ruleUrl as NSString
        let matches = Self.jsRegex.matches(in: ruleUrl, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return }
        var start = 0
        var result = ruleUrl
        for m in matches {
            if m.range.location > start {
                let pre = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !pre.isEmpty { result = pre.replacingOccurrences(of: "@result", with: result) }
            }
            let script: String
            if m.range(at: 2).location != NSNotFound { script = ns.substring(with: m.range(at: 2)) }
            else { script = ns.substring(with: m.range(at: 1)) }
            result = JSValueFormat.string(try evalJS(script, result: result))
            start = m.range.location + m.range.length
        }
        if ns.length > start {
            let tail = ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { result = tail.replacingOccurrences(of: "@result", with: result) }
        }
        ruleUrl = result
    }

    /// 替换 `{{js}}` 与 `<a,b,c>` 分页
    private func replaceKeyPageJs() throws {
        if ruleUrl.contains("{{") && ruleUrl.contains("}}") {
            let replaced = try RuleAnalyzer(ruleUrl).innerRule(start: "{{", end: "}}") { inner in
                let v = try self.evalInlineJS(inner)
                return JSValueFormat.string(v)
            }
            if !replaced.isEmpty { ruleUrl = replaced }
        }
        if let page {
            let ns = ruleUrl as NSString
            let matches = Self.pageRegex.matches(in: ruleUrl, range: NSRange(location: 0, length: ns.length))
            var result = ruleUrl
            for m in matches {
                let whole = ns.substring(with: m.range)
                let pages = ns.substring(with: m.range(at: 1)).components(separatedBy: ",")
                let pick = page < pages.count ? pages[page - 1] : pages[pages.count - 1]
                result = result.replacingOccurrences(of: whole, with: pick.trimmingCharacters(in: .whitespaces))
            }
            ruleUrl = result
        }
    }

    /// 拆 `url,{option}`，拼绝对地址，处理 method/body/query 编码
    private func analyzeUrl() throws {
        var urlNoOption = ruleUrl
        var optionStr: String?
        if let m = Self.paramRegex.firstMatch(in: ruleUrl, range: NSRange(ruleUrl.startIndex..., in: ruleUrl)),
           let r = Range(m.range, in: ruleUrl) {
            urlNoOption = String(ruleUrl[..<r.lowerBound])
            optionStr = String(ruleUrl[r.upperBound...])
        }
        url = NetworkUtils.getAbsoluteURL(baseUrl, urlNoOption)
        if let b = NetworkUtils.getBaseUrl(url) { baseUrl = b }

        if let optionStr, let option = UrlOption.parse(optionStr) {
            if let m = option.method {
                switch m.uppercased() {
                case "POST": method = .post
                case "HEAD": method = .head
                default: method = .get
                }
            }
            option.headers?.forEach { headerMap[$0.key] = $0.value }
            body = option.body
            type = option.type
            charset = option.charset
            retry = option.retry
            useWebView = option.webView
            webJs = option.webJs
            bodyJs = option.bodyJs
            dnsIp = option.dnsIp
            if let jsStr = option.js {
                url = JSValueFormat.string(try evalJS(jsStr, result: url))
            }
            serverID = option.serverID
            webViewDelayTime = option.webViewDelayTime
        }

        urlNoQuery = url
        switch method {
        case .post:
            if let b = body {
                let contentType = headerMap.first { $0.key.lowercased() == "content-type" }?.value ?? ""
                if !Self.isJson(b) && !Self.isXml(b) && contentType.isEmpty {
                    encodedForm = encodeParams(b, isQuery: false)
                }
            }
        default:
            if let q = url.firstIndex(of: "?") {
                encodedQuery = encodeParams(String(url[url.index(after: q)...]), isQuery: true)
                urlNoQuery = String(url[..<q])
            }
        }
    }

    // MARK: - 编码（与 Legado encodeParams 一致）

    private func encodeParams(_ params: String, isQuery: Bool) -> String {
        let checkEncoded = (charset ?? "").isEmpty
        let enc: String.Encoding?
        if (charset ?? "").isEmpty { enc = .utf8 }
        else if charset == "escape" { enc = nil }
        else { enc = NetworkUtils.encoding(named: charset) ?? .utf8 }

        if isQuery, let enc {
            if NetworkUtils.encodedQuery(params) { return params }
            return NetworkUtils.queryEncode(params, encoding: enc)
        }

        var out: [String] = []
        for pair in params.components(separatedBy: "&") {
            if let eq = pair.firstIndex(of: "=") {
                let k = String(pair[..<eq]), v = String(pair[pair.index(after: eq)...])
                out.append(encodeOne(k, checkEncoded, enc) + "=" + encodeOne(v, checkEncoded, enc))
            } else {
                out.append(encodeOne(pair, checkEncoded, enc))
            }
        }
        return out.joined(separator: "&")
    }

    private func encodeOne(_ v: String, _ checkEncoded: Bool, _ enc: String.Encoding?) -> String {
        if checkEncoded && NetworkUtils.encodedForm(v) { return v }
        guard let enc else { return NetworkUtils.jsEscape(v) }
        return NetworkUtils.urlEncode(v, encoding: enc)
    }

    // MARK: - JS

    func evalJS(_ script: String, result: Any? = nil) throws -> Any? {
        var b: [String: Any?] = [
            "baseUrl": baseUrl,
            "page": page,
            "key": key,
            "result": result,
            "source": source,
        ]
        extraBindings.forEach { b[$0.key] = $0.value }
        return try js.eval(script, bindings: b)
    }

    /// `{{...}}` 内嵌：常见的 key / page / page±n 直接算，其余交给 JS 引擎
    private func evalInlineJS(_ inner: String) throws -> Any? {
        let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        if t == "key" { return key ?? "" }
        if t == "page" { return page }
        if let m = Self.pageArithRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let page,
           let opR = Range(m.range(at: 1), in: t), let nR = Range(m.range(at: 2), in: t),
           let n = Int(t[nR]) {
            return t[opR] == "+" ? page + n : page - n
        }
        return try evalJS(t)
    }

    // MARK: - 书源请求头

    static func sourceHeaders(_ source: BookSource, js: JSEvaluator) throws -> [String: String] {
        guard let header = source.header?.trimmingCharacters(in: .whitespacesAndNewlines), !header.isEmpty else { return [:] }
        var jsonText = header
        let lower = header.lowercased()
        if lower.hasPrefix("@js:") {
            jsonText = JSValueFormat.string(try js.eval(String(header.dropFirst(4)), bindings: ["source": source]))
        } else if lower.hasPrefix("<js>") {
            let inner = header.dropFirst(4)
            let end = inner.range(of: "<", options: .backwards)?.lowerBound ?? inner.endIndex
            jsonText = JSValueFormat.string(try js.eval(String(inner[..<end]), bindings: ["source": source]))
        }
        guard let obj = JSONLoose.parseObject(jsonText) else { return [:] }
        return obj.reduce(into: [:]) { $0[$1.key] = ($1.value as? String) ?? String(describing: $1.value) }
    }

    // MARK: - 构造 URLRequest

    func makeRequest(timeout: TimeInterval = 30) throws -> URLRequest {
        var finalURL = urlNoQuery
        if method != .post, let q = encodedQuery, !q.isEmpty { finalURL += "?" + q }
        guard let u = URL(string: finalURL) else {
            throw URLError(.badURL, userInfo: [NSURLErrorFailingURLStringErrorKey: finalURL])
        }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.httpMethod = method.rawValue
        headerMap.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if method == .post {
            if let form = encodedForm, !form.isEmpty {
                req.httpBody = form.data(using: .utf8)
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            } else if let b = body, !b.isEmpty {
                req.httpBody = b.data(using: .utf8)
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                }
            } else {
                req.httpBody = Data()
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        return req
    }

    // MARK: - 常量

    static let paramRegex = try! NSRegularExpression(pattern: "\\s*,\\s*(?=\\{)")
    static let pageRegex = try! NSRegularExpression(pattern: "<(.*?)>")
    static let jsRegex = try! NSRegularExpression(pattern: "<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)", options: .caseInsensitive)
    private static let pageArithRegex = try! NSRegularExpression(pattern: "^page\\s*([+-])\\s*(\\d+)$")

    static func isJson(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]"))
    }
    static func isXml(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("<") && t.hasSuffix(">")
    }
}
