import Foundation
import SwiftSoup

/// 对应 Legado `AnalyzeRule`：规则引擎总入口。
///
/// 支持：`@css:` `@XPath:` `@json:` / `$.` / `//` 自动识别、`@js:` `<js></js>`、`{{...}}` 内嵌、
/// `@put:{k:rule}` `@get:{k}`、`##正则##替换[###]`、`$1` 正则分组、`&&` `||` `%%` 组合。
final class AnalyzeRule {

    enum Mode { case xpath, json, `default`, js, regex, webJs }

    // 上下文
    let source: BookSource?
    var ruleData: RuleData?
    var book: Book?
    var chapter: BookChapter?
    var chapterData: RuleData?
    var js: JSEvaluator
    var extraBindings: [String: Any?] = [:]

    private(set) var content: Any?
    private(set) var baseUrl: String?
    private var redirectUrl: URL?
    private var isJSON = false
    private var isRegex = false

    private var byXPath: AnalyzeByXPath?
    private var byJSoup: AnalyzeByJSoup?
    private var byJSonPath: AnalyzeByJSonPath?

    private var stringRuleCache: [String: [SourceRule]] = [:]
    private var regexCache: [String: NSRegularExpression?] = [:]

    init(ruleData: RuleData? = nil, source: BookSource? = nil, js: JSEvaluator = UnavailableJSEvaluator()) {
        self.ruleData = ruleData
        self.source = source
        self.js = js
    }

    // MARK: - 上下文设置

    @discardableResult
    func setContent(_ content: Any, baseUrl: String? = nil) -> AnalyzeRule {
        self.content = content
        if content is Element || content is XMLDoc.Node || content is [String] { isJSON = false }
        else if content is [String: Any] || content is [Any] { isJSON = true }
        else {
            let s = String(describing: content).trimmingCharacters(in: .whitespacesAndNewlines)
            isJSON = (s.hasPrefix("{") && s.hasSuffix("}")) || (s.hasPrefix("[") && s.hasSuffix("]"))
        }
        if let baseUrl { setBaseUrl(baseUrl) }
        byXPath = nil; byJSoup = nil; byJSonPath = nil
        return self
    }

    @discardableResult
    func setBaseUrl(_ url: String?) -> AnalyzeRule {
        if let url { baseUrl = url }
        return self
    }

    @discardableResult
    func setRedirectUrl(_ url: String) -> URL? {
        if NetworkUtils.isDataUrl(url) { return redirectUrl }
        redirectUrl = URL(string: url) ?? redirectUrl
        return redirectUrl
    }

    // MARK: - 解析器懒加载

    private func xpath(_ o: Any) -> AnalyzeByXPath {
        if let n = o as? XMLDoc.Node { return AnalyzeByXPath(n) }
        if let e = o as? Element { return AnalyzeByXPath((try? e.outerHtml()) ?? "") }
        if let same = byXPath, isSameAsContent(o) { return same }
        let a = AnalyzeByXPath(o)
        if isSameAsContent(o) { byXPath = a }
        return a
    }

    private func jsoup(_ o: Any) -> AnalyzeByJSoup {
        if let e = o as? Element { return AnalyzeByJSoup(e) }
        if let n = o as? XMLDoc.Node { return AnalyzeByJSoup(n.asString) }
        if let same = byJSoup, isSameAsContent(o) { return same }
        let a = AnalyzeByJSoup(o)
        if isSameAsContent(o) { byJSoup = a }
        return a
    }

    private func jsonPath(_ o: Any) -> AnalyzeByJSonPath {
        if let same = byJSonPath, isSameAsContent(o) { return same }
        let a = AnalyzeByJSonPath(o)
        if isSameAsContent(o) { byJSonPath = a }
        return a
    }

    private func isSameAsContent(_ o: Any) -> Bool {
        guard let c = content else { return false }
        if let a = o as? String, let b = c as? String { return a == b }
        return (o as AnyObject) === (c as AnyObject)
    }

    // MARK: - 取列表

    func getStringList(_ rule: String?, _ mContent: Any? = nil, isUrl: Bool = false) throws -> [String]? {
        guard let rule, !rule.isEmpty else { return nil }
        return try getStringList(splitSourceRuleCached(rule), mContent, isUrl: isUrl)
    }

