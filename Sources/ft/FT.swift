import ArgumentParser
import FieldTheory

@main
struct FT: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ft",
        abstract: "Field Theory — sync and search your X/Twitter bookmarks locally.",
        version: FieldTheory.version,
        subcommands: [
            Sync.self,
            Search.self,
            List.self,
            Show.self,
            Stats.self,
            Classify.self,
            Categories.self,
            Domains.self,
            FetchMedia.self,
            Index.self,
            Status.self,
            Path.self,
        ]
    )
}
