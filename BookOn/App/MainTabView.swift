import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            BookshelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
            ExploreView()
                .tabItem { Label("发现", systemImage: "safari") }
            MineView()
                .tabItem { Label("我的", systemImage: "person.circle") }
        }
    }
}

struct BookshelfView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("书架空空如也")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("书架")
        }
    }
}

struct ExploreView: View {
    var body: some View {
        NavigationStack {
            Text("导入书源后可在此发现书籍")
                .foregroundColor(.secondary)
                .navigationTitle("发现")
        }
    }
}

struct MineView: View {
    @State private var sourceCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        BookSourceListView()
                    } label: {
                        HStack {
                            Label("书源管理", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Text("\(sourceCount)").foregroundColor(.secondary)
                        }
                    }
                    Label("替换净化", systemImage: "wand.and.stars").foregroundColor(.secondary)
                    Label("备份与恢复", systemImage: "externaldrive").foregroundColor(.secondary)
                }
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("我的")
            .onAppear { sourceCount = AppDatabase.shared.bookSourceCount() }
        }
    }
}