    func getStringList(_ ruleList: [SourceRule], _ mContent: Any? = nil, isUrl: Bool = false) throws -> [String]? {
        var result: Any?
        let content = mContent ?? self.content
        if let content, !ruleList.isEmpty {
            result = content
            do {
                for sr in ruleList {
                    try putRule(sr.putMap)
                    try sr.makeUpRule(result, self)
                    guard let r = result else { continue }
                    let rule = sr.rule
                    if !rule.isEmpty {
                        switch sr.mode {
                        case .js: result = try evalJS(rule, result: r)
                        case .webJs: result = try evalJS(rule, result: r)
                        case .json: result = jsonPath(r).getStringList(rule)
                        case .xpath: result = xpath(r).getStringList(rule)
                        case .default: result = jsoup(r).getStringList(rule)
                        case .regex: result = rule
                        }
                    }
                    if !sr.replaceRegex.isEmpty {
                        if let arr = result as? [Any] { result = arr.map { replaceRegex(JSONPath.stringOf($0), sr) } }
                        else if let r2 = result { result = replaceRegex(JSONPath.stringOf(r2), sr) }
                    }
                }
            }
        }
        guard let r = result else { return nil }
        var list: [String]
        if let s = r as? String { list = s.components(separatedBy: "\n") }
        else if let arr = r as? [Any] { list = arr.map { JSONPath.stringOf($0) } }
        else { list = [JSONPath.stringOf(r)] }
        if isUrl {
            var urls: [String] = []
            for u in list {
                let abs = NetworkUtils.getAbsoluteURL(redirectUrl?.absoluteString, u)
                if !abs.isEmpty, !urls.contains(abs) { urls.append(abs) }
            }
            return urls
        }
        return list
    }

    // MARK: - 取字符串

    func getString(_ rule: String?, _ mContent: Any? = nil, isUrl: Bool = false, unescape: Bool = true) throws -> String {
        guard let rule, !rule.isEmpty else { return "" }
        return try getString(splitSourceRuleCached(rule), mContent, isUrl: isUrl, unescape: unescape)
    }

    func getString(_ ruleList: [SourceRule], _ mContent: Any? = nil, isUrl: Bool = false, unescape: Bool = true) throws -> String {
        var result: Any?
        let content = mContent ?? self.content
        if let content, !ruleList.isEmpty {
            result = content
            do {
                for sr in ruleList {
                    try putRule(sr.putMap)
                    try sr.makeUpRule(result, self)
                    guard let r = result else { continue }
                    let rule = sr.rule
                    if !rule.trimmingCharacters(in: .whitespaces).isEmpty || sr.replaceRegex.isEmpty {
                        switch sr.mode {
                        case .js, .webJs: result = try evalJS(rule, result: r)
                        case .json: result = jsonPath(r).getString(rule)
                        case .xpath: result = xpath(r).getString(rule)
                        case .default: result = isUrl ? jsoup(r).getString0(rule) : jsoup(r).getString(rule)
                        case .regex: result = rule
                        }
                    }
                    if let r2 = result, !sr.replaceRegex.isEmpty {
                        result = replaceRegex(JSONPath.stringOf(r2), sr)
                    }
                }
            }
        }
        let str0 = JSONPath.stringOf(result)
        let str = (unescape && str0.contains("&")) ? Self.unescapeHtml(str0) : str0
        if isUrl {
            if str.trimmingCharacters(in: .whitespaces).isEmpty { return baseUrl ?? "" }
            return NetworkUtils.getAbsoluteURL(redirectUrl?.absoluteString, str)
        }
        return str
    }

    // MARK: - 取元素

    func getElement(_ ruleStr: String) throws -> Any? {
        guard !ruleStr.isEmpty, let content else { return nil }
        var result: Any? = content
        for sr in splitSourceRule(ruleStr, allInOne: true) {
            try putRule(sr.putMap)
            try sr.makeUpRule(result, self)
            guard let r = result else { continue }
            let rule = sr.rule
            switch sr.mode {
            case .regex: result = AnalyzeByRegex.getElement(JSONPath.stringOf(r), Self.splitNotBlank(rule, "&&"))
            case .js, .webJs: result = try evalJS(rule, result: r)
            case .json: result = jsonPath(r).getObject(rule)
            case .xpath: result = xpath(r).getElements(rule)
            case .default: result = jsoup(r).getElements(rule)
            }
            if !sr.replaceRegex.isEmpty { result = replaceRegex(JSONPath.stringOf(result), sr) }
        }
        return result
    }

