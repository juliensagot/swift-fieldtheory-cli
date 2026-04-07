import Testing
import Foundation
@testable import FieldTheory

@Suite("Paths")
struct PathsTests {

    // MARK: - Data Directory

    @Test func defaultDataDir() {
        let paths = Paths()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(paths.dataDir == "\(home)/.ft-bookmarks")
    }

    @Test func customBaseDir() {
        let paths = Paths(baseDir: "/tmp/custom-ft")
        #expect(paths.dataDir == "/tmp/custom-ft")
    }

    @Test func envOverride() {
        let paths = Paths(environment: ["FT_DATA_DIR": "/tmp/env-ft"])
        #expect(paths.dataDir == "/tmp/env-ft")
    }

    // MARK: - Sub-paths

    @Test func subPaths() {
        let paths = Paths(baseDir: "/data")
        #expect(paths.indexPath == "/data/bookmarks.db")
        #expect(paths.metaPath == "/data/bookmarks-meta.json")
        #expect(paths.backfillStatePath == "/data/bookmarks-backfill-state.json")
        #expect(paths.cachePath == "/data/bookmarks.jsonl")
    }

    // MARK: - ensureDataDir

    @Test func ensureDataDirCreatesDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ft-test-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let paths = Paths(baseDir: tmpDir)
        try paths.ensureDataDir()

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: tmpDir, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test func ensureDataDirIsIdempotent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ft-test-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let paths = Paths(baseDir: tmpDir)
        try paths.ensureDataDir()
        try paths.ensureDataDir() // should not throw
    }

    // MARK: - JSONL Read/Write

    @Test func jsonlWriteAndRead() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ft-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("test.jsonl").path

        let records = [
            BookmarkRecord(id: "1", tweetId: "1", url: "https://x.com/a/status/1", text: "First", syncedAt: "2024-01-01T00:00:00Z"),
            BookmarkRecord(id: "2", tweetId: "2", url: "https://x.com/b/status/2", text: "Second", syncedAt: "2024-01-02T00:00:00Z"),
        ]

        try FileUtilities.writeJSONLines(records, to: path)
        let loaded: [BookmarkRecord] = try FileUtilities.readJSONLines(from: path)

        #expect(loaded.count == 2)
        #expect(loaded[0].id == "1")
        #expect(loaded[1].id == "2")
    }

    @Test func jsonlReadNonexistentReturnsEmpty() throws {
        let loaded: [BookmarkRecord] = try FileUtilities.readJSONLines(from: "/tmp/nonexistent-\(UUID()).jsonl")
        #expect(loaded.isEmpty)
    }

    // MARK: - JSON Read/Write

    @Test func jsonWriteAndRead() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ft-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("meta.json").path
        let meta = BookmarkCacheMeta(schemaVersion: 5, totalBookmarks: 100)

        try FileUtilities.writeJSON(meta, to: path)
        let loaded: BookmarkCacheMeta = try FileUtilities.readJSON(from: path)

        #expect(loaded.schemaVersion == 5)
        #expect(loaded.totalBookmarks == 100)
    }
}
