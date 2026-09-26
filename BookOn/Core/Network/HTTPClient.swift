import Foundation

/// 对应 Legado `StrResponse`
struct StrResponse {
    let url: String          // 最终地址（跟随重定向后）
    let body: String
    let statusCode: Int
    let headers: [String: String]
    let data: Data
    let encodingUsed: String
}

enum HTTPError: LocalizedError {
    case badStatus(Int, String)
    case empty
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let c, let u): return "HTTP \(c)：\(u)"
        case .empty: return "响应为空"
        case .transport(let m): return m
        }
    }
}

/// 网络层：URLSession + Cookie 管理 + 字符集识别 + 重试。
final class HTTPClient: NSObject {
    static let shared = HTTPClient()

    static let defaultUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .never       // 自己管 cookie，方便按书源隔离
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept": "*/*", "Accept-Language": "zh-CN,zh;q=0.9"]
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    // MARK: - 请求

    /// 执行 AnalyzeUrl，返回解码后的字符串响应
    func strResponse(_ analyze: AnalyzeUrl) async throws -> StrResponse {
        var req = try analyze.makeRequest(timeout: TimeInterval((analyze.source?.respondTime ?? 30_000) / 1000))
        // Cookie
        if analyze.source?.enabledCookieJar ?? true, req.value(forHTTPHeaderField: "Cookie") == nil {
            if let c = CookieStore.shared.cookieHeader(for: analyze.url), !c.isEmpty {
                req.setValue(c, forHTTPHeaderField: "Cookie")
            }
        }
        let (data, resp) = try await perform(req, retry: analyze.retry)
        let http = resp as? HTTPURLResponse
        let finalURL = http?.url?.absoluteString ?? analyze.url
        var headers: [String: String] = [:]
        http?.allHeaderFields.forEach { headers[String(describing: $0.key)] = String(describing: $0.value) }

        // 保存 Set-Cookie
        if analyze.source?.enabledCookieJar ?? true, let http, let u = http.url {
            let setCookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: u)
            CookieStore.shared.store(setCookies, for: u)
        }

        let (text, encName) = Self.decode(data, contentType: headers["Content-Type"], preferred: analyze.charset)
        return StrResponse(url: finalURL, body: text, statusCode: http?.statusCode ?? 0,
                           headers: headers, data: data, encodingUsed: encName)
    }

    /// 原始字节（图片、文件等）
    func bytes(_ analyze: AnalyzeUrl) async throws -> Data {
        let req = try analyze.makeRequest()
        let (data, _) = try await perform(req, retry: analyze.retry)
        return data
    }

    private func perform(_ req: URLRequest, retry: Int) async throws -> (Data, URLResponse) {
        var attempt = 0
        var lastError: Error?
        while attempt <= max(0, retry) {
            do {
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                    // 4xx/5xx 仍返回内容（部分书源要读错误页），但记录状态
                    return (data, resp)
                }
                return (data, resp)
            } catch {
                lastError = error
                attempt += 1
                if attempt <= retry { try? await Task.sleep(nanoseconds: 300_000_000) }
            }
        }
        throw HTTPError.transport((lastError as? URLError)?.localizedDescription ?? lastError?.localizedDescription ?? "请求失败")
    }

    // MARK: - 字符集

    /// 解码顺序：书源指定 charset → Content-Type → HTML meta → UTF-8 校验 → GB18030 兜底
    static func decode(_ data: Data, contentType: String?, preferred: String?) -> (String, String) {
        if let p = preferred, p != "escape", let enc = NetworkUtils.encoding(named: p),
           let s = String(data: data, encoding: enc) { return (s, p) }
        if let ct = contentType, let name = charset(inContentType: ct), let enc = NetworkUtils.encoding(named: name),
           let s = String(data: data, encoding: enc) { return (s, name) }
        if let name = htmlMetaCharset(data), let enc = NetworkUtils.encoding(named: name),
           let s = String(data: data, encoding: enc) { return (s, name) }
        if let s = String(data: data, encoding: .utf8) { return (s, "utf-8") }
        if let enc = NetworkUtils.encoding(named: "gb18030"), let s = String(data: data, encoding: enc) { return (s, "gb18030") }
        return (String(decoding: data, as: UTF8.self), "utf-8(lossy)")
    }

    static func charset(inContentType ct: String) -> String? {
        guard let r = ct.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let rest = ct[r.upperBound...]
        let end = rest.firstIndex(where: { $0 == ";" || $0 == " " }) ?? rest.endIndex
        return String(rest[..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    private static let metaRegex = try! NSRegularExpression(
        pattern: "<meta[^>]+charset\\s*=\\s*[\"']?\\s*([\\w-]+)", options: .caseInsensitive)

    static func htmlMetaCharset(_ data: Data) -> String? {
        let head = data.prefix(4096)
        let s = String(decoding: head, as: UTF8.self)   // 头部 ASCII 为主，lossy 无妨
        guard let m = metaRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}

extension HTTPClient: URLSessionTaskDelegate {
    /// 跟随重定向时带上自定义头（URLSession 默认会丢掉部分头）
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var r = request
        task.originalRequest?.allHTTPHeaderFields?.forEach { k, v in
            if r.value(forHTTPHeaderField: k) == nil, k.lowercased() != "content-length" { r.setValue(v, forHTTPHeaderField: k) }
        }
        if let u = r.url, let c = CookieStore.shared.cookieHeader(for: u.absoluteString), !c.isEmpty {
            r.setValue(c, forHTTPHeaderField: "Cookie")
        }
        completionHandler(r)
    }
}

/// 对应 Legado `CookieStore`：按域名持久化 cookie 到数据库
final class CookieStore {
    static let shared = CookieStore()
    private let db = AppDatabase.shared
    private let lock = NSLock()

    private func key(_ domain: String) -> String { "cookie::\(domain)" }

    func cookieHeader(for url: String) -> String? {
        let domain = NetworkUtils.getSubDomain(url)
        return db.cacheGet(key(domain))
    }

    func store(_ cookies: [HTTPCookie], for url: URL) {
        guard !cookies.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let domain = NetworkUtils.getSubDomain(url.absoluteString)
        var map = parse(db.cacheGet(key(domain)) ?? "")
        for c in cookies { map[c.name] = c.value }
        db.cachePut(key(domain), map.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))
    }

    func setCookie(_ url: String, _ cookie: String) {
        let domain = NetworkUtils.getSubDomain(url)
        db.cachePut(key(domain), cookie)
    }

    func removeCookie(_ url: String) {
        db.cacheDelete(key(NetworkUtils.getSubDomain(url)))
    }

    func getKey(_ url: String, _ name: String) -> String {
        parse(cookieHeader(for: url) ?? "")[name] ?? ""
    }

    private func parse(_ s: String) -> [String: String] {
        var m: [String: String] = [:]
        for part in s.components(separatedBy: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            guard let eq = p.firstIndex(of: "=") else { continue }
            m[String(p[..<eq])] = String(p[p.index(after: eq)...])
        }
        return m
    }
}
