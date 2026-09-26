import Foundation

/// 对应 Legado `RuleAnalyzer`：规则字符串的切分器。
/// 关键能力：按 `&&` `||` `%%` `@` 等分隔符切分时，跳过 `[...]` `(...)` 与引号内部的内容。
struct RuleAnalyzer {
    private let queue: [Character]
    private var pos = 0
    private let code: Bool
    /// 首个匹配到的分隔符类型（"&&" / "||" / "%%"），未匹配为 ""
    private(set) var elementsType = ""

    init(_ text: String, code: Bool = false) {
        queue = Array(text)
        self.code = code
    }

    // MARK: - innerRule（{{ }} 内嵌）

    /// 把所有 `start ... end` 之间的内容交给 `fr` 处理并替换。找不到任何内嵌时返回原串。
    func innerRule(start startStr: String, end endStr: String, _ fr: (String) throws -> String?) throws -> String {
        let s = Array(startStr), e = Array(endStr)
        var out = ""
        var p = 0
        var startX = 0
        while let a = find(s, from: p) {
            p = a + s.count
            guard let b = find(e, from: p) else { break }
            let frv = try fr(String(queue[p..<b])) ?? ""
            out += String(queue[startX..<a]) + frv
            p = b + e.count
            startX = p
        }
        if startX == 0 { return String(queue) }
        out += String(queue[startX...])
        return out
    }

    /// 平衡括号版内嵌：`{$.a[0]}` 之类，`inner` 为起始标记（如 "{"），需要 `{}` 平衡
    func innerRuleBalanced(_ inner: String, startStep: Int = 1, endStep: Int = 1, _ fr: (String) throws -> String?) throws -> String {
        let s = Array(inner)
        var out = ""
        var p = 0
        var startX = 0
        while let a = find(s, from: p) {
            if let end = balancedEnd(from: a, open: "{", close: "}", codeMode: true) {
                let frv = try fr(String(queue[(a + startStep)..<(end - endStep)]))
                if let frv, !frv.isEmpty {
                    out += String(queue[startX..<a]) + frv
                    startX = end
                    p = end
                    continue
                }
            }
            p = a + s.count
        }
        if startX == 0 { return "" }
        out += String(queue[startX...])
        return out
    }

    // MARK: - splitRule

    /// 修剪当前位置之前的 "@" 与空白
    mutating func trim() {
        while pos < queue.count, queue[pos] == "@" || queue[pos].asciiValue.map({ $0 < 0x21 }) == true {
            pos += 1
        }
    }

    /// 按分隔符切分（跳过 [] () 与引号内部）。多个分隔符时，以最先出现的那个为准。
    mutating func splitRule(_ seps: String...) -> [String] {
        let sepArr = seps.map(Array.init)
        var result: [String] = []
        var segStart = pos
        var i = pos
        var chosen: [Character]? = sepArr.count == 1 ? sepArr[0] : nil
        var inS = false, inD = false
        if sepArr.count == 1 { elementsType = seps[0] }

        while i < queue.count {
            let c = queue[i]
            if c == "\\" && !(inS || inD) && !code { i += 2; continue }
            if c == "'" && !inD { inS.toggle(); i += 1; continue }
            if c == "\"" && !inS { inD.toggle(); i += 1; continue }
            if inS || inD { i += 1; continue }
            if c == "[" || c == "(" {
                let close: Character = c == "[" ? "]" : ")"
                if let end = balancedEnd(from: i, open: c, close: close, codeMode: code) { i = end; continue }
                // 不平衡：Legado 会抛错；这里按普通字符处理，避免整条规则失败
                i += 1; continue
            }
            var matched: [Character]? = nil
            if let ch = chosen {
                if matches(ch, at: i) { matched = ch }
            } else {
                for s in sepArr where matches(s, at: i) { matched = s; break }
            }
            if let m = matched {
                if chosen == nil { chosen = m; elementsType = String(m) }
                result.append(String(queue[segStart..<i]))
                i += m.count
                segStart = i
                continue
            }
            i += 1
        }
        result.append(String(queue[segStart...]))
        pos = queue.count
        return result
    }

    // MARK: - helpers

    private func matches(_ pattern: [Character], at i: Int) -> Bool {
        guard i + pattern.count <= queue.count else { return false }
        for j in 0..<pattern.count where queue[i + j] != pattern[j] { return false }
        return true
    }

    private func find(_ pattern: [Character], from: Int) -> Int? {
        guard !pattern.isEmpty, queue.count >= pattern.count else { return nil }
        var i = from
        while i + pattern.count <= queue.count {
            if matches(pattern, at: i) { return i }
            i += 1
        }
        return nil
    }

    /// 从 `from`（指向 open）开始找到平衡的 close，返回 close 之后的位置
    private func balancedEnd(from: Int, open: Char, close: Char, codeMode: Bool) -> Int? {
        var p = from
        var depth = 0
        var otherDepth = 0
        var inS = false, inD = false
        repeat {
            if p >= queue.count { break }
            let c = queue[p]; p += 1
            if codeMode {
                if c == "\\" { p += 1; continue }
                if c == "'" && !inD { inS.toggle() } else if c == "\"" && !inS { inD.toggle() }
                if inS || inD { continue }
                if c == "[" { depth += 1 } else if c == "]" { depth -= 1 }
                else if depth == 0 { if c == open { otherDepth += 1 } else if c == close { otherDepth -= 1 } }
            } else {
                if c == "'" && !inD { inS.toggle() } else if c == "\"" && !inS { inD.toggle() }
                if inS || inD { continue }
                if c == "\\" { p += 1; continue }
                if c == open { depth += 1 } else if c == close { depth -= 1 }
            }
        } while depth > 0 || otherDepth > 0
        return (depth > 0 || otherDepth > 0) ? nil : p
    }

    typealias Char = Character
}
