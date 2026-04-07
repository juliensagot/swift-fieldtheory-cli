import Testing
import Foundation
@testable import FieldTheory

@Suite("SnowflakeTimestamp")
struct SnowflakeTimestampTests {

    @Test func knownSnowflakeConverts() {
        // Twitter snowflake epoch: 1288834974657 ms
        // ID 1867614419191283712 → known date around Dec 13, 2024
        let iso = SnowflakeTimestamp.toISO("1867614419191283712")
        #expect(iso != nil)
        #expect(iso!.hasPrefix("2024-12-13"))
    }

    @Test func snowflakeEpochItself() {
        // ID 0 should map to the Twitter epoch: Nov 4, 2010
        // Actually, ID 0 means (0 >> 22) + epoch = epoch
        let iso = SnowflakeTimestamp.toISO("0")
        #expect(iso != nil)
        #expect(iso!.hasPrefix("2010-11-04"))
    }

    @Test func emptyStringReturnsNil() {
        #expect(SnowflakeTimestamp.toISO("") == nil)
    }

    @Test func nonNumericReturnsNil() {
        #expect(SnowflakeTimestamp.toISO("not_a_number") == nil)
    }

    @Test func smallIdStillWorks() {
        // Small but valid snowflake
        let iso = SnowflakeTimestamp.toISO("4194304") // 1 << 22
        #expect(iso != nil)
    }
}
