import Testing
@testable import FieldTheory

@Suite("FieldTheory")
struct FieldTheoryTests {
    @Test func version() {
        #expect(FieldTheory.version == "1.0.0")
    }
}
