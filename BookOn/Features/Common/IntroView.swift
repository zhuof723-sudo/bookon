import SwiftUI
import WebKit

/// 简介展示：<useweb>/<usehtml> 存的是 HTML，需要真正渲染；
/// <md> 是 Markdown；其余是纯文本。
struct IntroView: View {
    let text: String

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    enum Kind { case webHTML(String), html(String), markdown(String), plain(String) }

    private var kind: Kind {
        let t = trimmed
        if t.hasPrefix("<useweb>") { return .webHTML(String(t.dropFirst(8))) }
        if t.hasPrefix("<usehtml>") { return .html(String(t.dropFirst(9))) }
        if t.hasPrefix("<md>") { return .markdown(String(t.dropFirst(4))) }
        return .plain(t)
    }

    var body: some View {
        switch kind {
        case .webHTML(let html), .html(let html):
            HTMLContent(html: html)
                .frame(minHeight: 40)
        case .markdown(let md):
            Text(renderMarkdown(md))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .plain(let p):
            Text(p)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func renderMarkdown(_ md: String) -> AttributedString {
        (try? AttributedString(markdown: md)) ?? AttributedString(md)
    }
}

/// 自动高度的 HTML 渲染视图（WKWebView）
struct HTMLContent: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var heightConstraint: NSLayoutConstraint?
        var onHeight: ((CGFloat) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { value, _ in
                if let h = value as? CGFloat, h > 0 { self.onHeight?(h) }
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.backgroundColor = .clear
        web.setContentHuggingPriority(.defaultLow, for: .vertical)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let doc = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin:0; padding:0; font: -apple-system-body; font-size:15px; line-height:1.7;
               color: \(UIColor.secondaryLabel.hexRGBA); word-break: break-word; background: transparent; }
        img, svg, video { max-width: 100% !important; height: auto !important; }
        a { color: \(UIColor.link.hexRGBA); text-decoration: none; }
        p { margin: 0 0 8px; }
        </style></head><body>\(html)</body></html>
        """
        web.loadHTMLString(doc, baseURL: nil)
    }
}

extension UIColor {
    var hexRGBA: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
