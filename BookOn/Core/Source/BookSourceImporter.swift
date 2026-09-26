import Foundation

/// 书源导入：与 Legado `ImportBookSourceViewModel.importSource` 行为一致
/// - JSON 对象：优先读取 `$.sourceUrls` 批量拉取；否则视为单个书源
/// - JSON 数组：书源列表
/// - http(s) 地址：下载后解析（支持 `#requestWithoutUA` 后缀）
enum SourceImportError: LocalizedError {
    case notSource
    case wrongFormat
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notSource: return "不是书源"
        case .wrongFormat: return "格式不对，只支持书源 JSON 或网址"
        case .network(let m): return "下载失败：\(m)"
        }
    }
}

struct ImportedSource: Identifiable {
    let source: BookSource
    let existing: BookSource?
    var selected: Bool

    var id: String { source.bookSourceUrl }
    var isNew: Bool { existing == nil }
    var isUpdate: Bool { existing.map { $0.lastUpdateTime < source.lastUpdateTime } ?? false }
}

enum BookSourceImporter {

    static func importText(_ raw: String) async throws -> [BookSource] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SourceImportError.wrongFormat }

        if text.hasPrefix("{") {
            if let urls = sourceUrls(in: text) {
                var all: [BookSource] = []
                for u in urls { all += try await importURL(u) }
                return all
            }
            let s = try parseObject(text)
            return [s]
        }
        if text.hasPrefix("[") {
            return try parseArray(text)
        }
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return try await importURL(text)
        }
        throw SourceImportError.wrongFormat
    }

    static func importURL(_ raw: String) async throws -> [BookSource] {
        var urlString = raw
        var withoutUA = false
        if urlString.hasSuffix("#requestWithoutUA") {
            urlString = String(urlString.dropLast("#requestWithoutUA".count))
            withoutUA = true
        }
        guard let url = URL(string: urlString) else { throw SourceImportError.wrongFormat }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue(withoutUA ? "null" : HTTPClient.defaultUA, forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SourceImportError.network("HTTP \(http.statusCode)")
            }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("[") { return try parseArray(text) }
            if text.hasPrefix("{") {
                if let urls = sourceUrls(in: text) {
                    var all: [BookSource] = []
                    for u in urls { all += try await importURL(u) }
                    return all
                }
                return [try parseObject(text)]
            }
            throw SourceImportError.notSource
        } catch let e as SourceImportError {
            throw e
        } catch {
            throw SourceImportError.network(error.localizedDescription)
        }
    }

    // MARK: - 解析

    private static func parseObject(_ text: String) throws -> BookSource {
        guard let data = text.data(using: .utf8),
              let s = try? LegadoJSON.decoder().decode(BookSource.self, from: data),
              !s.bookSourceUrl.isEmpty else { throw SourceImportError.notSource }
        return s
    }

    private static func parseArray(_ text: String) throws -> [BookSource] {
        guard let data = text.data(using: .utf8),
              let items = try? LegadoJSON.decoder().decode([Failable<BookSource>].self, from: data)
        else { throw SourceImportError.notSource }
        let list = items.compactMap { $0.value }.filter { !$0.bookSourceUrl.isEmpty }
        guard !list.isEmpty else { throw SourceImportError.notSource }
        return list
    }

    private static func sourceUrls(in text: String) -> [String]? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urls = obj["sourceUrls"] as? [String], !urls.isEmpty else { return nil }
        return urls
    }

    // MARK: - 与本地比较

    static func compare(_ sources: [BookSource]) -> [ImportedSource] {
        let db = AppDatabase.shared
        var seen = Set<String>()
        return sources.compactMap { s in
            guard seen.insert(s.bookSourceUrl).inserted else { return nil }
            let old = db.bookSource(url: s.bookSourceUrl)
            let selected = old == nil || old!.lastUpdateTime < s.lastUpdateTime
            return ImportedSource(source: s, existing: old, selected: selected)
        }
    }
}

enum HTTPClient {
    static let defaultUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
