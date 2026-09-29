import SwiftUI
import WebKit

/// 神评 / 章评 / 作者说 / 相关推荐 的整幅横幅（原版 style:"full"，独占一行、块级）。
/// 书源把这些做成一张 SVG 图片（图里已经画好“神评/作家说/…”字样与数字），
/// 这里直接把 data-URI 的 SVG 渲染出来，点击执行其 click JS 打开对应页面。
struct ReviewBanner: View {
    let src: String
    let action: () -> Void
    @State private var height: CGFloat = 44

    var body: some View {
        Button(action: action) {
            SVGDataImage(src: src, height: $height)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .buttonStyle(.plain)
    }
}

/// 渲染 data:image/svg+xml;base64,... 的 SVG（用 WKWebView，自动按内容比例定高）。
struct SVGDataImage: UIViewRepresentable {
    let src: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        init(height: Binding<CGFloat>) { self.height = height }
        func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
            for d in [0.05, 0.25, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak webView] in
                    webView?.evaluateJavaScript("document.body.scrollHeight") { v, _ in
                        if let n = v as? NSNumber {
                            let h = max(CGFloat(truncating: n), 24)
                            if abs(h - self.height.wrappedValue) > 1 { self.height.wrappedValue = h }
                        }
                    }
                }
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.backgroundColor = .clear
        web.isUserInteractionEnabled = false   // 点击交给外层 Button
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // src 形如 data:image/svg+xml;base64,XXXX（选项后缀已在分段时剥离）
        let doc = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent;}
        img{display:block;width:100%;height:auto;}</style></head>
        <body><img src="\(src)"></body></html>
        """
        web.loadHTMLString(doc, baseURL: nil)
    }
}
