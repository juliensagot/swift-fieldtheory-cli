import Foundation

public enum SafariCookieError: Error, CustomStringConvertible {
    case invalidFormat(String)
    case missingCookie(String)
    case permissionDenied(String)

    public var description: String {
        switch self {
        case .invalidFormat(let msg): return "Invalid binary cookies format: \(msg)"
        case .missingCookie(let msg): return "Missing cookie: \(msg)"
        case .permissionDenied(let msg): return "Permission denied: \(msg)"
        }
    }
}

public struct ParsedCookie: Sendable {
    public let domain: String
    public let name: String
    public let path: String
    public let value: String
    public let flags: UInt32
    public let expirationDate: Date?
    public let creationDate: Date?

    public var isSecure: Bool { flags & 0x01 != 0 }
    public var isHTTPOnly: Bool { flags & 0x04 != 0 }
}

public struct CookieResult: Sendable {
    public let csrfToken: String
    public let cookieHeader: String
}

public enum SafariCookieParser {

    private static let magic: [UInt8] = [0x63, 0x6F, 0x6F, 0x6B] // "cook"
    private static let cocoaEpochOffset: TimeInterval = 978_307_200

    public static var defaultCookiesPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Modern macOS: Safari uses its sandboxed container
        let sandboxed = "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        if FileManager.default.fileExists(atPath: sandboxed) {
            return sandboxed
        }
        // Fallback: legacy path
        return "\(home)/Library/Cookies/Cookies.binarycookies"
    }

    // MARK: - Parse

    public static func parse(data: Data) throws -> [ParsedCookie] {
        guard data.count >= 8 else {
            throw SafariCookieError.invalidFormat("File too short")
        }

        // Validate magic
        let magicBytes = [UInt8](data[0..<4])
        guard magicBytes == magic else {
            throw SafariCookieError.invalidFormat("Invalid magic bytes, expected 'cook'")
        }

        let pageCount = data.readBigEndianUInt32(at: 4)
        guard data.count >= 8 + Int(pageCount) * 4 else {
            throw SafariCookieError.invalidFormat("File too short for page sizes")
        }

        // Read page sizes
        var pageSizes: [UInt32] = []
        for i in 0..<Int(pageCount) {
            let size = data.readBigEndianUInt32(at: 8 + i * 4)
            pageSizes.append(size)
        }

        // Parse pages
        var cookies: [ParsedCookie] = []
        var pageOffset = 8 + Int(pageCount) * 4

        for pageSize in pageSizes {
            let pageEnd = pageOffset + Int(pageSize)
            guard pageEnd <= data.count else {
                throw SafariCookieError.invalidFormat("Page extends beyond file")
            }
            let pageData = data[pageOffset..<pageEnd]
            let pageCookies = try parsePage(pageData)
            cookies.append(contentsOf: pageCookies)
            pageOffset = pageEnd
        }

        return cookies
    }

    public static func parse(path: String) throws -> [ParsedCookie] {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            throw SafariCookieError.permissionDenied(
                "Cannot read Safari cookies. Grant Full Disk Access to Terminal in System Settings > Privacy & Security > Full Disk Access."
            )
        }
        return try parse(data: data)
    }

    // MARK: - Extract X Cookies

    public static func extractXCookies(from data: Data) throws -> CookieResult {
        let allCookies = try parse(data: data)
        return try extractXCookies(from: allCookies)
    }

    public static func extractXCookies(fromPath path: String) throws -> CookieResult {
        let allCookies = try parse(path: path)
        return try extractXCookies(from: allCookies)
    }

    private static func extractXCookies(from cookies: [ParsedCookie]) throws -> CookieResult {
        let xDomains: Set<String> = [".x.com", ".twitter.com", "x.com", "twitter.com"]
        let xCookies = cookies.filter { xDomains.contains($0.domain) }

        guard let ct0 = xCookies.first(where: { $0.name == "ct0" }) else {
            throw SafariCookieError.missingCookie(
                "ct0 cookie not found for x.com. Make sure you're logged into X in Safari. " +
                "If using a CLI tool, ensure Full Disk Access is granted."
            )
        }

        let authToken = xCookies.first(where: { $0.name == "auth_token" })

        var parts = ["ct0=\(ct0.value)"]
        if let authToken {
            parts.append("auth_token=\(authToken.value)")
        }

        return CookieResult(
            csrfToken: ct0.value,
            cookieHeader: parts.joined(separator: "; ")
        )
    }

    // MARK: - Page Parsing

    private static func parsePage(_ pageData: Data.SubSequence) throws -> [ParsedCookie] {
        let base = pageData.startIndex

        guard pageData.count >= 12 else {
            throw SafariCookieError.invalidFormat("Page too short")
        }

        let cookieCount = readLittleEndianUInt32(pageData, at: base + 4)
        guard pageData.count >= 8 + Int(cookieCount) * 4 + 4 else {
            throw SafariCookieError.invalidFormat("Page too short for cookie offsets")
        }

        var offsets: [UInt32] = []
        for i in 0..<Int(cookieCount) {
            let offset = readLittleEndianUInt32(pageData, at: base + 8 + i * 4)
            offsets.append(offset)
        }

        var cookies: [ParsedCookie] = []
        for offset in offsets {
            let cookieStart = base + Int(offset)
            guard cookieStart + 56 <= pageData.endIndex else { continue }

            let cookie = try parseCookieRecord(pageData, at: cookieStart)
            cookies.append(cookie)
        }

        return cookies
    }

    private static func parseCookieRecord(_ data: Data.SubSequence, at offset: Int) throws -> ParsedCookie {
        // Cookie record layout:
        //  0: size (4, LE)
        //  4: unknown1 (4)
        //  8: flags (4, LE)
        // 12: unknown2 (4)
        // 16: URL/domain offset (4, LE)
        // 20: name offset (4, LE)
        // 24: path offset (4, LE)
        // 28: value offset (4, LE)
        // 32: comment (8)
        // 40: expiration (8, LE double, Cocoa epoch)
        // 48: creation (8, LE double, Cocoa epoch)
        let flags = readLittleEndianUInt32(data, at: offset + 8)
        let domainOffset = Int(readLittleEndianUInt32(data, at: offset + 16))
        let nameOffset = Int(readLittleEndianUInt32(data, at: offset + 20))
        let pathOffset = Int(readLittleEndianUInt32(data, at: offset + 24))
        let valueOffset = Int(readLittleEndianUInt32(data, at: offset + 28))

        let expiration = readLittleEndianDouble(data, at: offset + 40)
        let creation = readLittleEndianDouble(data, at: offset + 48)

        let domain = readNullTerminatedString(data, at: offset + domainOffset)
        let name = readNullTerminatedString(data, at: offset + nameOffset)
        let path = readNullTerminatedString(data, at: offset + pathOffset)
        let value = readNullTerminatedString(data, at: offset + valueOffset)

        let expirationDate = expiration > 0
            ? Date(timeIntervalSince1970: expiration + cocoaEpochOffset)
            : nil
        let creationDate = creation > 0
            ? Date(timeIntervalSince1970: creation + cocoaEpochOffset)
            : nil

        return ParsedCookie(
            domain: domain,
            name: name,
            path: path,
            value: value,
            flags: flags,
            expirationDate: expirationDate,
            creationDate: creationDate
        )
    }

    // MARK: - Binary Reading Helpers

    private static func readLittleEndianUInt32(_ data: Data.SubSequence, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { ptr in
            let relativeOffset = offset - data.startIndex
            return UInt32(littleEndian: ptr.loadUnaligned(fromByteOffset: relativeOffset, as: UInt32.self))
        }
    }

    private static func readLittleEndianDouble(_ data: Data.SubSequence, at offset: Int) -> Double {
        data.withUnsafeBytes { ptr in
            let relativeOffset = offset - data.startIndex
            return ptr.loadUnaligned(fromByteOffset: relativeOffset, as: Double.self)
        }
    }

    private static func readNullTerminatedString(_ data: Data.SubSequence, at offset: Int) -> String {
        guard offset >= data.startIndex && offset < data.endIndex else { return "" }
        var end = offset
        while end < data.endIndex && data[end] != 0 {
            end += 1
        }
        guard let str = String(data: data[offset..<end], encoding: .utf8) else {
            return ""
        }
        return str
    }
}

// MARK: - Data extension for big-endian reads

extension Data {
    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        withUnsafeBytes { ptr in
            UInt32(bigEndian: ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }
}
