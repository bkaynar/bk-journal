import XCTest
@testable import BKJournalCore

final class VaultTests: XCTestCase {
    var base: URL!
    let calendar = Support.istanbul

    override func setUpWithError() throws { base = try Support.makeTempDir() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    func testMissingVaultThrowsTurkishError() {
        let missing = base.appendingPathComponent("yok")
        XCTAssertThrowsError(try Vault(root: missing)) { error in
            XCTAssertEqual(error as? JournalError, .vaultMissing(missing.path))
            XCTAssertTrue(error.localizedDescription.contains("Obsidian kasası bulunamadı"))
        }
    }

    func testDailyNotePathFromSettings() throws {
        let vault = try Vault(root: try Support.makeVault(in: base))
        let settings = vault.dailyNotesSettings()
        XCTAssertEqual(settings, DailyNotesSettings(format: "YYYY-MM-DD", folder: "Günlükler", template: "30 Kaynaklar/Şablonlar/Günlük Not Şablonu"))
        let url = try vault.dailyNoteURL(for: Support.day("2026-11-10"), settings: settings, calendar: calendar)
        XCTAssertEqual(url.path, vault.root.path + "/Günlükler/2026-11-10.md")
    }

    func testCustomFormatWithSubfolders() throws {
        let vault = try Vault(root: try Support.makeVault(in: base, format: "YYYY/MM/DD.MM.YYYY"))
        let url = try vault.dailyNoteURL(for: Support.day("2026-03-05"), settings: vault.dailyNotesSettings(), calendar: calendar)
        XCTAssertEqual(url.path, vault.root.path + "/Günlükler/2026/03/05.03.2026.md")
    }

    func testUnparseableFormatFallsBack() throws {
        let vault = try Vault(root: try Support.makeVault(in: base, format: "dddd, D MMMM YYYY"))
        let url = try vault.dailyNoteURL(for: Support.day("2026-03-05"), settings: vault.dailyNotesSettings(), calendar: calendar)
        XCTAssertEqual(url.lastPathComponent, "2026-03-05.md")
    }

    func testMissingSettingsFileUsesObsidianDefaults() throws {
        let root = base.appendingPathComponent("Boş Kasa")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let vault = try Vault(root: root)
        XCTAssertEqual(vault.dailyNotesSettings(), DailyNotesSettings())
        let url = try vault.dailyNoteURL(for: Support.day("2026-11-10"), settings: vault.dailyNotesSettings(), calendar: calendar)
        XCTAssertEqual(url.path, vault.root.path + "/2026-11-10.md")
        XCTAssertNil(vault.templateText(settings: vault.dailyNotesSettings()))
        XCTAssertFalse(vault.templaterTriggersOnCreation())
    }

    func testPathOutsideVaultIsRejected() throws {
        let vault = try Vault(root: try Support.makeVault(in: base))
        var settings = vault.dailyNotesSettings()
        settings.folder = "../dışarı"
        XCTAssertThrowsError(try vault.dailyNoteURL(for: Support.day("2026-11-10"), settings: settings, calendar: calendar))
    }

    func testWeeklyNotePath() throws {
        let vault = try Vault(root: try Support.makeVault(in: base))
        let week = ISOWeek(containing: Support.day("2026-11-10"), calendar: calendar)
        let settings = vault.dailyNotesSettings()
        XCTAssertEqual(try vault.weeklyNoteURL(for: week, settings: settings, weeklyFolder: "").path,
                       vault.root.path + "/Günlükler/Haftalık/2026-W46.md")
        XCTAssertEqual(try vault.weeklyNoteURL(for: week, settings: settings, weeklyFolder: "20 Alanlar/Staj/").path,
                       vault.root.path + "/20 Alanlar/Staj/2026-W46.md")
    }

    func testTemplaterTriggerSetting() throws {
        let root = try Support.makeVault(in: base)
        let vault = try Vault(root: root)
        XCTAssertFalse(vault.templaterTriggersOnCreation())
        let data = root.appendingPathComponent(".obsidian/plugins/templater-obsidian/data.json")
        try Support.write(#"{"trigger_on_file_creation": true, "templates_folder": "x"}"#, to: data)
        XCTAssertTrue(vault.templaterTriggersOnCreation())
        try Support.write(#"{"trigger_on_file_creation": false}"#, to: data)
        XCTAssertFalse(vault.templaterTriggersOnCreation())
    }

    // MARK: Şablon

    func testCorePlaceholdersAreSubstituted() {
        let template = "---\ndate: {{date}}\n---\n# 📅 {{date}} - {{title}}\nSaat {{time}}, {{date:DD.MM.YYYY}}, {{time:HH.mm}}, {{ DATE }}, {{bilinmeyen}}\n"
        let date = Support.day("2026-11-10").start(in: calendar)
        let now = Support.date("2026-11-16T20:45:00Z") // İstanbul 23:45
        let (text, decision) = Template.newNotePrefix(template: template, title: "2026-11-10", date: date, now: now, calendar: calendar)
        XCTAssertEqual(decision, .coreTemplate)
        XCTAssertEqual(text, "---\ndate: 2026-11-10\n---\n# 📅 2026-11-10 - 2026-11-10\nSaat 23:45, 10.11.2026, 23.45, 2026-11-10, {{bilinmeyen}}\n")
    }

    func testTemplaterTemplateIsNotCopied() {
        let template = "# <% tp.file.title %>\n<%* await tp.system.prompt('x') %>\n{{date}}\n"
        let (text, decision) = Template.newNotePrefix(template: template, title: "2026-11-10", date: Date(), now: Date(), calendar: calendar)
        XCTAssertEqual(decision, .templaterSkipped)
        XCTAssertEqual(text, "# 2026-11-10\n")
        XCTAssertFalse(text.contains("<%"))
    }

    func testMissingTemplateGivesMinimalNote() {
        let (text, decision) = Template.newNotePrefix(template: nil, title: "2026-11-10", date: Date(), now: Date(), calendar: calendar)
        XCTAssertEqual(decision, .noTemplate)
        XCTAssertEqual(text, "# 2026-11-10\n")
    }

    // MARK: Proje eşleme

    func testNormalize() {
        XCTAssertEqual(ProjectMatcher.normalize("Trafik360"), "trafik360")
        XCTAssertEqual(ProjectMatcher.normalize("bio.re"), "biore")
        XCTAssertEqual(ProjectMatcher.normalize("İşletim Sistemleri"), "isletimsistemleri")
        XCTAssertEqual(ProjectMatcher.normalize("isletim-sistemleri"), "isletimsistemleri")
        XCTAssertEqual(ProjectMatcher.normalize("Uşak Kampüs"), "usakkampus")
        XCTAssertEqual(ProjectMatcher.normalize("IŞIK_ÇÖĞ"), "isikcog")
        // Ayrışık (NFD) yazım da aynı sonucu verir.
        XCTAssertEqual(ProjectMatcher.normalize("Us\u{0327}ak Kampu\u{0308}s"), "usakkampus")
        XCTAssertEqual(ProjectMatcher.normalize("--- ..."), "")
    }

    func testProjectEntriesAndMatching() throws {
        let vault = try Vault(root: try Support.makeVault(in: base))
        let entries = vault.projectEntries(folder: "10 Projeler")
        XCTAssertEqual(Set(entries.map(\.name)), ["Trafik360", "aytim", "bio.re", "İşletim Sistemleri", "Başlıksız"])

        // Klasör notu olmayan klasör: klasörün içindeki aynı adlı nota bağlanır.
        XCTAssertEqual(ProjectMatcher.link(forRepo: "trafik360", entries: entries)?.wikiLink, "[[10 Projeler/Trafik360/Trafik360|Trafik360]]")
        XCTAssertEqual(ProjectMatcher.link(forRepo: "biore", entries: entries)?.wikiLink, "[[10 Projeler/bio.re/bio.re|bio.re]]")
        // Klasör notu olan klasör: var olan nota bağlanır (dosya adının yazımıyla).
        XCTAssertEqual(ProjectMatcher.link(forRepo: "AYTIM", entries: entries)?.wikiLink, "[[10 Projeler/aytim/Aytim|aytim]]")
        XCTAssertEqual(ProjectMatcher.link(forRepo: "isletim-sistemleri", entries: entries)?.display, "İşletim Sistemleri")
        // Doğrudan klasördeki not.
        XCTAssertEqual(ProjectMatcher.link(forRepo: "basliksiz", entries: entries)?.wikiLink, "[[10 Projeler/Başlıksız|Başlıksız]]")
        XCTAssertNil(ProjectMatcher.link(forRepo: "bk-clean", entries: entries))
        XCTAssertNil(ProjectMatcher.link(forRepo: "---", entries: entries))
    }

    func testProjectMapOverrides() throws {
        let vault = try Vault(root: try Support.makeVault(in: base))
        let entries = vault.projectEntries(folder: "10 Projeler")
        let map = ["trafik360-sirlar": "Trafik360", "biore": "", "socify": "20 Alanlar/Socify Notları.md", "Ahi-Socify-New": "Aytim"]
        XCTAssertEqual(ProjectMatcher.link(forRepo: "trafik360-sirlar", entries: entries, overrides: map)?.wikiLink, "[[10 Projeler/Trafik360/Trafik360|Trafik360]]")
        XCTAssertNil(ProjectMatcher.link(forRepo: "biore", entries: entries, overrides: map), "boş değer bağlantıyı kapatır")
        XCTAssertEqual(ProjectMatcher.link(forRepo: "socify", entries: entries, overrides: map)?.wikiLink, "[[20 Alanlar/Socify Notları|Socify Notları]]")
        // Anahtar normalleştirilerek de bulunur.
        XCTAssertEqual(ProjectMatcher.link(forRepo: "ahi_socify_new", entries: entries, overrides: map)?.display, "aytim")
    }

    func testMissingProjectsFolderGivesNoEntries() throws {
        let vault = try Vault(root: try Support.makeVault(in: base))
        XCTAssertEqual(vault.projectEntries(folder: "Olmayan Klasör"), [])
    }

    // MARK: Ayarlar

    func testConfigDefaultsForMissingKeys() throws {
        let url = base.appendingPathComponent("config.json")
        try Support.write(#"{"roots": ["~/kod"], "extraEmails": ["a@b.c"]}"#, to: url)
        let config = try Config.load(from: url)
        XCTAssertEqual(config.roots, ["~/kod"])
        XCTAssertEqual(config.extraEmails, ["a@b.c"])
        XCTAssertEqual(config.vault, "~/Documents/obsidian")
        XCTAssertEqual(config.scheduleTime, "23:30")
        XCTAssertEqual(config.projectsFolder, "10 Projeler")
        XCTAssertEqual(config.maxDepth, 3)
    }

    func testMissingConfigIsNotCreatedUnlessAsked() throws {
        let url = base.appendingPathComponent("veri/config.json")
        XCTAssertEqual(try Config.load(from: url), Config())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Config.load(from: url, createIfMissing: true), Config())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Config.load(from: url), Config())
    }

    func testBrokenConfigThrowsTurkishError() throws {
        let url = base.appendingPathComponent("config.json")
        try Support.write("{ roots: [", to: url)
        XCTAssertThrowsError(try Config.load(from: url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Ayar dosyası okunamadı"))
        }
        try Support.write(#"{"roots": "tek"}"#, to: url)
        XCTAssertThrowsError(try Config.load(from: url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("\"roots\" alanının türü yanlış"))
        }
    }

    func testStateRoundTrip() throws {
        let url = base.appendingPathComponent("veri/state.json")
        XCTAssertEqual(State.load(from: url), State())
        let state = State(lastSuccessfulDay: "2026-11-16", lastRunAt: Date(timeIntervalSince1970: 1_800_000_000))
        try state.save(to: url)
        XCTAssertEqual(State.load(from: url), state)
    }

    func testSchedulerPlist() throws {
        let text = Scheduler.plist(executable: "/Users/x/.local/bin/bkjournal", hour: 23, minute: 30, logPath: "/tmp/a&b.log")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, "local.bkjournal")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/Users/x/.local/bin/bkjournal", "tamamla"])
        XCTAssertEqual(plist["StartCalendarInterval"] as? [String: Int], ["Hour": 23, "Minute": 30])
        XCTAssertEqual(plist["StandardErrorPath"] as? String, "/tmp/a&b.log")
        XCTAssertNil(plist["RunAtLoad"])
    }
}
