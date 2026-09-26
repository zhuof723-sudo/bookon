import Foundation

/// 轻量 JSONPath 实现，覆盖书源中实际使用的子集（兼容 Jayway JsonPath 语义）：
/// `$` `.key` `['key']` `[*]` `[0]` `[-1]` `[0,2]` `[1:3]` `..key`（深度）
/// `[?(@.a == 'x')]` `[?(@.a)]` 过滤（支持 == != > < >= <= =~ 与 &&/||）
/// 以及 `.length()` / `.min()` / `.max()` / `.sum()` / `.first()` / `.last()` 函数。
enum JSONPath {

    enum PathError: LocalizedError {
        case syntax(String)
        var errorDescription: String? { if case .syntax(let m) = self { return "JSONPath 语法错误: \(m)" }; return nil }
    }

    // MARK: - 公开

    static func parseJSON(_ text: String) -> Any? {
        guard let d = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
    }

    /// 读取；返回值可能是 单值 / [Any]。与 Jayway 一致：确定性路径（无 * .. 切片 过滤）返回单值，否则返回数组。
    static func read(_ root: Any, _ path: String) throws -> Any? {
        let (tokens, definite) = try tokenize(path)
        var current: [Any] = [root]
        for t in tokens {
            current = try apply(t, to: current)
            if current.isEmpty { break }
        }
        if definite { return current.first }
        return current
    }

    // MARK: - Token

    indirect enum Token {
        case key(String)
        case keys([String])
        case wildcard
        case index([Int])
        case slice(Int?, Int?, Int)
        case deep(Token)           // ..key / ..[*]
        case filter(Expr)
        case function(String)
    }

    indirect enum Expr {
        case exists(String)
        case compare(String, String, Value)       // path op literal
        case comparePaths(String, String, String) // @.a op @.b
        case and(Expr, Expr)
        case or(Expr, Expr)
        case not(Expr)
    }

    enum Value { case str(String), num(Double), bool(Bool), null }

    static func tokenize(_ path: String) throws -> ([Token], Bool) {
        var s = Array(path.trimmingCharacters(in: .whitespaces))
        var i = 0
        var tokens: [Token] = []
        var definite = true
        if i < s.count, s[i] == "$" { i += 1 }
        // 允许不写 $，直接 .a 或 a
        if i < s.count, s[i] != "." && s[i] != "[" { s.insert(".", at: i) }

        while i < s.count {
            let c = s[i]
            if c == "." {
                if i + 1 < s.count, s[i + 1] == "." {
                    // 深度扫描
                    i += 2
                    definite = false
                    if i < s.count, s[i] == "[" {
                        let (tk, ni) = try bracket(s, i); i = ni
                        tokens.append(.deep(tk))
                    } else if i < s.count, s[i] == "*" {
                        i += 1; tokens.append(.deep(.wildcard))
                    } else {
                        let (name, ni) = readName(s, i); i = ni
                        tokens.append(.deep(.key(name)))
                    }
                    continue
                }
                i += 1
                if i < s.count, s[i] == "*" { i += 1; definite = false; tokens.append(.wildcard); continue }
                let (name, ni) = readName(s, i); i = ni
                if i < s.count, s[i] == "(", i + 1 < s.count, s[i + 1] == ")" {
                    i += 2; tokens.append(.function(name)); continue
                }
                if name.isEmpty { throw PathError.syntax("空键名 at \(i)") }
                tokens.append(.key(name))
                continue
            }
            if c == "[" {
                let (tk, ni) = try bracket(s, i); i = ni
                switch tk {
                case .key: break
                case .index(let arr) where arr.count == 1: break
                default: definite = false
                }
                tokens.append(tk)
                continue
            }
            if c == " " { i += 1; continue }
            throw PathError.syntax("意外字符 '\(c)' at \(i)")
        }
        return (tokens, definite)
    }

    private static func readName(_ s: [Character], _ start: Int) -> (String, Int) {
        var i = start
        var name = ""
        while i < s.count, s[i] != "." && s[i] != "[" && s[i] != "(" {
            name.append(s[i]); i += 1
        }
        return (name.trimmingCharacters(in: .whitespaces), i)
    }

