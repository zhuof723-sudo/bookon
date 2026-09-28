import SwiftUI

/// 对应 Legado 正文里的段评气泡（书源用 `<img src="data:...,{"click":"..."}">` 注入）。
/// Legado 原生端是把气泡画进 Canvas 的 `ReviewColumn`；这里用一个轻量气泡视图代替，
/// 点击行为对齐 `ContentTextView.touch` 里 `ImageColumn` 的默认点击：执行 click JS。
struct CommentBubble: View {
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 12))
                if let count, count > 0 {
                    Text(count > 999 ? "999+" : "\(count)")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
