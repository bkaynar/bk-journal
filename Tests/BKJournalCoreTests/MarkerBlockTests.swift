import XCTest
@testable import BKJournalCore

final class MarkerBlockTests: XCTestCase {
    let block = MarkerBlock.wrap("## Çalışma Özeti\n\nBugün commit yok.")

    func testReplaceKeepsOutsideBytesIdentical() throws {
        // Üstte ve altta kullanıcı metni; CRLF, sekme, sondaki boşluklar ve ayrışık (NFD) Türkçe harfler dahil.
        let above = "# Günlük\r\n\r\nSabah notları: çğıöşü İ  \r\n\tgirintili satır\r\n" + "s\u{0327}u\u{0308}" + "\n\n"
        let below = "\n\n## Akşam\n- [ ] yapılacak iş   \nson satır, satır sonu yok"
        let old = MarkerBlock.start + "\neski içerik\n" + MarkerBlock.end
        let original = Data((above + old + below).utf8)

        let result = try MarkerBlock.apply(block: block, to: original)

        let aboveBytes = Data(above.utf8), belowBytes = Data(below.utf8), blockBytes = Data(block.utf8)
        XCTAssertEqual(result.count, aboveBytes.count + blockBytes.count + belowBytes.count)
        XCTAssertEqual(Data(result.prefix(aboveBytes.count)), aboveBytes)
        XCTAssertEqual(Data(result.suffix(belowBytes.count)), belowBytes)
        XCTAssertEqual(Data(result.dropFirst(aboveBytes.count).dropLast(belowBytes.count)), blockBytes)
    }

    func testReplaceKeepsInvalidUTF8Outside() throws {
        // Geçersiz UTF-8 baytları bile aynen kalmalı.
        var original = Data([0xFF, 0xFE, 0x0A])
        original.append(Data((MarkerBlock.start + "x" + MarkerBlock.end).utf8))
        original.append(Data([0x0A, 0xC3]))
        let result = try MarkerBlock.apply(block: block, to: original)
        XCTAssertEqual(Data(result.prefix(3)), Data([0xFF, 0xFE, 0x0A]))
        XCTAssertEqual(Data(result.suffix(2)), Data([0x0A, 0xC3]))
    }

    func testOnlyFirstBlockIsReplaced() throws {
        let second = MarkerBlock.start + "\nikinci\n" + MarkerBlock.end
        let original = Data(("a\n" + MarkerBlock.start + "\nbir\n" + MarkerBlock.end + "\nb\n" + second + "\n").utf8)
        let result = String(decoding: try MarkerBlock.apply(block: block, to: original), as: UTF8.self)
        XCTAssertEqual(result, "a\n" + block + "\nb\n" + second + "\n")
    }

    func testAppendKeepsExistingBytesAsPrefix() throws {
        for text in ["Kullanıcı notu, satır sonu yok", "Kullanıcı notu\n", "Kullanıcı notu\n\n", "Satır\r\n"] {
            let original = Data(text.utf8)
            let result = try MarkerBlock.apply(block: block, to: original)
            XCTAssertEqual(Data(result.prefix(original.count)), original, "önek değişti: \(text.debugDescription)")
            let tail = String(decoding: result.dropFirst(original.count), as: UTF8.self)
            XCTAssertTrue(tail.hasSuffix(block + "\n"))
            // Blok öncesinde tam bir boş satır olur.
            XCTAssertTrue(String(decoding: result, as: UTF8.self).contains("\n\n" + MarkerBlock.start) ||
                          String(decoding: result, as: UTF8.self).contains("\r\n\n" + MarkerBlock.start))
        }
    }

    func testAppendToEmptyFile() throws {
        let result = try MarkerBlock.apply(block: block, to: Data())
        XCTAssertEqual(String(decoding: result, as: UTF8.self), block + "\n")
    }

    func testApplyingTwiceIsStable() throws {
        let once = try MarkerBlock.apply(block: block, to: Data("Not\n".utf8))
        let twice = try MarkerBlock.apply(block: block, to: once)
        XCTAssertEqual(once, twice)
    }

