import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String

    public var description: String { "SQLiteError(\(code)): \(message)" }
}

public enum SQLiteValue: Equatable, Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null
}

public final class SQLiteStatement {
    private var handle: OpaquePointer?
    private let db: OpaquePointer

    init(handle: OpaquePointer, db: OpaquePointer) {
        self.handle = handle
        self.db = db
    }

    deinit {
        finalize()
    }

    public func bind(_ values: [SQLiteValue]) throws {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (i, value) in values.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch value {
            case .integer(let v): rc = sqlite3_bind_int64(handle, idx, v)
            case .real(let v):    rc = sqlite3_bind_double(handle, idx, v)
            case .text(let v):    rc = sqlite3_bind_text(handle, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .blob(let v):
                rc = v.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(handle, idx, ptr.baseAddress, Int32(v.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case .null:           rc = sqlite3_bind_null(handle, idx)
            }
            guard rc == SQLITE_OK else {
                throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    @discardableResult
    public func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW:  return true
        case SQLITE_DONE: return false
        default:
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    public func reset() throws {
        let rc = sqlite3_reset(handle)
        guard rc == SQLITE_OK else {
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    public func columnCount() -> Int32 {
        sqlite3_column_count(handle)
    }

    public func columnValue(at index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(handle, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(handle, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(handle, index))
        case SQLITE_TEXT:
            let cString = sqlite3_column_text(handle, index)!
            return .text(String(cString: cString))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(handle, index))
            if count == 0 {
                return .blob(Data())
            }
            let ptr = sqlite3_column_blob(handle, index)!
            return .blob(Data(bytes: ptr, count: count))
        default:
            return .null
        }
    }

    public func finalize() {
        guard let h = handle else { return }
        sqlite3_finalize(h)
        handle = nil
    }
}

public final class SQLiteDatabase {
    private var db: OpaquePointer?

    public init(path: String) throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open(path, &handle)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw SQLiteError(code: rc, message: msg)
        }
        self.db = handle
    }

    deinit {
        close()
    }

    public func close() {
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    public func execute(_ sql: String, _ params: [SQLiteValue] = []) throws {
        let stmt = try prepare(sql)
        defer { stmt.finalize() }
        if !params.isEmpty {
            try stmt.bind(params)
        }
        try stmt.step()
    }

    public func query(_ sql: String, _ params: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        let stmt = try prepare(sql)
        defer { stmt.finalize() }
        if !params.isEmpty {
            try stmt.bind(params)
        }
        var rows: [[SQLiteValue]] = []
        while try stmt.step() {
            let colCount = stmt.columnCount()
            var row: [SQLiteValue] = []
            for i in 0..<colCount {
                row.append(stmt.columnValue(at: i))
            }
            rows.append(row)
        }
        return rows
    }

    public func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let db else {
            throw SQLiteError(code: -1, message: "Database is closed")
        }
        var handle: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &handle, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError(code: rc, message: msg)
        }
        return SQLiteStatement(handle: handle, db: db)
    }

    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
