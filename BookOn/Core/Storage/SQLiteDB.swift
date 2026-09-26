import Foundation
import SQLite3

/// 极简 SQLite 封装：串行队列、参数绑定、行读取。
final class SQLiteDB {
    enum Value {
        case text(String), int(Int64), real(Double), null
    }

    struct Row {
        fileprivate let values: [String: Value]
        func string(_ k: String) -> String? {
            if case .text(let s)? = values[k] { return s }
            if case .int(let i)? = values[k] { return String(i) }
            return nil
        }
        func int(_ k: String) -> Int64? {
            if case .int(let i)? = values[k] { return i }
            if case .text(let s)? = values[k] { return Int64(s) }
            return nil
        }
    }

    struct DBError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "bookon.sqlite")

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw DBError(message: msg)
        }
        db = handle
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
    }

    deinit { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        try queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(err)
                throw DBError(message: msg)
            }
        }
    }

    @discardableResult
    func run(_ sql: String, _ args: [Value] = []) throws -> Int {
        try queue.sync {
            let stmt = try prepare(sql, args)
            defer { sqlite3_finalize(stmt) }
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                throw DBError(message: String(cString: sqlite3_errmsg(db)))
            }
            return Int(sqlite3_changes(db))
        }
    }

    func query(_ sql: String, _ args: [Value] = []) throws -> [Row] {
        try queue.sync {
            let stmt = try prepare(sql, args)
            defer { sqlite3_finalize(stmt) }
            var rows: [Row] = []
            let count = sqlite3_column_count(stmt)
            let names = (0..<count).map { String(cString: sqlite3_column_name(stmt, $0)) }
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else {
                    throw DBError(message: String(cString: sqlite3_errmsg(db)))
                }
                var dict: [String: Value] = [:]
                for i in 0..<count {
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER: dict[names[Int(i)]] = .int(sqlite3_column_int64(stmt, i))
                    case SQLITE_FLOAT: dict[names[Int(i)]] = .real(sqlite3_column_double(stmt, i))
                    case SQLITE_TEXT: dict[names[Int(i)]] = .text(String(cString: sqlite3_column_text(stmt, i)))
                    default: dict[names[Int(i)]] = .null
                    }
                }
                rows.append(Row(values: dict))
            }
            return rows
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN;")
        do {
            try body()
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String, _ args: [Value]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw DBError(message: String(cString: sqlite3_errmsg(db)))
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case .text(let t): sqlite3_bind_text(s, idx, t, -1, transient)
            case .int(let n): sqlite3_bind_int64(s, idx, n)
            case .real(let d): sqlite3_bind_double(s, idx, d)
            case .null: sqlite3_bind_null(s, idx)
            }
        }
        return s
    }
}
