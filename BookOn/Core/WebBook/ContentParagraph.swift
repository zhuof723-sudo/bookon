import Foundation

/// 把正文切成“段落”，每段带其文字与**尾部**的段评气泡列表。
/// 原版 getComments 是 `comcont[段号] += '<img...>'`，气泡拼在该段文字之后；
/// 段落之间用 `\n` 分隔。所以这里：先用 ContentSegmenter 切成 text/image 片段，
/// 再按片段里的换行还原段落，把出现在换行之前、紧跟文字的 image 归到当前段的尾部气泡。
struct ContentParagraph {
    struct Bubble {
        let src: String
        let click: String?
    }
    var text: String
    var bubbles: [Bubble]

    static func parse(_ content: String) -> [ContentParagraph] {
        var paragraphs: [ContentParagraph] = []
        var currentText = ""
        var currentBubbles: [Bubble] = []

        func flush() {
            // 丢掉纯空白且无气泡的空段
            if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && currentBubbles.isEmpty {
                currentText = ""; currentBubbles = []
                return
            }
            paragraphs.append(ContentParagraph(text: currentText, bubbles: currentBubbles))
            currentText = ""; currentBubbles = []
        }

        for seg in ContentSegmenter.segments(content) {
            switch seg {
            case .text(let t):
                // 文本内部可能含换行 → 拆成多段
                let parts = t.components(separatedBy: "\n")
                for (i, part) in parts.enumerated() {
                    if i > 0 { flush() }   // 每遇到一个换行就结束上一段
                    currentText += part
                }
            case .image(let src, let click):
                currentBubbles.append(Bubble(src: src, click: click))
            }
        }
        flush()
        return paragraphs
    }
}
