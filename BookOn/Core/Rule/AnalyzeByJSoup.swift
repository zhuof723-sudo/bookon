import Foundation
import SwiftSoup

/// 对应 Legado `AnalyzeByJSoup`：默认规则语法（`class.xx.0@tag.a@text`、`@CSS:` 等）
final class AnalyzeByJSoup {
    private let element: Element

    init(_ doc: Any) {
        element = Self.parse(doc)
    }

    private static func parse(_ doc: Any) -> Element {
        if let e = doc as? Element { return e }
        let s = String(describing: doc)
        if s.lowercased().hasPrefix("<?xml"), let d = try? SwiftSoup.parse(s, "", Parser.xmlParser()) { return d }
        return (try? SwiftSoup.parse(s)) ?? Document("")
    }

    // MARK: - 对外

    func getElements(_ rule: String) -> [Element] {
        getElements(element, rule)
    }

    func getString(_ rule: String) -> String? {
        if rule.isEmpty { return nil }
        let list = getStringList(rule)
        if list.isEmpty { return nil }
        return list.count == 1 ? list[0] : list.joined(separator: "\n")
    }

    func getString0(_ rule: String) -> String {
        getStringList(rule).first ?? ""
    }

    func getStringList(_ ruleStr: String) -> [String] {
        var textS: [String] = []
        if ruleStr.isEmpty { return textS }
        let (isCss, elementsRule) = Self.splitCss(ruleStr)
        if elementsRule.isEmpty {
            textS.append(element.data())
            return textS
        }
        var analyzer = RuleAnalyzer(elementsRule)
        let rules = analyzer.splitRule("&&", "||", "%%")
        var results: [[String]] = []
        for r in rules {
            var temp: [String]?
            if isCss {
                if let at = r.lastIndex(of: "@") {
                    let sel = String(r[..<at]), last = String(r[r.index(after: at)...])
                    if let es = try? element.select(sel) { temp = getResultLast(es.array(), last) }
                } else if let es = try? element.select(r) {
                    temp = getResultLast(es.array(), "text")
                }
            } else {
                temp = getResultList(r)
            }
            if let t = temp, !t.isEmpty {
                results.append(t)
                if analyzer.elementsType == "||" { break }
            }
        }
        if results.isEmpty { return textS }
        if analyzer.elementsType == "%%" {
            for i in 0..<results[0].count {
                for t in results where i < t.count { textS.append(t[i]) }
            }
        } else {
            results.forEach { textS += $0 }
        }
        return textS
    }

    // MARK: - 元素

    private func getElements(_ temp: Element?, _ rule: String) -> [Element] {
        guard let temp, !rule.isEmpty else { return [] }
        let (isCss, elementsRule) = Self.splitCss(rule)
        var analyzer = RuleAnalyzer(elementsRule)
        let rules = analyzer.splitRule("&&", "||", "%%")
        var lists: [[Element]] = []
        if isCss {
            for r in rules {
                let es = (try? temp.select(r).array()) ?? []
                lists.append(es)
                if !es.isEmpty && analyzer.elementsType == "||" { break }
            }
        } else {
            for r in rules {
                var rs = RuleAnalyzer(r)
                rs.trim()
                let parts = rs.splitRule("@")
                var el: [Element]
                if parts.count > 1 {
                    el = [temp]
                    for p in parts {
                        var es: [Element] = []
                        for et in el { es += getElements(et, p) }
                        el = es
                    }
                } else {
                    var single = ElementsSingle(); el = single.getElementsSingle(temp, r)
                }
                lists.append(el)
                if !el.isEmpty && analyzer.elementsType == "||" { break }
            }
        }
        var out: [Element] = []
        if analyzer.elementsType == "%%", let first = lists.first {
            for i in 0..<first.count {
                for es in lists where i < es.count { out.append(es[i]) }
            }
        } else {
            lists.forEach { out += $0 }
        }
        return out
    }

    private func getResultList(_ ruleStr: String) -> [String]? {
        if ruleStr.isEmpty { return nil }
        var elements: [Element] = [element]
        var analyzer = RuleAnalyzer(ruleStr)
        analyzer.trim()
        let rules = analyzer.splitRule("@")
        let last = rules.count - 1
        for i in 0..<last {
            var es: [Element] = []
            for elt in elements { var single = ElementsSingle(); es += single.getElementsSingle(elt, rules[i]) }
            elements = es
        }
        return elements.isEmpty ? nil : getResultLast(elements, rules[last])
    }

    private func getResultLast(_ elements: [Element], _ lastRule: String) -> [String] {
        var textS: [String] = []
        switch lastRule {
        case "text":
            for e in elements { if let t = try? e.text(), !t.isEmpty { textS.append(t) } }
        case "textNodes":
            for e in elements {
                let tn = e.textNodes().map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !tn.isEmpty { textS.append(tn.joined(separator: "\n")) }
            }
        case "ownText":
            for e in elements { let t = e.ownText(); if !t.isEmpty { textS.append(t) } }
        case "html":
            let es = Elements(elements)
            _ = try? es.select("script").remove()
            _ = try? es.select("style").remove()
            if let h = try? es.outerHtml(), !h.isEmpty { textS.append(h) }
        case "all":
            textS.append((try? Elements(elements).outerHtml()) ?? "")
        default:
            for e in elements {
                let v = (try? e.attr(lastRule)) ?? ""
                if v.trimmingCharacters(in: .whitespaces).isEmpty || textS.contains(v) { continue }
                textS.append(v)
            }
        }
        return textS
    }

