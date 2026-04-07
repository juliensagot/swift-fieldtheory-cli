import Testing
import Foundation
@testable import FieldTheory

@Suite("SafariCookies")
struct SafariCookiesTests {

    // MARK: - Helpers

    /// Build a minimal valid binarycookies file in memory.
    private func buildBinaryCookies(cookies: [(domain: String, name: String, path: String, value: String, flags: UInt32)]) -> Data {
        // Build cookie records first
        var cookieRecords: [Data] = []
        for cookie in cookies {
            cookieRecords.append(buildCookieRecord(
                domain: cookie.domain, name: cookie.name,
                path: cookie.path, value: cookie.value, flags: cookie.flags
            ))
        }

        // Build the single page containing all cookies
        let pageData = buildPage(cookieRecords: cookieRecords)

        // Build file
        var data = Data()
        // Magic: "cook"
        data.append(contentsOf: [0x63, 0x6F, 0x6F, 0x6B])
        // Page count: 1 (big-endian)
        data.appendBigEndianUInt32(1)
        // Page sizes (big-endian)
        data.appendBigEndianUInt32(UInt32(pageData.count))
        // Page data
        data.append(pageData)
        // Checksum placeholder (not validated by our parser)
        data.appendLittleEndianUInt32(0)

        return data
    }

    private func buildPage(cookieRecords: [Data]) -> Data {
        var page = Data()
        // Page header
        page.appendLittleEndianUInt32(0x00000100)
        // Cookie count
        page.appendLittleEndianUInt32(UInt32(cookieRecords.count))

        // Calculate offsets: after header(4) + count(4) + offsets(4*count) + end_header(4)
        let headerSize = 4 + 4 + (4 * cookieRecords.count) + 4
        var offset = headerSize
        var offsets: [UInt32] = []
        for record in cookieRecords {
            offsets.append(UInt32(offset))
            offset += record.count
        }

        // Write offsets
        for o in offsets {
            page.appendLittleEndianUInt32(o)
        }
        // End of offsets marker
        page.appendLittleEndianUInt32(0x00000000)

        // Write cookie records
        for record in cookieRecords {
            page.append(record)
        }

        return page
    }

    private func buildCookieRecord(domain: String, name: String, path: String, value: String, flags: UInt32) -> Data {
        // String data (null-terminated)
        let domainBytes = Data(domain.utf8) + Data([0x00])
        let nameBytes = Data(name.utf8) + Data([0x00])
        let pathBytes = Data(path.utf8) + Data([0x00])
        let valueBytes = Data(value.utf8) + Data([0x00])

        // Fixed header: size(4) + unknown1(4) + flags(4) + unknown2(4) +
        //   4 string offsets(16) + comment(8) + expiration(8) + creation(8) = 56
        let fixedHeaderSize = 56
        let domainOffset = fixedHeaderSize
        let nameOffset = domainOffset + domainBytes.count
        let pathOffset = nameOffset + nameBytes.count
        let valueOffset = pathOffset + pathBytes.count
        let totalSize = valueOffset + valueBytes.count

        var record = Data()
        // Cookie size
        record.appendLittleEndianUInt32(UInt32(totalSize))
        // Unknown1
        record.appendLittleEndianUInt32(0)
        // Flags
        record.appendLittleEndianUInt32(flags)
        // Unknown2
        record.appendLittleEndianUInt32(0)
        // String offsets (relative to record start)
        record.appendLittleEndianUInt32(UInt32(domainOffset))
        record.appendLittleEndianUInt32(UInt32(nameOffset))
        record.appendLittleEndianUInt32(UInt32(pathOffset))
        record.appendLittleEndianUInt32(UInt32(valueOffset))
        // Comment (8 bytes unused)
        record.append(Data(repeating: 0, count: 8))
        // Expiration: Cocoa epoch for 2025-01-01 = 757382400.0
        var expiration: Double = 757382400.0
        record.append(Data(bytes: &expiration, count: 8))
        // Creation: Cocoa epoch for 2024-01-01 = 725846400.0
        var creation: Double = 725846400.0
        record.append(Data(bytes: &creation, count: 8))
        // Strings
        record.append(domainBytes)
        record.append(nameBytes)
        record.append(pathBytes)
        record.append(valueBytes)

        return record
    }

    // MARK: - Magic Bytes

    @Test func validMagicBytes() throws {
        let data = buildBinaryCookies(cookies: [
            (domain: ".example.com", name: "test", path: "/", value: "val", flags: 0)
        ])
        let cookies = try SafariCookieParser.parse(data: data)
        #expect(!cookies.isEmpty)
    }