    func getElements(_ ruleStr: String) throws -> [Any] {
        guard !ruleStr.isEmpty, let content else { return [] }
        var result: Any? = content
        for sr in splitSourceRule(ruleStr, allInOne: true) {
            try putRule(sr.putMap)
            guard let r = result else { continue }
            let rule = sr.rule
            switch sr.mode {
            case .regex: result = AnalyzeByRegex.getElements(JSONPath.stringOf(r), Self.splitNotBlank(rule, "&&"))
            case .js, .webJs: result = try evalJS(rule, result: r)
            case .json: result = jsonPath(r).getList(rule)
            case .xpath: result = xpath(r).getElements(rule)
            case .default: result = jsoup(r).getElements(rule)
            }
        }
        if let arr = result as? [Any] { return arr }
        if let arr = result as? [Element] { return arr }
        if let arr = result as? [XMLDoc.Node] { return arr }
        if let arr = result as? [[String]] { return arr }
        return []
    }

    // MARK: - 变量

    private func putRule(_ map: [String: String]) throws {
        for (k, v) in map { put(k, try getString(v)) }
    }

    @discardableResult
    func put(_ key: String, _ value: String) -> String {
        if let cd = chapterData { cd.putVariable(key, value) }
        else if let rd = ruleData { rd.putVariable(key, value) }
        else { AppDatabase.shared.cachePut("var::\(source?.bookSourceUrl ?? "")::\(key)", value) }
        return value
    }

    func get(_ key: String) -> String {
        if key == "bookName", let b = book { return b.name }
        if key == "title", let c = chapter { return c.title }
        if let v = chapterData?.getVariable(key), !v.isEmpty { return v }
        if let v = ruleData?.getVariable(key), !v.isEmpty { return v }
        return AppDatabase.shared.cacheGet("var::\(source?.bookSourceUrl ?? "")::\(key)") ?? ""
    }

    // MARK: - 正则替换

