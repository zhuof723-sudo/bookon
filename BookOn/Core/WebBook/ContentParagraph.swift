import Foundation

/// 把正文切成“显示单元”。每个单元要么是一段文字（可带**行内段评气泡**），要么是一个**块级图片**
/// （神评 / 章评 / 作者说 / 相关推荐 / 正文插图，独占一行）。
///
/// 依据原版书源的生成方式区分：
/// - 段评（style=text）：`comcont[段号] += '<img...>'`，气泡拼在**该段文字末尾** → 行内小气泡。
/// - 神评 / 章评 / 作者说 / 相关（style=full 或无选项）：`result += '\n<img...>'`，前面有换行、
///   自己独占一段 → 块级整幅，单独一行。
struct ContentParagraph: Identifiable {
    enum Kind {
        case text                                   // 文字段落（可带尾部行内气泡）
        case blockImage(src: String, click: String?) // 块级图片（神评/章评/作者说/相关）
    }
    struct Bubble {
        let src: String
        let click: String?
    }

    let id = UUID()
    var kind: Kind
    var text: String = ""
    var bubbles: [Bubble] = []   // 仅 text 段落用：尾部行内段评气泡

    static func parse(_ content: String) -> [ContentParagraph] {
        var out: [ContentParagraph] = []
        var curText = ""
        var curBubbles: [Bubble] = []
        var hasText = false

        func flushText() {
            if hasText || !curBubbles.isEmpty {
                if !curText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !curBubbles.isEmpty {
                    out.append(ContentParagraph(kind: .text, text: curText, bubbles: curBubbles))
                }
            }
            curText = ""; curBubbles = []; hasText = false
        }

        for seg in ContentSegmenter.segments(content) {
            switch seg {
            case .text(let t):
                let parts = t.components(separatedBy: "\n")
                for (i, part) in parts.enumerated() {
                    if i > 0 { flushText() }   // 换行 = 段落结束
                    if !part.isEmpty { hasText = true }
                    curText += part
                }
            case .image(let src, let click, let style):
                switch style {
                case .text:
                    // 行内段评气泡：挂到当前段落尾部
                    curBubbles.append(Bubble(src: src, click: click))
                case .full, .normal:
                    // 块级：先结束当前文字段，再单独成块
                    flushText()
                    out.append(ContentParagraph(kind: .blockImage(src: src, click: click)))
                }
            }
        }
        flushText()
        return out
    }
}
