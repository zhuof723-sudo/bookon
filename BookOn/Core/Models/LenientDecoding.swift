import Foundation

/// Legado 导出的 JSON 来源五花八门（GSON、Web 端、手写），
/// 数值可能是字符串、布尔可能是 0/1、规则对象可能被序列化成字符串。
/// 这里提供一组“尽力而为”的解码工具，保证能吃下各种变体。
extension KeyedDecodingContainer {

    func lenientString(_ key: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key) {
            if v == v.rounded(), abs(v) < 9e15 { return String(Int(v)) }
            return String(v)
        }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v ? "true" : "false" }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key), v.isFinite, abs(v) < 9e18 { return Int(v) }
        if let v = try? decodeIfPresent(String.self, forKey: key) {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = Int(t) { return i }
            if let d = Double(t), d.isFinite, abs(d) < 9e18 { return Int(d) }
        }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v ? 1 : 0 }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v != 0 }
        if let v = try? decodeIfPresent(String.self, forKey: key) {
            switch v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no", "": return false
            default: return nil
            }
        }
        return nil
    }

    /// 规则对象：既可能是 JSON 对象，也可能是包含 JSON 的字符串（Legado 两种都接受）。
    func lenientObject<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        if let v = try? decodeIfPresent(T.self, forKey: key) { return v }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.hasPrefix("{"), let data = t.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return nil
    }
}

/// 数组中单个元素解析失败时跳过，而不是让整批导入失败。
struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

enum LegadoJSON {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