    private static func splitCss(_ rule: String) -> (Bool, String) {
        if rule.lowercased().hasPrefix("@css:") {
            return (true, String(rule.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        return (false, rule)
    }

    // MARK: - 单段规则 + 索引（tag.div.-1  /  class.x!0  /  tag.li[1:3]）

    struct ElementsSingle {
        enum Index { case single(Int), range(Int?, Int?, Int) }
        var split: Character = "."
        var beforeRule = ""
        var indexDefault: [Int] = []
        var indexes: [Index] = []

        mutating func getElementsSingle(_ temp: Element, _ rule: String) -> [Element] {
            findIndexSet(rule)
            var elements: [Element]
            if beforeRule.isEmpty {
                elements = temp.children().array()
            } else {
                let parts = beforeRule.components(separatedBy: ".")
                let arg = parts.count > 1 ? parts[1...].joined(separator: ".") : ""
                switch parts[0] {
                case "children": elements = temp.children().array()
                case "class": elements = (try? temp.getElementsByClass(arg).array()) ?? []
                case "tag": elements = (try? temp.getElementsByTag(arg).array()) ?? []
                case "id": elements = ((try? temp.getElementById(arg)) ?? nil).map { [$0] } ?? []
                case "text": elements = (try? temp.getElementsContainingOwnText(arg).array()) ?? []
                default: elements = (try? temp.select(beforeRule).array()) ?? []
                }
            }
            let len = elements.count
            var indexSet: [Int] = []   // 保序去重
            func add(_ i: Int) { if !indexSet.contains(i) { indexSet.append(i) } }

            if indexes.isEmpty {
                for it in indexDefault.reversed() {
                    if it >= 0 && it < len { add(it) } else if it < 0 && len >= -it { add(it + len) }
                }
            } else {
                for ix in indexes.reversed() {
                    switch ix {
                    case .single(let it):
                        if it >= 0 && it < len { add(it) } else if it < 0 && len >= -it { add(it + len) }
                    case .range(let sX, let eX, let stepX):
                        var start = sX ?? 0; if start < 0 { start += len }
                        var end = eX ?? (len - 1); if end < 0 { end += len }
                        if (start < 0 && end < 0) || (start >= len && end >= len) { continue }
                        if start >= len { start = len - 1 } else if start < 0 { start = 0 }
                        if end >= len { end = len - 1 } else if end < 0 { end = 0 }
                        if start == end || stepX >= len { add(start); continue }
                        let step = stepX > 0 ? stepX : (-stepX < len ? stepX + len : 1)
                        if end > start { for i in stride(from: start, through: end, by: max(1, step)) { add(i) } }
                        else { for i in stride(from: start, through: end, by: -max(1, step)) { add(i) } }
                    }
                }
            }

            if split == "!" {
                let ex = Set(indexSet)
                return elements.enumerated().filter { !ex.contains($0.offset) }.map(\.element)
            } else if split == "." {
                return indexSet.map { elements[$0] }
            }
            return elements
        }

        private mutating func findIndexSet(_ rule: String) {
            let rus = Array(rule.trimmingCharacters(in: .whitespaces))
            guard !rus.isEmpty else { split = " "; beforeRule = ""; return }
            var len = rus.count
            var curMinus = false
            var curList: [Int?] = []
            var l = ""
            if rus[len - 1] == "]" {
                len -= 1
                len -= 1
                while len >= 0 {
                    var rl = rus[len]
                    if rl == " " { len -= 1; continue }
                    if rl.isNumber { l = String(rl) + l }
                    else if rl == "-" { curMinus = true }
                    else {
                        let curInt: Int? = l.isEmpty ? nil : (curMinus ? -Int(l)! : Int(l)!)
                        if rl == ":" {
                            curList.append(curInt)
                        } else {
                            if curList.isEmpty {
                                guard let ci = curInt else { break }
                                indexes.append(.single(ci))
                            } else {
                                indexes.append(.range(curInt, curList.last!, curList.count == 2 ? (curList.first! ?? 1) : 1))
                                curList.removeAll()
                            }
                            if rl == "!" {
                                split = "!"
                                repeat { len -= 1; rl = len >= 0 ? rus[len] : "[" } while len > 0 && rl == " "
                            }
                            if rl == "[" {
                                beforeRule = String(rus[0..<max(0, len)])
                                return
                            }
                            if rl != "," { break }
                        }
                        l = ""; curMinus = false
                    }
                    len -= 1
                }
            } else {
                len -= 1
                while len >= 0 {
                    let rl = rus[len]
                    if rl == " " { len -= 1; continue }
                    if rl.isNumber { l = String(rl) + l }
                    else if rl == "-" { curMinus = true }
                    else {
                        if rl == "!" || rl == "." || rl == ":" {
                            guard let n = Int(l) else { break }
                            indexDefault.append(curMinus ? -n : n)
                            if rl != ":" {
                                split = rl
                                beforeRule = String(rus[0..<len])
                                return
                            }
                        } else { break }
                        l = ""; curMinus = false
                    }
                    len -= 1
                }
            }
            split = " "
            beforeRule = String(rus)
            indexDefault.removeAll()
            indexes.removeAll()
        }
    }
}