    private func replaceRegex(_ result: String, _ rule: SourceRule) -> String {
        guard !rule.replaceRegex.isEmpty else { return result }
        let regex = compileRegex(rule.replaceRegex)
        let replacement = Self.convertReplacement(rule.replacement)
        if rule.replaceFirst {
            // ##match##replace### ：取第一个匹配段，在其内部做一次替换
            guard let regex else { return rule.replacement }
            let ns = result as NSString
            guard let m = regex.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)) else { return "" }
            let matched = ns.substring(with: m.range)
            let mns = matched as NSString
            guard let m2 = regex.firstMatch(in: matched, range: NSRange(location: 0, length: mns.length)) else { return matched }
            let rep = regex.replacementString(for: m2, in: matched, offset: 0, template: replacement)
            return mns.replacingCharacters(in: m2.range, with: rep)
        }
        if let regex {
            return regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: replacement)
        }
        return result.replacingOccurrences(of: rule.replaceRegex, with: rule.replacement)
    }

    private func compileRegex(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache[pattern] { return cached }
        let re = try? NSRegularExpression(pattern: Self.convertJavaRegex(pattern), options: [])
        if regexCache.count > 32 { regexCache.removeAll() }
        regexCache[pattern] = re
        return re
    }

    /// Java `$1` 与 ICU `$1` 相同；Java 中 `\` 需转义为 `\\`，ICU 同样。基本兼容，仅处理 `${name}`。
    static func convertReplacement(_ s: String) -> String { s }

    /// Java 正则 → ICU：绝大多数语法一致。处理 Java 专有：`\p{Alpha}` 等 POSIX 类、`(?i)` 支持相同。
    static func convertJavaRegex(_ p: String) -> String {
        var s = p
        let posix = ["\\p{Alpha}": "[a-zA-Z]", "\\p{Digit}": "\\d", "\\p{Alnum}": "[a-zA-Z0-9]",
                     "\\p{Punct}": "\\p{P}", "\\p{Space}": "\\s", "\\p{Upper}": "[A-Z]", "\\p{Lower}": "[a-z]",
                     "\\p{Blank}": "[ \\t]", "\\p{Cntrl}": "\\p{Cc}", "\\p{XDigit}": "[0-9a-fA-F]"]
        for (k, v) in posix { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }

    // MARK: - JS

    func evalJS(_ script: String, result: Any? = nil) throws -> Any? {
        var b: [String: Any?] = [
            "java": self,
            "baseUrl": baseUrl,
            "result": result,
            "source": source,
            "book": book,
            "chapter": chapter,
        ]
        extraBindings.forEach { b[$0.key] = $0.value }
        return try js.eval(script, bindings: b)
    }

    // MARK: - 规则切分

    private func splitSourceRuleCached(_ rule: String) -> [SourceRule] {
        if let c = stringRuleCache[rule] { return c }
        let list = splitSourceRule(rule)
        if stringRuleCache.count > 64 { stringRuleCache.removeAll() }
        stringRuleCache[rule] = list
        return list
    }

    func splitSourceRule(_ ruleStr: String?, allInOne: Bool = false) -> [SourceRule] {
        guard let ruleStr, !ruleStr.isEmpty else { return [] }
        var list: [SourceRule] = []
        var mode: Mode = .default
        var start = 0
        if allInOne && ruleStr.hasPrefix(":") {
            mode = .regex; isRegex = true; start = 1
        } else if isRegex {
            mode = .regex
        }
        let ns = ruleStr as NSString
        for m in AnalyzeUrl.jsRegex.matches(in: ruleStr, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > start {
                let tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tmp.isEmpty { list.append(SourceRule(tmp, mode, isJSON: isJSON)) }
            }
            let script = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ns.substring(with: m.range(at: 1))
            list.append(SourceRule(script, .js, isJSON: isJSON))
            start = m.range.location + m.range.length
        }
        for m in Self.webJsRegex.matches(in: ruleStr, range: NSRange(location: 0, length: ns.length)) where m.range.location >= start {
            if m.range.location > start {
                let tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tmp.isEmpty { list.append(SourceRule(tmp, mode, isJSON: isJSON)) }
            }
            list.append(SourceRule(ns.substring(with: m.range(at: 1)), .webJs, isJSON: isJSON))
            start = m.range.location + m.range.length
        }
        if ns.length > start {
            let tmp = ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tmp.isEmpty { list.append(SourceRule(tmp, mode, isJSON: isJSON)) }
        }
        return list
    }

    // MARK: - SourceRule

    final class SourceRule {
        var mode: Mode
        var rule: String
        var replaceRegex = ""
        var replacement = ""
        var replaceFirst = false
        var putMap: [String: String] = [:]
        private var ruleParam: [String] = []
        private var ruleType: [Int] = []
        private let getRuleType = -2, jsRuleType = -1, defaultRuleType = 0
        var paramCount: Int { ruleParam.count }

        init(_ ruleStr: String, _ mode: Mode = .default, isJSON: Bool) {
            self.mode = mode
            var r = ruleStr
            let lower = ruleStr.lowercased()
            switch true {
            case mode == .js || mode == .regex: break
            case lower.hasPrefix("@css:"): self.mode = .default
            case ruleStr.hasPrefix("@@"): self.mode = .default; r = String(ruleStr.dropFirst(2))
            case lower.hasPrefix("@xpath:"): self.mode = .xpath; r = String(ruleStr.dropFirst(7))
            case lower.hasPrefix("@json:"): self.mode = .json; r = String(ruleStr.dropFirst(6))
            case isJSON || ruleStr.hasPrefix("$.") || ruleStr.hasPrefix("$["): self.mode = .json
            case ruleStr.hasPrefix("/"): self.mode = .xpath
            default: break
            }
            rule = r
            rule = splitPutRule(rule)

            // @get:{} 与 {{ }} 拆分
            var start = 0
            let ns = rule as NSString
            let matches = AnalyzeRule.evalRegex.matches(in: rule, range: NSRange(location: 0, length: ns.length))
            if let first = matches.first {
                let tmp = ns.substring(to: first.range.location)
                if self.mode != .js && self.mode != .regex && (first.range.location == 0 || !tmp.contains("##")) {
                    self.mode = .regex
                }
                for m in matches {
                    if m.range.location > start {
                        splitRegex(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
                    }
                    let t = ns.substring(with: m.range)
                    if t.lowercased().hasPrefix("@get:") {
                        ruleType.append(getRuleType)
                        ruleParam.append(String(t.dropFirst(6).dropLast()))
                    } else if t.hasPrefix("{{") {
                        ruleType.append(jsRuleType)
                        ruleParam.append(String(t.dropFirst(2).dropLast(2)))
                    } else {
                        splitRegex(t)
                    }
                    start = m.range.location + m.range.length
                }
            }
            if ns.length > start { splitRegex(ns.substring(from: start)) }
        }

        private func splitPutRule(_ ruleStr: String) -> String {
            var r = ruleStr
            let ns = ruleStr as NSString
            for m in AnalyzeRule.putRegex.matches(in: ruleStr, range: NSRange(location: 0, length: ns.length)).reversed() {
                let whole = ns.substring(with: m.range)
                r = r.replacingOccurrences(of: whole, with: "")
                if let obj = JSONLoose.parseObject(ns.substring(with: m.range(at: 1))) {
                    for (k, v) in obj { putMap[k] = (v as? String) ?? JSONPath.stringOf(v) }
                }
            }
            return r
        }

        /// 拆分 `$1` `$2`
        private func splitRegex(_ ruleStr: String) {
            var start = 0
            let firstPart = ruleStr.components(separatedBy: "##")[0]
            let ns = ruleStr as NSString
            let matches = AnalyzeRule.regexGroupRegex.matches(in: firstPart, range: NSRange(location: 0, length: (firstPart as NSString).length))
            if !matches.isEmpty {
                if mode != .js && mode != .regex { mode = .regex }
                for m in matches {
                    if m.range.location > start {
                        ruleType.append(defaultRuleType)
                        ruleParam.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
                    }
                    let t = ns.substring(with: m.range)
                    ruleType.append(Int(t.dropFirst()) ?? 0)
                    ruleParam.append(t)
                    start = m.range.location + m.range.length
                }
            }
            if ns.length > start {
                ruleType.append(defaultRuleType)
                ruleParam.append(ns.substring(from: start))
            }
        }

        /// 用 result / 变量 / JS 结果拼回 rule，再拆出 `##` 替换段
        func makeUpRule(_ result: Any?, _ analyzer: AnalyzeRule) throws {
            if !ruleParam.isEmpty {
                var info = ""
                var index = ruleParam.count
                while index > 0 {
                    index -= 1
                    let regType = ruleType[index]
                    if regType > defaultRuleType {
                        if let list = result as? [String] {
                            if list.count > regType { info = list[regType] + info }
                        } else if let list = result as? [Any] {
                            if list.count > regType { info = JSONPath.stringOf(list[regType]) + info }
                        } else {
                            info = ruleParam[index] + info
                        }
                    } else if regType == jsRuleType {
                        let p = ruleParam[index]
                        if Self.isRule(p) {
                            info = try analyzer.getString([SourceRule(p, .default, isJSON: false)]) + info
                        } else {
                            let v = try analyzer.evalJS(p, result: result)
                            info = JSValueFormat.string(v) + info
                        }
                    } else if regType == getRuleType {
                        info = analyzer.get(ruleParam[index]) + info
                    } else {
                        info = ruleParam[index] + info
                    }
                }
                rule = info
            }
            let parts = rule.components(separatedBy: "##")
            rule = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if parts.count > 1 { replaceRegex = parts[1] }
            if parts.count > 2 { replacement = parts[2] }
            if parts.count > 3 { replaceFirst = true }
        }

        private static func isRule(_ s: String) -> Bool {
            s.hasPrefix("@") || s.hasPrefix("$.") || s.hasPrefix("$[") || s.hasPrefix("//")
        }
    }

    // MARK: - 常量 & 工具

    static let putRegex = try! NSRegularExpression(pattern: "@put:(\\{[^}]+?\\})", options: .caseInsensitive)
    static let evalRegex = try! NSRegularExpression(pattern: "@get:\\{[^}]+?\\}|\\{\\{[\\w\\W]*?\\}\\}", options: .caseInsensitive)
    static let regexGroupRegex = try! NSRegularExpression(pattern: "\\$\\d{1,2}")
    static let webJsRegex = try! NSRegularExpression(pattern: "@webjs:([\\w\\W]{5,})", options: .caseInsensitive)

    static func splitNotBlank(_ s: String, _ sep: String) -> [String] {
        s.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// HTML 实体反转义（对应 StringEscapeUtils.unescapeHtml4）
    static func unescapeHtml(_ s: String) -> String {
        (try? Entities.unescape(s)) ?? s
    }
}
