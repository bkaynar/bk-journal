import XCTest
@testable import BKJournalCore

/// Sahte kasa ve geçici depolarla uçtan uca yazma testleri.
final class JournalTests: XCTestCase {
    var base: URL!
    var vaultURL: URL!
    var repoRoot: URL!
    var stateURL: URL!
    let calendar = Support.istanbul

    override func setUpWithError() throws {
        base = try Support.makeTempDir()
        vaultURL = try Support.makeVault(in: base, template: "---\ndate: {{date}}\n---\n\n# 📅 {{date}} - Günlük\n\n## 📝 Notlar\n- \n")
        repoRoot = base.appendingPathComponent("Kod Deposu")
        stateURL = base.appendingPathComponent("veri/state.json")

        let trafik = repoRoot.appendingPathComponent("trafik360")
        try Support.initRepo(trafik)
        try Support.commit(trafik, file: "a", content: "1\n2\n", message: "Giriş ekranı eklendi", date: "2026-11-10T09:05:00+03:00")
        try Support.commit(trafik, file: "a", content: "1\n3\n", message: "Şifre doğrulaması düzeltildi", date: "2026-11-10T14:30:00+03:00")
        try Support.commit(trafik, file: "b", content: "x\n", message: "Pazar çalışması", date: "2026-11-15T20:00:00+03:00")
        try Support.commit(trafik, file: "c", content: "x\n", message: "Bugünün işi", date: "2026-11-16T10:00:00+03:00")
        let other = repoRoot.appendingPathComponent("araçlar/bk-clean")
        try Support.initRepo(other)
        try Support.commit(other, file: "a", content: "1\n", message: "Tarama hızlandırıldı", date: "2026-11-10T11:00:00+03:00")
        try Support.commit(other, file: "a", content: "2\n", message: "Başkasının işi", date: "2026-11-10T12:00:00+03:00", author: Support.other)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func journal(now: String = "2026-11-16T20:30:00Z") throws -> Journal {   // İstanbul 23:30
        var config = Config()
        config.roots = [repoRoot.path]
        config.vault = vaultURL.path
        return try Journal(config: config, calendar: calendar, now: Support.date(now), collector: Support.collector, identity: Support.identity)
    }

    private func note(_ name: String) -> URL { vaultURL.appendingPathComponent("Günlükler/\(name).md") }
    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    /// Kasadaki bütün dosyaların göreli yolları (gizli olanlar dahil).
    private func vaultFiles() -> Set<String> {
        let enumerator = FileManager.default.enumerator(at: vaultURL, includingPropertiesForKeys: [.isRegularFileKey])!
        var result = Set<String>()
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            result.insert(String(url.resolvingSymlinksInPath().path.dropFirst(vaultURL.path.count + 1)))
        }
        return result
    }

    func testExistingNoteOnlyBlockChanges() throws {
        let above = "---\ntags:\n  - günlük\n---\n# Salı\r\n\nSabah: çay, ğüşiöç İIı  \n\n"
        let below = "\n\n## Akşam değerlendirmesi\n- [ ] yarın: sunum\nson satır"
        let url = note("2026-11-10")
        try Support.write(above + MarkerBlock.start + "\neski özet\n" + MarkerBlock.end + below, to: url)
        let before = vaultFiles()

        let journal = try journal()
        let report = try journal.planDay(Support.day("2026-11-10"))
        XCTAssertEqual(report.plan.outcome, .updated)
        XCTAssertEqual(report.commitCount, 3)
        try NoteWriter.commit(report.plan)

        let expectedBlock = """
        <!-- bk-journal:start -->
        ## Çalışma Özeti

        **3 commit, 2 proje, +4 / −1 satır**

        ### bk-clean
        - 11:00 Tarama hızlandırıldı · `main` (+1/−0)

        ### [[10 Projeler/Trafik360/Trafik360|Trafik360]]
        - 09:05 Giriş ekranı eklendi · `main` (+2/−0)
        - 14:30 Şifre doğrulaması düzeltildi · `main` (+1/−1)
        <!-- bk-journal:end -->
        """
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data, Data((above + expectedBlock + below).utf8))
        XCTAssertEqual(vaultFiles(), before, "başka dosya oluşmamalı")