    @Test func invalidMagicBytesThrows() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00, 0x00])
        #expect(throws: SafariCookieError.self) {
            try SafariCookieParser.parse(data: data)
        }
    }

    @Test func tooShortDataThrows() {
        let data = Data([0x63, 0x6F])
        #expect(throws: SafariCookieError.self) {
            try SafariCookieParser.parse(data: data)
        }
    }

    // MARK: - Cookie Parsing

    @Test func parseSingleCookie() throws {
        let data = buildBinaryCookies(cookies: [
            (domain: ".x.com", name: "ct0", path: "/", value: "abc123csrf", flags: 0x05) // secure + httpOnly
        ])

        let cookies = try SafariCookieParser.parse(data: data)
        #expect(cookies.count == 1)
        #expect(cookies[0].domain == ".x.com")
        #expect(cookies[0].name == "ct0")
        #expect(cookies[0].value == "abc123csrf")
        #expect(cookies[0].path == "/")
    }

    @Test func parseMultipleCookies() throws {
        let data = buildBinaryCookies(cookies: [
            (domain: ".x.com", name: "ct0", path: "/", value: "csrf_token_val", flags: 0x05),
            (domain: ".x.com", name: "auth_token", path: "/", value: "auth_token_val", flags: 0x05),
            (domain: ".example.com", name: "session", path: "/", value: "sess_val", flags: 0x01),
        ])

        let cookies = try SafariCookieParser.parse(data: data)
        #expect(cookies.count == 3)
    }

    // MARK: - Cookie Flags

    @Test func cookieFlags() throws {
        let data = buildBinaryCookies(cookies: [
            (domain: ".example.com", name: "secure_only", path: "/", value: "v", flags: 0x01),
            (domain: ".example.com", name: "httponly_only", path: "/", value: "v", flags: 0x04),
            (domain: ".example.com", name: "both", path: "/", value: "v", flags: 0x05),
            (domain: ".example.com", name: "none", path: "/", value: "v", flags: 0x00),
        ])

        let cookies = try SafariCookieParser.parse(data: data)
        #expect(cookies[0].isSecure == true)
        #expect(cookies[0].isHTTPOnly == false)
        #expect(cookies[1].isSecure == false)
        #expect(cookies[1].isHTTPOnly == true)
        #expect(cookies[2].isSecure == true)
        #expect(cookies[2].isHTTPOnly == true)
        #expect(cookies[3].isSecure == false)
        #expect(cookies[3].isHTTPOnly == false)
    }

    // MARK: - Cocoa Epoch

    @Test func cocoaEpochConversion() {
        // Cocoa epoch is Jan 1, 2001 00:00:00 UTC
        // Unix epoch offset: 978307200 seconds
        let cocoaTimestamp: Double = 757382400.0 // 2025-01-01 in Cocoa epoch
        let unixTimestamp = cocoaTimestamp + 978_307_200
        let date = Date(timeIntervalSince1970: unixTimestamp)

        let formatter = ISO8601DateFormatter()
        let str = formatter.string(from: date)
        #expect(str.hasPrefix("2025-01-01"))
    }

    // MARK: - X Cookie Extraction

    @Test func extractXCookies() throws {
        let data = buildBinaryCookies(cookies: [
            (domain: ".x.com", name: "ct0", path: "/", value: "my_csrf_token", flags: 0x05),
            (domain: ".x.com", name: "auth_token", path: "/", value: "my_auth_token", flags: 0x05),
            (domain: ".other.com", name: "unrelated", path: "/", value: "ignore", flags: 0x00),
        ])

        let result = try SafariCookieParser.extractXCookies(from: data)
        #expect(result.csrfToken == "my_csrf_token")
        #expect(result.cookieHeader.contains("ct0=my_csrf_token"))
        #expect(result.cookieHeader.contains("auth_token=my_auth_token"))
    }

    @Test func extractXCookiesFromTwitterDomain() throws {
        let data = buildBinaryCookies(cookies: [
            (domain: ".twitter.com", name: "ct0", path: "/", value: "twitter_csrf", flags: 0x05),
            (domain: ".twitter.com", name: "auth_token", path: "/", value: "twitter_auth", flags: 0x05),
        ])

        let result = try SafariCookieParser.extractXCookies(from: data)
        #expect(result.csrfToken == "twitter_csrf")
    }

    @Test func missingCsrfTokenThrows() {
        let data = buildBinaryCookies(cookies: [
            (domain: ".x.com", name: "auth_token", path: "/", value: "val", flags: 0x05),
        ])

        #expect(throws: SafariCookieError.self) {
            try SafariCookieParser.extractXCookies(from: data)
        }
    }

    // MARK: - Default Path

    @Test func defaultPath() {
        let path = SafariCookieParser.defaultCookiesPath
        #expect(path.hasSuffix("Cookies.binarycookies"))
    }
}

// MARK: - Data helpers for test fixture building

private extension Data {
    mutating func appendBigEndianUInt32(_ value: UInt32) {
        var v = value.bigEndian
        append(Data(bytes: &v, count: 4))
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
