import Foundation

/// 把正文里保留下来的 `<img src="地址[,{option}]">` 标签切成 文本/图片 片段，
/// 对应 Legado 阅读排版阶段对 `<img>` 的识别（`ImageSpan` + `urlOption`）。
/// `option` 里常见字段：`click`（点击执行的 JS，比如段评气泡）、`style`、`width`。
enum ContentSegmenter {
    enum Segment {
        case text(String)
        case image(src: String, click: String?)
    }

    /// 与 `HTMLFormatter.formatKeepImg` 用的是同一条 Legado 正则：`formatKeepImg` 只是把地址部分
    /// 换成绝对地址，`,{...}` 选项原样保留在引号内（书源 JS 拼出来的属性值本身就带未转义的裸引号），
    /// 所以这里解析时必须用同一套“捕获平衡花括号”的规则，不能用简单的“遇到引号就停”。
    private static let imgTag = try! NSRegularExpression(
        pattern: "<img[^>]*\\ssrc\\s*=\\s*['\"]([^'\"{>]*\\{(?:[^{}]|\\{[^}>]+\\})+\\})['\"][^>]*>"
               + "|<img[^>]*\\ssrc\\s*=\\s*\"([^\">]+)\"[^>]*>",
        options: .caseInsensitive)

    static func segments(_ content: String) -> [Segment] {
        let ns = content as NSString
        var out: [Segment] = []
        var pos = 0
        for m in imgTag.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > pos {
                out.append(.text(ns.substring(with: NSRange(location: pos, length: m.range.location - pos))))
            }
            let raw = m.range(at: 1).location != NSNotFound
                ? ns.substring(with: m.range(at: 1))
                : ns.substring(with: m.range(at: 2))
            let (src, click) = splitOption(raw)
            out.append(.image(src: src, click: click))
            pos = m.range.location + m.range.length
        }
        if pos < ns.length {
            out.append(.text(ns.substring(from: pos)))
        }
        return out
    }

    /// "地址,{...}" → (地址, click 字段)。用 AnalyzeUrl.paramRegex（`\s*,\s*(?=\{)`）与 Legado 一致地切分。
    private static func splitOption(_ raw: String) -> (String, String?) {
        guard let m = AnalyzeUrl.paramRegex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let r = Range(m.range, in: raw) else { return (raw, nil) }
        let src = String(raw[..<r.lowerBound])
        let optionStr = String(raw[r.upperBound...])
        let obj = JSONLoose.parseObject(optionStr)
        let click = (obj?["click"] as? String)
        return (src, click)
    }
}
