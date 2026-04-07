import ArgumentParser
import FieldTheory

extension FT {
    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print data directory path."
        )

        func run() throws {
            print(Paths().dataDir)
        }
    }
}