    func testStartWithoutEndThrowsAndTouchesNothing() {
        let original = Data(("metin\n" + MarkerBlock.start + "\nyarım kalmış\n").utf8)
        XCTAssertThrowsError(try MarkerBlock.apply(block: block, to: original, path: "/x.md")) { error in
            XCTAssertEqual(error as? JournalError, .markerCorrupt("/x.md"))
        }
    }

    func testExistingBlockExtraction() {
        let data = Data(("üst\n" + block + "\nalt").utf8)
        XCTAssertEqual(MarkerBlock.existingBlock(in: data), block)
        XCTAssertNil(MarkerBlock.existingBlock(in: Data("blok yok".utf8)))
    }
}

final class NoteWriterTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws { dir = try Support.makeTempDir() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func modificationDate(_ url: URL) throws -> Date {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }

    private func inode(_ url: URL) throws -> UInt64 {
        try XCTUnwrap((FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?.uint64Value)
    }

    func testIdenticalContentIsNotWritten() throws {
        let url = dir.appendingPathComponent("Günlükler/2026-11-10.md")
        let block = MarkerBlock.wrap("## Çalışma Özeti\n\nBugün commit yok.")
        try Support.write("Üst metin\n\n" + block + "\n\nAlt metin\n", to: url)
        // Eski bir değişiklik zamanı verilir; yazılırsa değişir.
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        let inodeBefore = try inode(url)

        let plan = try NoteWriter.plan(url: url, block: block) { XCTFail("şablon istenmemeli"); return ("", .noTemplate) }
        XCTAssertEqual(plan.outcome, .unchanged)
        try NoteWriter.commit(plan)

        XCTAssertEqual(try modificationDate(url), old)
        XCTAssertEqual(try inode(url), inodeBefore)
    }

    func testUpdateWritesAtomicallyAndLeavesNoTempFile() throws {
        let url = dir.appendingPathComponent("not.md")
        try Support.write("Üst\n" + MarkerBlock.wrap("eski") + "\nAlt\n", to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let inodeBefore = try inode(url)

        let block = MarkerBlock.wrap("yeni")
        let plan = try NoteWriter.plan(url: url, block: block) { ("", .noTemplate) }
        XCTAssertEqual(plan.outcome, .updated)
        try NoteWriter.commit(plan)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Üst\n" + block + "\nAlt\n")
        // rename ile değiştirildiği için dosya numarası farklıdır; izinler korunur.
        XCTAssertNotEqual(try inode(url), inodeBefore)
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["not.md"])
    }

    func testCreateMakesFoldersAndUsesPrefix() throws {
        let url = dir.appendingPathComponent("Günlükler/Haftalık/2026-W46.md")
        let block = MarkerBlock.wrap("içerik")
        let plan = try NoteWriter.plan(url: url, block: block) { ("# Başlık\n", .noTemplate) }
        XCTAssertEqual(plan.outcome, .created)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "plan diske yazmamalı")
        try NoteWriter.commit(plan)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Başlık\n\n" + block + "\n")
    }

    func testTemplateWithMarkersGetsBlockInPlace() throws {
        let url = dir.appendingPathComponent("yeni.md")
        let block = MarkerBlock.wrap("içerik")
        let prefix = "# Gün\n\n" + MarkerBlock.start + "\n" + MarkerBlock.end + "\n\n## Notlar\n"
        let plan = try NoteWriter.plan(url: url, block: block) { (prefix, .coreTemplate) }
        XCTAssertEqual(String(decoding: plan.data, as: UTF8.self), "# Gün\n\n" + block + "\n\n## Notlar\n")
    }

    func testCorruptNoteIsNotWritten() throws {
        let url = dir.appendingPathComponent("bozuk.md")
        let text = "metin\n" + MarkerBlock.start + "\n"
        try Support.write(text, to: url)
        XCTAssertThrowsError(try NoteWriter.plan(url: url, block: MarkerBlock.wrap("x")) { ("", .noTemplate) })
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
    }
}
