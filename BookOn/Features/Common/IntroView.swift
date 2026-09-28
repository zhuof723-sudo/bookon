import SwiftUI
import WebKit

/// 简介展示：<useweb>/<usehtml> 存的是 HTML，需要真正渲染；
/// <md> 是 Markdown；其余是纯文本。
struct IntroView: View {
    let text: String
    @State private var webHeight: CGFloat = 80

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
            HTMLContent(html: html, height: $webHeight)
                .frame(maxWidth: .infinity)
                .frame(height: webHeight)
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
/// 关键点：SwiftUI 的 UIViewRepresentable 不会自动帮 WKWebView 撑高度，
/// 必须实测网页内容高度后写回 `height` binding，否则整块视图会以 0 高度收起、
/// 看起来就像“简介消失了”。
struct HTMLContent: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        init(height: Binding<CGFloat>) { self.height = height }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure(webView)
            // 内嵌图片（含 base64 SVG）可能在 didFinish 后才完成布局，补测几次
            for delay in [0.15, 0.4, 0.9] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak webView] in
                    guard let webView else { return }
                    self.measure(webView)
                }
            }
        }

        private func measure(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] value, _ in
                guard let self else { return }
                if let h = value as? NSNumber {
                    let newHeight = max(CGFloat(truncating: h), 40)
                    if abs(newHeight - self.height.wrappedValue) > 1 {
                        self.height.wrappedValue = newHeight
                    }
                }
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.backgroundColor = .clear
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.height = $height
        let doc = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body { margin:0; padding:0; }
        body { font: -apple-system-body; font-size:15px; line-height:1.7;
               color: \(UIColor.label.hexRGBA); word-break: break-word; background: transparent; }
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
