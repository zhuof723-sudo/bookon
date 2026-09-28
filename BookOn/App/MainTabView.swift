import SwiftUI

struct MainTabView: View {
    @StateObject private var browser = BrowserPresenter.shared

    var body: some View {
        TabView {
            BookshelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            MineView()
                .tabItem { Label("我的", systemImage: "person.circle") }
        }
        // 书源 JS 调用 java.showBrowser / startBrowser（段评/章评/书评等）时，从这里弹出
        .sheet(item: $browser.request) { req in
            BottomWebView(title: req.title, html: req.html, url: req.url)
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
