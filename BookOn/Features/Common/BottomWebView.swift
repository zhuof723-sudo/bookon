import SwiftUI
import WebKit

/// 对应 Legado `BottomWebViewDialog`（简化版）：以底部弹窗展示预取到的 HTML 页面。
/// 用于书源 JS 调用 `java.showBrowser` / `startBrowser`（段评、章评、书评、作家说等评论页）。
struct BottomWebView: View {
    let title: String
    let html: String?
    let url: String
    /// 书源在 commentViewerConfig() 里给的高度占比（0~1），段评默认约 0.62（半屏）
    var heightFraction: Double = 0.62
    @Environment(\.dismiss) private var dismiss

    private var detents: Set<PresentationDetent> {
        let f = min(max(heightFraction, 0.3), 0.98)
        // 半屏为主，可上拉到接近全屏
        return [.fraction(f), .large]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let html, !html.isEmpty {
                    RawHTMLWebView(html: html, baseURL: URL(string: url))
                } else if let u = URL(string: url) {
                    RawURLWebView(url: u)
                } else {
                    Text("无法打开").foregroundColor(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        // 半屏弹窗（对应原版评论页的 BottomSheet），可上拉放大
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }
}

/// 直接加载已下载好的 HTML 字符串（不再重新请求网络）
struct RawHTMLWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ web: WKWebView, context: Context) {
        web.loadHTMLString(html, baseURL: baseURL)
    }
}

/// 加载 URL（预取失败时的兜底）
struct RawURLWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ web: WKWebView, context: Context) {
        web.load(URLRequest(url: url))
    }
}

/// 全局桥接：JS 里的 java.showBrowser / startBrowser 调用后，把要展示的页面发布到这里，
/// 由最外层（App 根视图）监听并弹出 BottomWebView。
@MainActor
final class BrowserPresenter: ObservableObject {
    static let shared = BrowserPresenter()

    struct Request: Identifiable {
        let id = UUID()
        let title: String
        let html: String?
        let url: String
        var heightFraction: Double = 0.62
    }

    @Published var request: Request?

    func show(title: String, html: String?, url: String, heightFraction: Double = 0.62) {
        request = Request(title: title, html: html, url: url, heightFraction: heightFraction)
    }
}