    /// 解析 `[...]`，返回 token 与 `]` 之后的位置
    private static func bracket(_ s: [Character], _ start: Int) throws -> (Token, Int) {
        var i = start + 1
        // 找到平衡的 ]
        var depth = 1
        var inS = false, inD = false
        var j = i
        while j < s.count {
            let c = s[j]
            if c == "'" && !inD { inS.toggle() } else if c == "\"" && !inS { inD.toggle() }
            else if !inS && !inD {
                if c == "[" || c == "(" { depth += 1 }
                else if c == "]" || c == ")" { depth -= 1; if depth == 0 && c == "]" { break } }
            }
            j += 1
        }
        guard j < s.count else { throw PathError.syntax("缺少 ]") }
        let inner = String(s[i..<j]).trimmingCharacters(in: .whitespaces)
        i = j + 1

        if inner == "*" { return (.wildcard, i) }
        if inner.hasPrefix("?") {
            var body = inner.dropFirst()
            body = body.trimmingCharacters(in: .whitespaces)[...]
            if body.hasPrefix("("), body.hasSuffix(")") { body = body.dropFirst().dropLast() }
            return (.filter(try parseExpr(String(body))), i)
        }
        if inner.hasPrefix("'") || inner.hasPrefix("\"") {
            let keys = splitTop(inner, ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .map { String($0.dropFirst().dropLast()) }
            return (keys.count == 1 ? .key(keys[0]) : .keys(keys), i)
        }
        if inner.contains(":") {
            let parts = inner.components(separatedBy: ":")
            let a = Int(parts[0].trimmingCharacters(in: .whitespaces))
            let b = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
            let st = parts.count > 2 ? Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
            return (.slice(a, b, st == 0 ? 1 : st), i)
        }
        let nums = inner.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if !nums.isEmpty { return (.index(nums), i) }
        // 裸键名 [key]
        return (.key(inner), i)
    }

    private static func splitTop(_ s: String, _ sep: Character) -> [String] {
        var out: [String] = []; var cur = ""; var inS = false, inD = false; var depth = 0
        for c in s {
            if c == "'" && !inD { inS.toggle() } else if c == "\"" && !inS { inD.toggle() }
            if !inS && !inD { if c == "(" || c == "[" { depth += 1 } else if c == ")" || c == "]" { depth -= 1 } }
            if c == sep && !inS && !inD && depth == 0 { out.append(cur); cur = "" } else { cur.append(c) }
        }
        out.append(cur)
        return out
    }

    // MARK: - 过滤表达式

    static func parseExpr(_ text: String) throws -> Expr {
        let t = text.trimmingCharacters(in: .whitespaces)
        let orParts = splitLogical(t, "||")
        if orParts.count > 1 {
            return try orParts.dropFirst().reduce(try parseExpr(orParts[0])) { .or($0, try parseExpr($1)) }
        }
        let andParts = splitLogical(t, "&&")
        if andParts.count > 1 {
            return try andParts.dropFirst().reduce(try parseExpr(andParts[0])) { .and($0, try parseExpr($1)) }
        }
        var body = t
        if body.hasPrefix("("), body.hasSuffix(")") { body = String(body.dropFirst().dropLast()); return try parseExpr(body) }
        if body.hasPrefix("!") { return .not(try parseExpr(String(body.dropFirst()))) }
        for op in ["==", "!=", ">=", "<=", "=~", ">", "<"] {
            if let r = body.range(of: " \(op) ") ?? body.range(of: op) {
                let lhs = body[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let rhs = body[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if rhs.hasPrefix("@") { return .comparePaths(lhs, op, rhs) }
                return .compare(lhs, op, literal(rhs))
            }
        }
        return .exists(body)
    }

    private static func splitLogical(_ s: String, _ op: String) -> [String] {
        var out: [String] = []; var cur = ""; var inS = false, inD = false; var depth = 0
        let chars = Array(s); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" && !inD { inS.toggle() } else if c == "\"" && !inS { inD.toggle() }
            if !inS && !inD { if c == "(" { depth += 1 } else if c == ")" { depth -= 1 } }
            if !inS && !inD && depth == 0 && i + 1 < chars.count && String(chars[i...i+1]) == op {
                out.append(cur); cur = ""; i += 2; continue
            }
            cur.append(c); i += 1
        }
        out.append(cur)
        return out
    }

    private static func literal(_ s: String) -> Value {
        if (s.hasPrefix("'") && s.hasSuffix("'")) || (s.hasPrefix("\"") && s.hasSuffix("\"")) {
            return .str(String(s.dropFirst().dropLast()))
        }
        if s == "true" { return .bool(true) }
        if s == "false" { return .bool(false) }
        if s == "null" { return .null }
        if let d = Double(s) { return .num(d) }
        if s.hasPrefix("/") { return .str(s) } // 正则字面量
        return .str(s)
    }

    // MARK: - 求值

    private static func apply(_ t: Token, to items: [Any]) throws -> [Any] {
        var out: [Any] = []
        for item in items {
            switch t {
            case .key(let k):
                if let d = item as? [String: Any], let v = d[k] { out.append(v) }
            case .keys(let ks):
                if let d = item as? [String: Any] { for k in ks { if let v = d[k] { out.append(v) } } }
            case .wildcard:
                if let a = item as? [Any] { out += a }
                else if let d = item as? [String: Any] { out += d.keys.sorted().map { d[$0]! } }
            case .index(let idx):
                if let a = item as? [Any] {
                    for i in idx { let j = i < 0 ? a.count + i : i; if j >= 0 && j < a.count { out.append(a[j]) } }
                }
            case .slice(let s, let e, let step):
                if let a = item as? [Any] {
                    var st = s ?? 0; if st < 0 { st += a.count }
                    var en = e ?? a.count; if en < 0 { en += a.count }
                    st = max(0, st); en = min(a.count, en)
                    if st < en { for i in stride(from: st, to: en, by: max(1, step)) { out.append(a[i]) } }
                }
            case .deep(let inner):
                var all: [Any] = []
                collectDeep(item, into: &all)
                out += try apply(inner, to: all)
            case .filter(let e):
                if let a = item as? [Any] { out += a.filter { evaluate(e, $0) } }
                else if let d = item as? [String: Any], evaluate(e, d) { out.append(d) }
            case .function(let f):
                out.append(callFunction(f, item))
            }
        }
        return out
    }

    private static func collectDeep(_ node: Any, into acc: inout [Any]) {
        acc.append(node)
        if let a = node as? [Any] { a.forEach { collectDeep($0, into: &acc) } }
        else if let d = node as? [String: Any] { d.keys.sorted().forEach { collectDeep(d[$0]!, into: &acc) } }
    }

    private static func callFunction(_ f: String, _ item: Any) -> Any {
        let arr = item as? [Any]
        let nums = arr?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
        switch f {
        case "length", "size": return arr?.count ?? (item as? [String: Any])?.count ?? (item as? String)?.count ?? 0
        case "min": return nums.min() ?? NSNull()
        case "max": return nums.max() ?? NSNull()
        case "sum": return nums.reduce(0, +)
        case "avg": return nums.isEmpty ? NSNull() : nums.reduce(0, +) / Double(nums.count)
        case "first": return arr?.first ?? NSNull()
        case "last": return arr?.last ?? NSNull()
        case "keys": return (item as? [String: Any])?.keys.sorted() ?? []
        default: return NSNull()
        }
    }

    private static func resolve(_ p: String, _ ctx: Any) -> Any? {
        var path = p.trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("@") { path.removeFirst() }
        if path.isEmpty { return ctx }
        return try? read(ctx, "$" + path)
    }

    private static func evaluate(_ e: Expr, _ ctx: Any) -> Bool {
        switch e {
        case .and(let a, let b): return evaluate(a, ctx) && evaluate(b, ctx)
        case .or(let a, let b): return evaluate(a, ctx) || evaluate(b, ctx)
        case .not(let a): return !evaluate(a, ctx)
        case .exists(let p):
            let v = resolve(p, ctx)
            return v != nil && !(v is NSNull)
        case .comparePaths(let a, let op, let b):
            guard let va = resolve(a, ctx), let vb = resolve(b, ctx) else { return false }
            return compare(va, op, toValue(vb))
        case .compare(let p, let op, let lit):
            guard let v = resolve(p, ctx) else { return op == "!=" }
            return compare(v, op, lit)
        }
    }

    private static func toValue(_ v: Any) -> Value {
        if let s = v as? String { return .str(s) }
        if let n = v as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .num(n.doubleValue) }
        if v is NSNull { return .null }
        return .str(String(describing: v))
    }

    private static func compare(_ v: Any, _ op: String, _ lit: Value) -> Bool {
        if op == "=~" {
            guard case .str(var pat) = lit else { return false }
            var opts: NSRegularExpression.Options = []
            if pat.hasPrefix("/") {
                if let last = pat.lastIndex(of: "/"), last != pat.startIndex {
                    let flags = pat[pat.index(after: last)...]
                    if flags.contains("i") { opts.insert(.caseInsensitive) }
                    pat = String(pat[pat.index(after: pat.startIndex)..<last])
                }
            }
            let s = stringOf(v)
            guard let re = try? NSRegularExpression(pattern: pat, options: opts) else { return false }
            return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        switch lit {
        case .null:
            let isNull = v is NSNull
            return op == "==" ? isNull : op == "!=" ? !isNull : false
        case .bool(let b):
            guard let n = v as? NSNumber else { return op == "!=" }
            let vb = n.boolValue
            return op == "==" ? vb == b : op == "!=" ? vb != b : false
        case .num(let d):
            let vd: Double
            if let n = v as? NSNumber { vd = n.doubleValue } else if let s = v as? String, let x = Double(s) { vd = x } else { return op == "!=" }
            switch op {
            case "==": return vd == d
            case "!=": return vd != d
            case ">": return vd > d
            case "<": return vd < d
            case ">=": return vd >= d
            case "<=": return vd <= d
            default: return false
            }
        case .str(let s):
            let vs = stringOf(v)
            switch op {
            case "==": return vs == s
            case "!=": return vs != s
            case ">": return vs > s
            case "<": return vs < s
            case ">=": return vs >= s
            case "<=": return vs <= s
            default: return false
            }
        }
    }

    /// 与 Java toString 近似：整数不带 .0，对象/数组转紧凑 JSON
    static func stringOf(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return n.stringValue
        }
        if JSONSerialization.isValidJSONObject(v),
           let d = try? JSONSerialization.data(withJSONObject: v, options: [.withoutEscapingSlashes, .sortedKeys]) {
            return String(decoding: d, as: UTF8.self)
        }
        return String(describing: v)
    }
}
