import SwiftUI

/// 简单的网络封面图（AsyncImage + 占位）
struct BookCoverView: View {
    let url: String?
    var size: CGSize = CGSize(width: 60, height: 82)

    var body: some View {
        Group {
            if let u = url, let link = URL(string: u) {
                AsyncImage(url: link) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                    case .failure: placeholder
                    default: ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var placeholder: some View {
        Image(systemName: "book.closed")
            .foregroundColor(.secondary)
            .font(.system(size: size.width * 0.4))
    }
}
