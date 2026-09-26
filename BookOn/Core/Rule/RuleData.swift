import Foundation

/// 对应 Legado `RuleDataInterface`：规则解析过程中 @put/@get 的变量容器。
/// Book / BookChapter / SearchBook 都持有 `variable`（JSON 字符串）。
final class RuleData {
    var variableMap: [String: String]

    init(variable: String? = nil) {
        if let v = variable, let d = v.data(using: .utf8),
           let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            variableMap = m.reduce(into: [:]) { $0[$1.key] = JSONPath.stringOf($1.value) }
        } else {
            variableMap = [:]
        }
    }

    @discardableResult
    func putVariable(_ key: String, _ value: String?) -> Bool {
        if let value, !value.isEmpty { variableMap[key] = value; return true }
        variableMap.removeValue(forKey: key)
        return false
    }

    func getVariable(_ key: String) -> String { variableMap[key] ?? "" }

    /// 序列化回 `variable` 字段
    var variable: String? {
        guard !variableMap.isEmpty,
              let d = try? JSONSerialization.data(withJSONObject: variableMap, options: [.sortedKeys]) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
}
