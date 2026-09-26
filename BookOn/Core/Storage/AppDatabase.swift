import Foundation

/// 应用数据库：每张表存 “索引列 + 完整 JSON”。
/// 这样模型字段增减不用迁移，也天然保持与 Legado JSON 兼容。
final class AppDatabase {
    static let shared = AppDatabase()

    let db: SQLiteDB
    private let encoder = LegadoJSON.encoder()
    private let decoder = LegadoJSON.decoder()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookOn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("bookon.sqlite").path
        do {
            db = try SQLiteDB(path: path)
            try migrate()
        } catch {
            fatalError("数据库初始化失败: \(error)")
        }
    }

    private func migrate() throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS book_sources (
            url TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            grp TEXT,
            type INTEGER NOT NULL DEFAULT 0,
            enabled INTEGER NOT NULL DEFAULT 1,
            enabled_explore INTEGER NOT NULL DEFAULT 1,
            custom_order INTEGER NOT NULL DEFAULT 0,
            last_update_time INTEGER NOT NULL DEFAULT 0,
            has_explore INTEGER NOT NULL DEFAULT 0,
            json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_bs_order ON book_sources(custom_order);
        CREATE INDEX IF NOT EXISTS idx_bs_name ON book_sources(name);

        CREATE TABLE IF NOT EXISTS books (
            url TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            author TEXT NOT NULL,
            origin TEXT NOT NULL,
            grp INTEGER NOT NULL DEFAULT 0,
            type INTEGER NOT NULL DEFAULT 0,
            dur_chapter_time INTEGER NOT NULL DEFAULT 0,
            latest_chapter_time INTEGER NOT NULL DEFAULT 0,
            json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_books_name_author ON books(name, author);

        CREATE TABLE IF NOT EXISTS chapters (
            book_url TEXT NOT NULL,
            idx INTEGER NOT NULL,
            url TEXT NOT NULL,
            title TEXT NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (book_url, idx)
        );

        CREATE TABLE IF NOT EXISTS book_groups (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS replace_rules (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            grp TEXT,
            enabled INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS kv_cache (
            key TEXT PRIMARY KEY,
            value TEXT,
            deadline INTEGER NOT NULL DEFAULT 0
        );
        """)
    }

    // MARK: - 编解码

    private func json<T: Encodable>(_ v: T) throws -> String {
        String(decoding: try encoder.encode(v), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ s: String?) -> T? {
        guard let s, let d = s.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: d)
    }

    // MARK: - BookSource

    func allBookSources() -> [BookSource] {
        let rows = (try? db.query("SELECT json FROM book_sources ORDER BY custom_order ASC, name ASC")) ?? []
        return rows.compactMap { decode(BookSource.self, $0.string("json")) }
    }

    func enabledBookSources() -> [BookSource] {
        let rows = (try? db.query("SELECT json FROM book_sources WHERE enabled = 1 ORDER BY custom_order ASC")) ?? []
        return rows.compactMap { decode(BookSource.self, $0.string("json")) }
    }

    func bookSource(url: String) -> BookSource? {
        let rows = try? db.query("SELECT json FROM book_sources WHERE url = ?", [.text(url)])
        return rows?.first.flatMap { decode(BookSource.self, $0.string("json")) }
    }

    func bookSourceCount() -> Int {
        Int((try? db.query("SELECT COUNT(*) AS c FROM book_sources"))?.first?.int("c") ?? 0)
    }

    func upsert(_ sources: [BookSource]) throws {
        try db.transaction {
            for s in sources where !s.bookSourceUrl.isEmpty {
                try db.run("""
                INSERT OR REPLACE INTO book_sources
                (url, name, grp, type, enabled, enabled_explore, custom_order, last_update_time, has_explore, json)
                VALUES (?,?,?,?,?,?,?,?,?,?)
                """, [
                    .text(s.bookSourceUrl), .text(s.bookSourceName), s.bookSourceGroup.map { .text($0) } ?? .null,
                    .int(Int64(s.bookSourceType)), .int(s.enabled ? 1 : 0), .int(s.enabledExplore ? 1 : 0),
                    .int(Int64(s.customOrder)), .int(s.lastUpdateTime), .int(s.hasExplore ? 1 : 0),
                    .text(try json(s))
                ])
            }
        }
    }

    func upsert(_ source: BookSource) throws { try upsert([source]) }

    func deleteBookSources(urls: [String]) throws {
        try db.transaction {
            for u in urls { try db.run("DELETE FROM book_sources WHERE url = ?", [.text(u)]) }
        }
    }

    func setBookSourcesEnabled(urls: [String], enabled: Bool) throws {
        var list: [BookSource] = []
        for u in urls {
            if var s = bookSource(url: u) {
                s.enabled = enabled
                list.append(s)
            }
        }
        try upsert(list)
    }

    // MARK: - Book

    func allBooks() -> [Book] {
        let rows = (try? db.query("SELECT json FROM books ORDER BY dur_chapter_time DESC")) ?? []
        return rows.compactMap { decode(Book.self, $0.string("json")) }
    }

    func book(url: String) -> Book? {
        let rows = try? db.query("SELECT json FROM books WHERE url = ?", [.text(url)])
        return rows?.first.flatMap { decode(Book.self, $0.string("json")) }
    }

    func upsert(_ book: Book) throws {
        try db.run("""
        INSERT OR REPLACE INTO books (url, name, author, origin, grp, type, dur_chapter_time, latest_chapter_time, json)
        VALUES (?,?,?,?,?,?,?,?,?)
        """, [
            .text(book.bookUrl), .text(book.name), .text(book.author), .text(book.origin),
            .int(book.group), .int(Int64(book.type)), .int(book.durChapterTime), .int(book.latestChapterTime),
            .text(try json(book))
        ])
    }

    func deleteBook(url: String) throws {
        try db.transaction {
            try db.run("DELETE FROM books WHERE url = ?", [.text(url)])
            try db.run("DELETE FROM chapters WHERE book_url = ?", [.text(url)])
        }
    }

    // MARK: - Chapter

    func chapters(bookUrl: String) -> [BookChapter] {
        let rows = (try? db.query("SELECT json FROM chapters WHERE book_url = ? ORDER BY idx ASC", [.text(bookUrl)])) ?? []
        return rows.compactMap { decode(BookChapter.self, $0.string("json")) }
    }

    func replaceChapters(bookUrl: String, _ list: [BookChapter]) throws {
        try db.transaction {
            try db.run("DELETE FROM chapters WHERE book_url = ?", [.text(bookUrl)])
            for c in list {
                try db.run("INSERT INTO chapters (book_url, idx, url, title, json) VALUES (?,?,?,?,?)",
                           [.text(bookUrl), .int(Int64(c.index)), .text(c.url), .text(c.title), .text(try json(c))])
            }
        }
    }

    // MARK: - ReplaceRule

    func allReplaceRules() -> [ReplaceRule] {
        let rows = (try? db.query("SELECT json FROM replace_rules ORDER BY sort_order ASC")) ?? []
        return rows.compactMap { decode(ReplaceRule.self, $0.string("json")) }
    }

    func upsert(_ rules: [ReplaceRule]) throws {
        try db.transaction {
            for r in rules {
                try db.run("INSERT OR REPLACE INTO replace_rules (id, name, grp, enabled, sort_order, json) VALUES (?,?,?,?,?,?)",
                           [.int(r.id), .text(r.name), r.group.map { .text($0) } ?? .null,
                            .int(r.isEnabled ? 1 : 0), .int(Int64(r.order)), .text(try json(r))])
            }
        }
    }

    // MARK: - KV cache（供 java.put/get、cookie 等使用）

    func cacheGet(_ key: String) -> String? {
        let rows = try? db.query("SELECT value, deadline FROM kv_cache WHERE key = ?", [.text(key)])
        guard let r = rows?.first else { return nil }
        let deadline = r.int("deadline") ?? 0
        if deadline > 0 && deadline < Date.nowMillis {
            try? db.run("DELETE FROM kv_cache WHERE key = ?", [.text(key)])
            return nil
        }
        return r.string("value")
    }

    func cachePut(_ key: String, _ value: String, ttlSeconds: Int = 0) {
        let deadline: Int64 = ttlSeconds > 0 ? Date.nowMillis + Int64(ttlSeconds) * 1000 : 0
        try? db.run("INSERT OR REPLACE INTO kv_cache (key, value, deadline) VALUES (?,?,?)",
                    [.text(key), .text(value), .int(deadline)])
    }

    func cacheDelete(_ key: String) {
        try? db.run("DELETE FROM kv_cache WHERE key = ?", [.text(key)])
    }
}
