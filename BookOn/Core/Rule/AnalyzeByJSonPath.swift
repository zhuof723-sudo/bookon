import Foundation

/// 对应 Legado `AnalyzeByJSonPath`
final class AnalyzeByJSonPath {
    private let ctx: Any

    init(_ json: Any) {
        if let s = json as? String { ctx = JSONPath.parseJSON(s) ?? s }
        else { ctx = json }
    }

    func getString(_ rule: String) -> String? {
        if rule.isEmpty { return nil }
        var analyzer = RuleAnalyzer(rule, code: true)
        let rules = analyzer.splitRule("&&", "||")
        if rules.count == 1 {
            let inner = RuleAnalyzer(rule, code: true)
            var result = (try? inner.innerRuleBalanced("{$.") { self.getString($0) }) ?? ""
            if result.isEmpty {
                if let ob = try? JSONPath.read(ctx, rule) {
                    if let arr = ob as? [Any] { result = arr.map { JSONPath.stringOf($0) }.joined(separator: "\n") }
                    else { result = JSONPath.stringOf(ob) }
                }
            }
            return result
        }
        var texts: [String] = []
        for r in rules {
            if let t = getString(r), !t.isEmpty {
                texts.append(t)
                if analyzer.elementsType == "||" { break }
            }
        }
        return texts.joined(separator: "\n")
    }

    func getStringList(_ rule: String) -> [String] {
        var result: [String] = []
        if rule.isEmpty { return result }
        var analyzer = RuleAnalyzer(rule, code: true)
        let rules = analyzer.splitRule("&&", "||", "%%")
        if rules.count == 1 {
            let inner = RuleAnalyzer(rule, code: true)
            let st = (try? inner.innerRuleBalanced("{$.") { self.getString($0) }) ?? ""
            if st.isEmpty {
                if let ob = try? JSONPath.read(ctx, rule) {
                    if let arr = ob as? [Any] { result += arr.map { JSONPath.stringOf($0) } }
                    else { result.append(JSONPath.stringOf(ob)) }
                }
            } else {
                result.append(st)
            }
            return result
        }
        var results: [[String]] = []
        for r in rules {
            let t = getStringList(r)
            if !t.isEmpty {
                results.append(t)
                if analyzer.elementsType == "||" { break }
            }
        }
        return Self.merge(results, analyzer.elementsType)
    }

    func getObject(_ rule: String) -> Any? {
        try? JSONPath.read(ctx, rule)
    }

    func getList(_ rule: String) -> [Any] {
        if rule.isEmpty { return [] }
        var analyzer = RuleAnalyzer(rule, code: true)
        let rules = analyzer.splitRule("&&", "||", "%%")
        if rules.count == 1 {
            guard let ob = try? JSONPath.read(ctx, rules[0]) else { return [] }
            if let arr = ob as? [Any] { return arr }
            return ob is NSNull ? [] : [ob]
        }
        var results: [[Any]] = []
        for r in rules {
            let t = getList(r)
            if !t.isEmpty {
                results.append(t)
                if analyzer.elementsType == "||" { break }
            }
        }
        return Self.merge(results, analyzer.elementsType)
    }

    static func merge<T>(_ results: [[T]], _ type: String) -> [T] {
        guard let first = results.first else { return [] }
        if type == "%%" {
            var out: [T] = []
            for i in 0..<first.count { for t in results where i < t.count { out.append(t[i]) } }
            return out
        }
        return results.flatMap { $0 }
    }
}
