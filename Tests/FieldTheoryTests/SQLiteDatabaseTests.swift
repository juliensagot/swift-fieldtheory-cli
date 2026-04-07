import Testing
import Foundation
@testable import FieldTheory

@Suite("SQLiteDatabase")
struct SQLiteDatabaseTests {

    // MARK: - Open / Close

    @Test func openInMemoryDatabase() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        db.close()
    }

    // MARK: - Execute DDL

    @Test func executeDDL() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")

        let rows = try db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='t'")
        #expect(rows.count == 1)
        #expect(rows[0][0] == .text("t"))
    }

    // MARK: - Bind Parameters

    @Test func executeWithBindParameters() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
        try db.execute(
            "INSERT INTO t VALUES (?, ?, ?)",
            [.integer(1), .text("hello"), .real(3.14)]
        )

        let rows = try db.query("SELECT id, name, score FROM t")
        #expect(rows.count == 1)
        #expect(rows[0][0] == .integer(1))
        #expect(rows[0][1] == .text("hello"))
        #expect(rows[0][2] == .real(3.14))
    }

    @Test func bindNull() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO t VALUES (?, ?)", [.integer(1), .null])

        let rows = try db.query("SELECT name FROM t")
        #expect(rows[0][0] == .null)
    }

    // MARK: - Query

    @Test func queryReturnsMultipleRows() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO t VALUES (1, 'alice')")
        try db.execute("INSERT INTO t VALUES (2, 'bob')")
        try db.execute("INSERT INTO t VALUES (3, 'carol')")

        let rows = try db.query("SELECT id, name FROM t ORDER BY id")
        #expect(rows.count == 3)
        #expect(rows[0][1] == .text("alice"))
        #expect(rows[1][1] == .text("bob"))
        #expect(rows[2][1] == .text("carol"))
    }

    @Test func queryWithParameters() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO t VALUES (1, 'alice')")
        try db.execute("INSERT INTO t VALUES (2, 'bob')")

        let rows = try db.query("SELECT name FROM t WHERE id = ?", [.integer(2)])
        #expect(rows.count == 1)
        #expect(rows[0][0] == .text("bob"))
    }

    // MARK: - Prepared Statements

    @Test func preparedStatement() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")

        let stmt = try db.prepare("INSERT INTO t VALUES (?, ?)")
        defer { stmt.finalize() }

        try stmt.bind([.integer(1), .text("alice")])
        try stmt.step()
        try stmt.reset()

        try stmt.bind([.integer(2), .text("bob")])
        try stmt.step()
        try stmt.reset()

        let rows = try db.query("SELECT count(*) FROM t")
        #expect(rows[0][0] == .integer(2))
    }

    // MARK: - File-backed Database

    @Test func fileBackedPersistence() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("test.db").path

        // Write
        let db1 = try SQLiteDatabase(path: path)
        try db1.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT)")
        try db1.execute("INSERT INTO t VALUES (1, 'persisted')")
        db1.close()

        // Read back
        let db2 = try SQLiteDatabase(path: path)
        defer { db2.close() }
        let rows = try db2.query("SELECT val FROM t WHERE id = 1")
        #expect(rows[0][0] == .text("persisted"))
    }

    // MARK: - Transactions

    @Test func transactionCommits() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")

        try db.transaction {
            try db.execute("INSERT INTO t VALUES (1)")
            try db.execute("INSERT INTO t VALUES (2)")
        }

        let rows = try db.query("SELECT count(*) FROM t")
        #expect(rows[0][0] == .integer(2))
    }

    @Test func transactionRollsBackOnError() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
        try db.execute("INSERT INTO t VALUES (1)")

        do {
            try db.transaction {
                try db.execute("INSERT INTO t VALUES (2)")
                throw SQLiteError(code: -1, message: "simulated failure")
            }
        } catch {
            // expected
        }

        let rows = try db.query("SELECT count(*) FROM t")
        #expect(rows[0][0] == .integer(1))
    }

    // MARK: - FTS5

    @Test func fts5SearchWorks() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("""
            CREATE VIRTUAL TABLE docs USING fts5(title, body, tokenize='porter unicode61')
        """)
        try db.execute(
            "INSERT INTO docs (title, body) VALUES (?, ?)",
            [.text("Swift Programming"), .text("Swift is a powerful language for Apple platforms")]
        )
        try db.execute(
            "INSERT INTO docs (title, body) VALUES (?, ?)",
            [.text("Rust Programming"), .text("Rust is a systems programming language")]
        )

        let rows = try db.query(
            "SELECT title FROM docs WHERE docs MATCH ? ORDER BY rank",
            [.text("swift")]
        )
        #expect(rows.count == 1)
        #expect(rows[0][0] == .text("Swift Programming"))
    }

    // MARK: - Error Handling

    @Test func malformedSQLThrows() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        #expect(throws: SQLiteError.self) {
            try db.execute("NOT VALID SQL")
        }
    }

    @Test func sqliteErrorContainsMessage() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        do {
            try db.execute("SELECT * FROM nonexistent_table")
            Issue.record("Expected SQLiteError")
        } catch let error as SQLiteError {
            #expect(error.message.contains("nonexistent_table") || error.message.contains("no such table"))
        }
    }

    // MARK: - Blob

    @Test func blobRoundTrip() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE blobs (id INTEGER PRIMARY KEY, data BLOB)")

        let original = Data([0x00, 0xFF, 0x42, 0xDE, 0xAD, 0xBE, 0xEF])
        try db.execute("INSERT INTO blobs VALUES (?, ?)", [.integer(1), .blob(original)])

        let rows = try db.query("SELECT data FROM blobs WHERE id = 1")
        #expect(rows[0][0] == .blob(original))
    }

    @Test func emptyBlobRoundTrip() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE blobs (id INTEGER PRIMARY KEY, data BLOB)")
        try db.execute("INSERT INTO blobs VALUES (?, ?)", [.integer(1), .blob(Data())])

        let rows = try db.query("SELECT data FROM blobs WHERE id = 1")
        #expect(rows[0][0] == .blob(Data()))
    }
}
