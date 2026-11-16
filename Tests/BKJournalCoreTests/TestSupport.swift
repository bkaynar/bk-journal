import XCTest
@testable import BKJournalCore

/// Testler için geçici klasör, sabit saat dilimi ve yalıtılmış git yardımcıları.
enum Support {
    /// İstanbul (UTC+3, yaz saati yok): yerel gün sınırlarının UTC'den farklı olduğunu sınamak için.
    static var istanbul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    static let me = (name: "Deneme Kullanıcı", email: "ben@ornek.dev")
    static let other = (name: "Başka Biri", email: "baska@ornek.dev")
    static let identity = Identity(emails: [me.email], names: [me.name])

    /// Kullanıcının gerçek git ayarları testleri etkilemesin.
    static let gitEnvironment = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]

    static var collector: GitCollector {
        var collector = GitCollector()
        collector.extraEnvironment = gitEnvironment
        return collector
    }

    static func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("bkjournal-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.resolvingSymlinksInPath()
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @discardableResult
    static func git(_ arguments: [String], in directory: URL, date: String? = nil,
                    author: (name: String, email: String) = me, file: StaticString = #filePath, line: UInt = #line) -> String {
        var env = gitEnvironment
        if let date {
            env["GIT_AUTHOR_DATE"] = date
            env["GIT_COMMITTER_DATE"] = date
        }
        let base = ["-c", "user.name=\(author.name)", "-c", "user.email=\(author.email)", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main"]
        let out = Shell.run("/usr/bin/git", base + arguments, cwd: directory, environment: env, timeout: 30)
        XCTAssertTrue(out.succeeded, "git \(arguments.joined(separator: " ")) başarısız: \(out.stderr)", file: file, line: line)
        return out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func initRepo(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        git(["init", "-q", "-b", "main"], in: url)
    }

    /// Dosyayı yazar ve commit eder; commit hash'ini döndürür.
    @discardableResult
    static func commit(_ repo: URL, file: String, content: String, message: String, date: String,
                       author: (name: String, email: String) = me) throws -> String {
        try write(content, to: repo.appendingPathComponent(file))
        git(["add", "-A"], in: repo)
        git(["commit", "-q", "-m", message], in: repo, date: date, author: author)
        return git(["rev-parse", "HEAD"], in: repo)
    }

    static func day(_ text: String) -> LocalDay { LocalDay(string: text)! }

    static func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Türkçe karakterli klasörleri, şablonu ve proje notları olan sahte kasa.
    static func makeVault(in base: URL, format: String = "YYYY-MM-DD", template: String? = "# {{title}}\n\nTarih: {{date}}\n") throws -> URL {
        let vault = base.appendingPathComponent("Kasa Örneği")
        let json = """
        {"format":"\(format)","folder":"Günlükler","template":"30 Kaynaklar/Şablonlar/Günlük Not Şablonu"}
        """
        try write(json, to: vault.appendingPathComponent(".obsidian/daily-notes.json"))
        if let template {
            try write(template, to: vault.appendingPathComponent("30 Kaynaklar/Şablonlar/Günlük Not Şablonu.md"))
        }
        try write("x", to: vault.appendingPathComponent("10 Projeler/Trafik360/Eksikler.md"))
        try write("x", to: vault.appendingPathComponent("10 Projeler/aytim/Aytim.md"))
        try write("x", to: vault.appendingPathComponent("10 Projeler/bio.re/Admin.md"))
        try write("x", to: vault.appendingPathComponent("10 Projeler/İşletim Sistemleri/Vize.md"))
        try write("x", to: vault.appendingPathComponent("10 Projeler/Başlıksız.md"))
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Günlükler"), withIntermediateDirectories: true)
        return vault
    }
}
