import Foundation

/// 对应 Legado `RuleAnalyzer` 的子集：目前只实现 `innerRule(startStr, endStr)`。
/// 完整的规则切分（`&&` `||` `%%` `##` 平衡组等）在第 4 步补齐。
struct RuleAnalyzer {
    private let queue: [Character]

    init(_ text: String) {
        queue = Array(text)
    }

    /// 把所有 `start ... end` 之间的内容交给 `fr` 处理并替换。
    /// 与 Legado 一致：找不到任何内嵌时返回原串。
    func innerRule(start startStr: String, end endStr: String, _ fr: (String) throws -> String?) throws -> String {
        let s = Array(startStr), e = Array(endStr)
        var out = ""
        var pos = 0
        var startX = 0
        while let a = find(s, from: pos) {
            pos = a + s.count
            guard let b = find(e, from: pos) else { break }
            let inner = String(queue[pos..<b])
            let frv = try fr(inner) ?? ""
            out += String(queue[startX..<a]) + frv
            pos = b + e.count
            startX = pos
        }
        if startX == 0 { return String(queue) }
        out += String(queue[startX...])
        return out
    }

    private func find(_ pattern: [Character], from: Int) -> Int? {
        guard !pattern.isEmpty, queue.count >= pattern.count else { return nil }
        var i = from
        while i + pattern.count <= queue.count {
            if queue[i] == pattern[0] {
                var ok = true
                for j in 1..<pattern.count where queue[i + j] != pattern[j] { ok = false; break }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }
}
