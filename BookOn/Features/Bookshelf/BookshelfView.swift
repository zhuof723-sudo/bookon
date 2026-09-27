import SwiftUI

@MainActor
final class BookshelfViewModel: ObservableObject {
    @Published var books: [Book] = []
    func reload() { books = AppDatabase.shared.allBooks().filter { $0.type & BookType.notShelf == 0 } }
    func remove(_ book: Book) { try? AppDatabase.shared.deleteBook(url: book.bookUrl); reload() }
}

struct BookshelfView: View {
    @StateObject private var vm = BookshelfViewModel()
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if vm.books.isEmpty {
                    empty
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(vm.books) { book in
                                NavigationLink { BookDetailView(book: book) } label: { cell(book) }
                                    .contextMenu {
                                        Button(role: .destructive) { vm.remove(book) } label: {
                                            Label("移出书架", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("书架")
            .onAppear { vm.reload() }
        }
    }

    private func cell(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                BookCoverView(url: book.displayCover, size: CGSize(width: 100, height: 136))
                if book.unreadCount > 0 {
                    Text("\(book.unreadCount)")
                        .font(.caption2).padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.red).foregroundColor(.white).clipShape(Capsule())
                        .padding(4)
                }
            }
            Text(book.name).font(.caption).lineLimit(1).foregroundColor(.primary)
            if let t = book.durChapterTitle {
                Text(t).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            } else {
                Text(book.author).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical").font(.system(size: 48)).foregroundColor(.secondary)
            Text("书架空空如也").font(.headline)
            Text("到「搜索」找书，进详情页加入书架").foregroundColor(.secondary).font(.subheadline)
        }
        .padding()
    }
}
