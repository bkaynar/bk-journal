// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BKJournal",
    platforms: [.macOS(.v14)],
    targets: [
        // Commit toplama, not yazma ve zamanlayıcı mantığı.
        .target(name: "BKJournalCore"),
        // Komut satırı aracı.
        .executableTarget(name: "bkjournal", dependencies: ["BKJournalCore"]),
        .testTarget(name: "BKJournalCoreTests", dependencies: ["BKJournalCore"]),
    ],
    swiftLanguageModes: [.v5]
)