        // İkinci çalıştırma: içerik aynı, dosyaya dokunulmaz.
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        let again = try journal.planDay(Support.day("2026-11-10"))
        XCTAssertEqual(again.plan.outcome, .unchanged)
        try NoteWriter.commit(again.plan)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, old)
    }

    func testExistingNoteWithoutBlockGetsAppend() throws {
        let text = "# Salı\n\nKendi notlarım.\n- çay içildi"
        let url = note("2026-11-10")
        try Support.write(text, to: url)
        let journal = try journal()
        let report = try journal.planDay(Support.day("2026-11-10"))
        try NoteWriter.commit(report.plan)
        XCTAssertEqual(try read(url), text + "\n\n" + report.block + "\n")
    }

    func testNewNoteUsesCoreTemplate() throws {
        let journal = try journal()
        let report = try journal.planDay(Support.day("2026-11-10"))
        XCTAssertEqual(report.plan.outcome, .created)
        XCTAssertEqual(report.plan.template, .coreTemplate)
        XCTAssertFalse(FileManager.default.fileExists(atPath: note("2026-11-10").path), "plan (kuru çalıştırma) dosya oluşturmamalı")
        try NoteWriter.commit(report.plan)
        XCTAssertEqual(try read(note("2026-11-10")),
                       "---\ndate: 2026-11-10\n---\n\n# 📅 2026-11-10 - Günlük\n\n## 📝 Notlar\n- \n\n" + report.block + "\n")
    }

    func testNewNoteWithTemplaterTemplateIsMinimal() throws {
        try Support.write("# <% tp.date.now() %>\n<%* tR += 'x' %>\n", to: vaultURL.appendingPathComponent("30 Kaynaklar/Şablonlar/Günlük Not Şablonu.md"))
        try Support.write(#"{"trigger_on_file_creation": true}"#, to: vaultURL.appendingPathComponent(".obsidian/plugins/templater-obsidian/data.json"))
        let journal = try journal()
        let report = try journal.planDay(Support.day("2026-11-10"))
        XCTAssertEqual(report.plan.template, .templaterSkipped)
        try NoteWriter.commit(report.plan)
        let text = try read(note("2026-11-10"))
        XCTAssertEqual(text, "# 2026-11-10\n\n" + report.block + "\n")
        XCTAssertFalse(text.contains("<%"))
    }

    func testDayWithoutCommits() throws {
        let journal = try journal()
        let report = try journal.planDay(Support.day("2026-11-12"))
        XCTAssertEqual(report.commitCount, 0)
        XCTAssertTrue(report.block.contains("Bugün commit yok."))
    }

    func testTodayListsUncommittedAndPastDayKeepsItsSnapshot() throws {
        try Support.write("yarım iş\n", to: repoRoot.appendingPathComponent("trafik360/yarım.txt"))
        let journal = try journal()

        let today = try journal.planDay(journal.today)
        XCTAssertTrue(today.block.contains("- 10:00 Bugünün işi · `main` (+1/−0)"))
        XCTAssertTrue(today.block.hasSuffix("**Commit edilmemiş değişiklikler**\n- trafik360: 1 izlenmeyen dosya\n" + MarkerBlock.end))

        // Geçmiş gün: şu anki durum yazılmaz…
        let past = try journal.planDay(Support.day("2026-11-10"))
        XCTAssertFalse(past.block.contains("Commit edilmemiş"))
        // …ama o gün yazılmış kayıt korunur.
        let snapshot = "**Commit edilmemiş değişiklikler**\n- biore: 4 değişen dosya"
        try Support.write("not\n\n" + MarkerBlock.wrap("## Çalışma Özeti\n\nBugün commit yok.\n\n" + snapshot) + "\n", to: note("2026-11-10"))
        let rewritten = try journal.planDay(Support.day("2026-11-10"))
        XCTAssertTrue(rewritten.block.hasSuffix(snapshot + "\n" + MarkerBlock.end))
        XCTAssertTrue(rewritten.block.contains("Giriş ekranı eklendi"))
    }

    func testFutureDateIsRejected() throws {
        let journal = try journal()
        XCTAssertThrowsError(try journal.planDay(Support.day("2026-11-17"))) { error in
            XCTAssertEqual(error as? JournalError, .futureDate("2026-11-17"))
        }
    }

    func testNoReposThrows() throws {
        var config = Config()
        config.roots = [base.appendingPathComponent("boş klasör").path]
        config.vault = vaultURL.path
        XCTAssertThrowsError(try Journal(config: config, calendar: calendar, collector: Support.collector, identity: Support.identity)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Hiç git deposu bulunamadı"))
        }
    }

    func testExcludedRepoIsIgnored() throws {
        var config = Config()
        config.roots = [repoRoot.path]
        config.vault = vaultURL.path
        config.excludeRepos = ["BK-Clean"]
        let journal = try Journal(config: config, calendar: calendar, now: Support.date("2026-11-16T20:30:00Z"), collector: Support.collector, identity: Support.identity)
        XCTAssertEqual(try journal.planDay(Support.day("2026-11-10")).commitCount, 2)
    }

    func testWeeklyReportWriteAndRewrite() throws {
        let journal = try journal()
        let week = ISOWeek(containing: Support.day("2026-11-12"), calendar: calendar)
        let report = try journal.planWeek(week)
        XCTAssertEqual(report.plan.url.path, vaultURL.path + "/Günlükler/Haftalık/2026-W46.md")
        XCTAssertEqual(report.commitCount, 4)
        try NoteWriter.commit(report.plan)
        XCTAssertEqual(try read(report.plan.url), "# Haftalık Rapor 2026-W46\n\n" + report.block + "\n")
        XCTAssertTrue(report.block.contains("| 10.11 Salı | 3 | 2 | +4 | −1 |"))
        XCTAssertTrue(report.block.contains("| 15.11 Pazar | 1 | 1 | +1 | −0 |"))
        XCTAssertTrue(report.block.contains("- 10.11 Sal: Şifre doğrulaması düzeltildi"))
        XCTAssertFalse(report.block.contains("Bugünün işi"), "sonraki haftanın commit'i girmemeli")
        XCTAssertFalse(report.block.contains("Başkasının işi"))

        // Kullanıcı rapora kendi metnini ekler; yeniden yazımda korunur.
        let edited = "Staj defteri girişi\n\n" + (try read(report.plan.url)) + "\nDanışman notu: ğüşiöç\n"
        try Support.write(edited, to: report.plan.url)
        let again = try journal.planWeek(week)
        XCTAssertEqual(again.plan.outcome, .unchanged)
    }

    func testCatchUpBackfillsAndWritesFinishedWeek() throws {
        try State(lastSuccessfulDay: "2026-11-14", lastRunAt: nil).save(to: stateURL)
        let userText = "Cumartesi notlarım\n"
        try Support.write(userText, to: note("2026-11-14"))

        let journal = try journal()
        let report = try journal.catchUp(stateURL: stateURL, write: true)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertFalse(report.capped)
        XCTAssertEqual(report.days.map(\.label), ["2026-11-14", "2026-11-15", "2026-11-16"])
        XCTAssertEqual(report.weeks.map(\.label), ["2026-W46"])
        XCTAssertEqual(report.days.map(\.plan.outcome), [.updated, .created, .created])

        XCTAssertTrue(try read(note("2026-11-14")).hasPrefix(userText + "\n" + MarkerBlock.start))
        XCTAssertTrue(try read(note("2026-11-15")).contains("- 20:00 Pazar çalışması"))
        XCTAssertTrue(try read(note("2026-11-16")).contains("- 10:00 Bugünün işi"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("Günlükler/Haftalık/2026-W46.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("Günlükler/Haftalık/2026-W47.md").path))
        XCTAssertEqual(State.load(from: stateURL).lastSuccessfulDay, "2026-11-16")

        // Hemen ardından yeniden çalıştırma hiçbir not dosyasını değiştirmez.
        let second = try journal.catchUp(stateURL: stateURL, write: true)
        XCTAssertEqual(second.days.map(\.label), ["2026-11-16"])
        XCTAssertEqual(second.days.map(\.plan.outcome), [.unchanged])
        XCTAssertEqual(second.weeks.count, 0)
    }

    func testCatchUpDryRunWritesNothing() throws {
        let before = vaultFiles()
        let journal = try journal()
        let report = try journal.catchUp(stateURL: stateURL, write: false)
        XCTAssertEqual(report.days.map(\.label), ["2026-11-16"])
        XCTAssertEqual(vaultFiles(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testCatchUpIsCappedAndCorruptNoteBlocksStateUpdate() throws {
        try State(lastSuccessfulDay: "2026-10-01", lastRunAt: nil).save(to: stateURL)
        let corrupt = "yarım\n" + MarkerBlock.start + "\n"
        try Support.write(corrupt, to: note("2026-11-12"))

        let journal = try journal()
        let report = try journal.catchUp(stateURL: stateURL, write: true)
        XCTAssertTrue(report.capped)
        XCTAssertEqual(report.days.count, 6)
        XCTAssertEqual(report.failures.map(\.label), ["2026-11-12"])
        XCTAssertEqual(try read(note("2026-11-12")), corrupt, "bozuk nota dokunulmamalı")
        XCTAssertEqual(report.weeks.map(\.label), ["2026-W46"])
        XCTAssertEqual(State.load(from: stateURL).lastSuccessfulDay, "2026-10-01", "hata varsa durum ilerlememeli")
    }
}
