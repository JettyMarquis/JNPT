import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteValue: Equatable {
    case text(String)
    case int(Int64)
    case double(Double)
    case blob(Data)
    case null

    public var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    public var intValue: Int64? {
        if case .int(let i) = self { return i }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let d) = self { return d }
        return nil
    }

    public var blobValue: Data? {
        if case .blob(let d) = self { return d }
        return nil
    }
}

public enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case bindFailed(Int)
    case databaseClosed
    case integrityCheckFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .executionFailed(let msg): return "SQLite execution failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .bindFailed(let idx): return "SQLite bind failed at index \(idx)"
        case .databaseClosed: return "Database is closed"
        case .integrityCheckFailed(let detail): return "File failed integrity check: \(detail)"
        }
    }
}

public class SQLiteDatabase {
    private var db: OpaquePointer?

    public init(path: String) throws {
        var dbPointer: OpaquePointer?
        let result = sqlite3_open(path, &dbPointer)
        guard result == SQLITE_OK, let opened = dbPointer else {
            let msg = dbPointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(dbPointer)
            throw SQLiteError.openFailed(msg)
        }
        self.db = opened
        do {
            try checkIntegrity()
        } catch {
            close()
            throw error
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    /// Untrusted files (opened from disk) must pass this before any write (e.g. WAL mode)
    /// touches them, so a malformed file is never mutated before being judged safe.
    private func checkIntegrity() throws {
        let rows = try query("PRAGMA integrity_check;")
        let result = rows.first?["integrity_check"]?.textValue
        guard result == "ok" else {
            throw SQLiteError.integrityCheckFailed(result ?? "unknown")
        }
    }

    deinit {
        close()
    }

    public func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Execute

    public func execute(_ sql: String) throws {
        guard let db = db else { throw SQLiteError.databaseClosed }
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        if result != SQLITE_OK {
            let msg = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMsg)
            throw SQLiteError.executionFailed(msg)
        }
    }

    public func executeWithParams(_ sql: String, params: [SQLiteValue]) throws {
        guard let db = db else { throw SQLiteError.databaseClosed }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt: stmt!, params: params)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Query

    public func query(_ sql: String, params: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        guard let db = db else { throw SQLiteError.databaseClosed }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt: stmt!, params: params)

        var rows: [[String: SQLiteValue]] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                row[name] = extractValue(stmt: stmt!, column: i)
            }
            rows.append(row)
        }
        return rows
    }

    public func insertReturningRowId(_ sql: String, params: [SQLiteValue]) throws -> Int64 {
        guard let db = db else { throw SQLiteError.databaseClosed }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt: stmt!, params: params)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            throw SQLiteError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        return sqlite3_last_insert_rowid(db)
    }

    // MARK: - Transactions

    public func beginTransaction() throws { try execute("BEGIN TRANSACTION;") }
    public func commitTransaction() throws { try execute("COMMIT;") }
    public func rollbackTransaction() throws { try execute("ROLLBACK;") }

    public func inTransaction<T>(_ body: () throws -> T) throws -> T {
        try beginTransaction()
        do {
            let result = try body()
            try commitTransaction()
            return result
        } catch {
            try? rollbackTransaction()
            throw error
        }
    }

    // MARK: - Private

    private func bindParams(stmt: OpaquePointer, params: [SQLiteValue]) throws {
        for (index, param) in params.enumerated() {
            let i = Int32(index + 1)
            let rc: Int32
            switch param {
            case .text(let str):
                rc = str.withCString { cStr in
                    sqlite3_bind_text(stmt, i, cStr, -1, SQLITE_TRANSIENT)
                }
            case .int(let val):
                rc = sqlite3_bind_int64(stmt, i, val)
            case .double(let val):
                rc = sqlite3_bind_double(stmt, i, val)
            case .blob(let data):
                rc = data.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, i, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            case .null:
                rc = sqlite3_bind_null(stmt, i)
            }
            guard rc == SQLITE_OK else {
                throw SQLiteError.bindFailed(index + 1)
            }
        }
    }

    private func extractValue(stmt: OpaquePointer, column: Int32) -> SQLiteValue {
        switch sqlite3_column_type(stmt, column) {
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(stmt, column)))
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(stmt, column))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(stmt, column))
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(stmt, column) {
                let count = Int(sqlite3_column_bytes(stmt, column))
                return .blob(Data(bytes: bytes, count: count))
            }
            return .null
        default:
            return .null
        }
    }
}
