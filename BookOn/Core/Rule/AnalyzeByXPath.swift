import Foundation
import libxml2

/// 基于 libxml2 的 HTML/XML 文档与 XPath 查询（对应 Legado 的 JsoupXpath / JXNode）
final class XMLDoc {
    final class Node {
        let ptr: xmlNodePtr
        let doc: XMLDoc          // 持有文档，防止提前释放
        init(_ ptr: xmlNodePtr, _ doc: XMLDoc) { self.ptr = ptr; self.doc = doc }

        var isElement: Bool { ptr.pointee.type == XML_ELEMENT_NODE }

        var name: String { ptr.pointee.name.map { String(cString: $0) } ?? "" }

        /// 文本节点/属性节点返回其值；元素节点返回所有后代文本
        var text: String {
            guard let c = xmlNodeGetContent(ptr) else { return "" }
            defer { xmlFree(c) }
            return String(cString: c)
        }

        /// 元素 outerHTML
        var outerHtml: String {
            guard isElement, let buf = xmlBufferCreate() else { return text }
            defer { xmlBufferFree(buf) }
            htmlNodeDump(buf, doc.docPtr, ptr)
            guard let content = xmlBufferContent(buf) else { return "" }
            return String(cString: content)
        }

        /// 与 JXNode.asString 一致：元素 → outerHtml，其他 → 文本值
        var asString: String { isElement ? outerHtml : text }

        func sel(_ xpath: String) -> [Node] { doc.evaluate(xpath, context: ptr) }
    }

    private(set) var docPtr: htmlDocPtr?

    init(html: String) {
        var h = html
        let trimmed = h.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasSuffix("</td>") { h = "<tr>\(h)</tr>" }
        if h.hasSuffix("</tr>") || h.hasSuffix("</tbody>") { h = "<table>\(h)</table>" }
        let bytes = Array(h.utf8)
        if trimmed.lowercased().hasPrefix("<?xml") {
            docPtr = bytes.withUnsafeBufferPointer { p in
                xmlReadMemory(p.baseAddress, Int32(p.count), "", "UTF-8",
                              Int32(XML_PARSE_RECOVER.rawValue | XML_PARSE_NOERROR.rawValue | XML_PARSE_NOWARNING.rawValue | XML_PARSE_NONET.rawValue))
            }
        } else {
            docPtr = bytes.withUnsafeBufferPointer { p in
                htmlReadMemory(p.baseAddress, Int32(p.count), "", "UTF-8",
                               Int32(HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue | HTML_PARSE_NONET.rawValue))
            }
        }
    }

    deinit { if let d = docPtr { xmlFreeDoc(d) } }

    var root: Node? {
        guard let d = docPtr, let r = xmlDocGetRootElement(d) else { return nil }
        return Node(r, self)
    }

    /// 执行 XPath，返回节点列表；若结果为字符串/数字/布尔（如 `string(...)`、`count(...)`），包成文本节点
    func evaluate(_ xpath: String, context: xmlNodePtr? = nil) -> [Node] {
        guard let d = docPtr, let ctx = xmlXPathNewContext(d) else { return [] }
        defer { xmlXPathFreeContext(ctx) }
        if let c = context { ctx.pointee.node = c }
        guard let result = xmlXPathEvalExpression(xpath, ctx) else { return [] }
        defer { xmlXPathFreeObject(result) }

        switch result.pointee.type {
        case XPATH_NODESET:
            guard let set = result.pointee.nodesetval, set.pointee.nodeNr > 0, let tab = set.pointee.nodeTab else { return [] }
            return (0..<Int(set.pointee.nodeNr)).compactMap { tab[$0].map { Node($0, self) } }
        case XPATH_STRING:
            guard let s = result.pointee.stringval else { return [] }
            return [makeTextNode(String(cString: s))]
        case XPATH_NUMBER:
            let v = result.pointee.floatval
            let s = v == v.rounded() ? String(Int64(v)) : String(v)
            return [makeTextNode(s)]
        case XPATH_BOOLEAN:
            return [makeTextNode(result.pointee.boolval != 0 ? "true" : "false")]
        default:
            return []
        }
    }

    /// 保存动态创建的文本节点，随文档一起释放
    private var scratch: [xmlNodePtr] = []
    private func makeTextNode(_ s: String) -> Node {
        let n = xmlNewText(s)!
        scratch.append(n)
        return Node(n, self)
    }
}

/// 对应 Legado `AnalyzeByXPath`
final class AnalyzeByXPath {
    private let doc: XMLDoc
    private let node: XMLDoc.Node?

    init(_ input: Any) {
        if let n = input as? XMLDoc.Node {
            doc = n.doc; node = n
        } else {
            doc = XMLDoc(html: String(describing: input)); node = nil
        }
    }

    private func getResult(_ xpath: String) -> [XMLDoc.Node] {
        if let n = node { return n.sel(xpath) }
        return doc.evaluate(xpath)
    }

    func getElements(_ xpath: String) -> [XMLDoc.Node] {
        if xpath.isEmpty { return [] }
        var analyzer = RuleAnalyzer(xpath)
        let rules = analyzer.splitRule("&&", "||", "%%")
        if rules.count == 1 { return getResult(rules[0]) }
        var results: [[XMLDoc.Node]] = []
        for r in rules {
            let t = getElements(r)
            if !t.isEmpty { results.append(t); if analyzer.elementsType == "||" { break } }
        }
        return AnalyzeByJSonPath.merge(results, analyzer.elementsType)
    }

    func getStringList(_ xpath: String) -> [String] {
        var analyzer = RuleAnalyzer(xpath)
        let rules = analyzer.splitRule("&&", "||", "%%")
        if rules.count == 1 { return getResult(xpath).map(\.asString) }
        var results: [[String]] = []
        for r in rules {
            let t = getStringList(r)
            if !t.isEmpty { results.append(t); if analyzer.elementsType == "||" { break } }
        }
        return AnalyzeByJSonPath.merge(results, analyzer.elementsType)
    }

    func getString(_ rule: String) -> String? {
        var analyzer = RuleAnalyzer(rule)
        let rules = analyzer.splitRule("&&", "||")
        if rules.count == 1 {
            let r = getResult(rule)
            return r.isEmpty ? nil : r.map(\.asString).joined(separator: "\n")
        }
        var texts: [String] = []
        for r in rules {
            if let t = getString(r), !t.isEmpty { texts.append(t); if analyzer.elementsType == "||" { break } }
        }
        return texts.joined(separator: "\n")
    }
}
