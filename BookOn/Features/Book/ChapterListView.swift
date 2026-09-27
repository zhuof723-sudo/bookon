import SwiftUI

struct ChapterListView: View {
    let book: Book
    let chapters: [BookChapter]
    let source: BookSource
    @State private var reverse = false

    var displayed: [BookChapter] { reverse ? chapters.reversed() : chapters }

    var body: some View {
        List {
            ForEach(displayed) { c in
                NavigationLink {
                    ReaderView(book: book, chapters: chapters, startIndex: c.index, source: source)
                } label: {
                    HStack {
                        Text(c.title)
                            .font(.subheadline)
                            .foregroundColor(c.index == book.durChapterIndex ? .accentColor : .primary)
                            .lineLimit(1)
                        if c.isVip { Text("VIP").font(.caption2).foregroundColor(.orange) }
                        Spacer()
                        if c.index == book.durChapterIndex {
                            Image(systemName: "bookmark.fill").font(.caption2).foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("目录 · \(chapters.count) 章")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { reverse.toggle() } label: {
                Image(systemName: reverse ? "arrow.up" : "arrow.down")
            }
        }
    }
}
