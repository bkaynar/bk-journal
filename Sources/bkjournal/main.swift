import Foundation
import BKJournalCore

// BK Journal: günün git commit'lerini Obsidian günlük notuna yazar.

let usage = """
BK Journal — günlük git çalışmalarını Obsidian günlük notuna yazar.

Kullanım:
  bkjournal yaz [--tarih YYYY-MM-DD] [--kuru]     Bir günün özetini günlük nota yazar (varsayılan: bugün)
  bkjournal hafta [--tarih YYYY-MM-DD] [--kuru]   O günü içeren haftanın (Pzt–Paz) raporunu yazar
  bkjournal pano [--kuru]                         Grafikli çalışma panosunu (son 30 gün) günceller
  bkjournal tamamla [--kuru]                      Son çalışmadan bu yana eksik günleri (en fazla 7) tamamlar
  bkjournal kur                                   Her gün otomatik çalışacak zamanlayıcıyı kurar
  bkjournal kaldir                                Zamanlayıcıyı kaldırır
  bkjournal durum                                 Ayarları, kasayı, son çalışmayı ve zamanlayıcıyı gösterir

Seçenekler:
  --tarih YYYY-MM-DD   İşlenecek gün
  --kuru               Hiçbir şey yazmaz; bloğu ve hedef dosyayı gösterir

Ayarlar: \(Paths.abbreviate(Paths.configFile.path))
"""

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

struct Options {
    var day: LocalDay?
    var dry = false
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--kuru", "--dry-run":
            options.dry = true
        case "--tarih", "--date":
            index += 1
            guard index < arguments.count else { throw JournalError.usage("\(argument) seçeneğinden sonra bir tarih gerekli (YYYY-MM-DD).") }
            guard let day = LocalDay(string: arguments[index]) else { throw JournalError.invalidDate(arguments[index]) }
            options.day = day
        default:
            if argument.hasPrefix("--tarih=") || argument.hasPrefix("--date=") {
                let value = String(argument[argument.index(after: argument.firstIndex(of: "=")!)...])
                guard let day = LocalDay(string: value) else { throw JournalError.invalidDate(value) }
                options.day = day
            } else {
                throw JournalError.usage("Bilinmeyen seçenek: \(argument)\n\n\(usage)")
            }
        }
        index += 1
    }
    return options
}

func describe(_ report: NoteReport, dry: Bool) -> String {
    let path = Paths.abbreviate(report.plan.url.path)
    switch (report.plan.outcome, dry) {
    case (.unchanged, _): return "Değişiklik yok: \(path)"
    case (.created, false): return "Oluşturuldu: \(path) (\(report.commitCount) commit)"
    case (.updated, false): return "Güncellendi: \(path) (\(report.commitCount) commit)"
    case (.created, true): return "Oluşturulacaktı: \(path) (\(report.commitCount) commit)"
    case (.updated, true): return "Güncellenecekti: \(path) (\(report.commitCount) commit)"
    }
}

func templateNote(_ report: NoteReport, journal: Journal) -> String? {
    switch report.plan.template {
    case .notNeeded: return nil
    case .coreTemplate: return "Not yok; günlük not şablonu doldurularak oluşturulur."
    case .templaterSkipped: return "Not yok; şablonda Templater kodu olduğu için şablon kopyalanmaz, başlık ve bloktan oluşan sade bir not oluşturulur."
    case .noTemplate: return "Not yok; başlık ve bloktan oluşan sade bir not oluşturulur."
    }
}

/// `--kuru` çıktısı: blok, hedef dosya ve ne yapılacağı.
func printDry(_ report: NoteReport, journal: Journal) {
    print(report.block)
    print("")
    print("Hedef: \(Paths.abbreviate(report.plan.url.path))")
    if let note = templateNote(report, journal: journal) { print(note) }
    print(describe(report, dry: true))
    print("Kuru çalıştırma: hiçbir şey yazılmadı.")
}

func loadJournal(dry: Bool) throws -> Journal {
    // Kuru çalıştırma ayar dosyası bile oluşturmaz.
    let config = try Config.load(createIfMissing: !dry)
    return try Journal(config: config)
}

func run() throws -> Int32 {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard !arguments.isEmpty else {
        print(usage)
        return 0
    }
    let command = arguments.removeFirst()

    switch command {
    case "yaz", "write":
        let options = try parseOptions(arguments)
        let journal = try loadJournal(dry: options.dry)
        let report = try journal.planDay(options.day ?? journal.today)
        if options.dry {
            printDry(report, journal: journal)
        } else {
            try NoteWriter.commit(report.plan)
            print(describe(report, dry: false))
        }
        return 0

    case "hafta", "week":
        let options = try parseOptions(arguments)
        let journal = try loadJournal(dry: options.dry)
        let week = ISOWeek(containing: options.day ?? journal.today, calendar: journal.calendar)
        let report = try journal.planWeek(week)
        if options.dry {
            printDry(report, journal: journal)
        } else {
            try NoteWriter.commit(report.plan)
            print(describe(report, dry: false))
        }
        return 0

    case "pano", "dashboard":
        let options = try parseOptions(arguments)
        guard options.day == nil else { throw JournalError.usage("pano komutu --tarih almaz.") }
        let journal = try loadJournal(dry: options.dry)
        guard let report = try journal.planDashboard() else {
            print("Pano kapalı: config.json içinde \"dashboardNote\" boş.")
            return 0
        }
        if options.dry {
            printDry(report, journal: journal)
        } else {
            try NoteWriter.commit(report.plan)
            print(describe(report, dry: false))
        }
        return 0

    case "tamamla", "catchup":
        let options = try parseOptions(arguments)
        guard options.day == nil else { throw JournalError.usage("tamamla komutu --tarih almaz.") }
        let journal = try loadJournal(dry: options.dry)
        let report = try journal.catchUp(write: !options.dry)
        if report.capped {
            print("Son çalışmadan bu yana \(CatchUp.maxDays) günden fazla geçmiş; yalnızca son \(CatchUp.maxDays) gün işlendi.")
        }
        for item in report.days + report.weeks + [report.dashboard].compactMap({ $0 }) { print(describe(item, dry: options.dry)) }
        for failure in report.failures { printError("Hata (\(failure.label)): \(failure.message)") }
        if options.dry { print("Kuru çalıştırma: hiçbir şey yazılmadı.") }
        return report.failures.isEmpty ? 0 : 1

    case "kur", "install":
        guard arguments.isEmpty else { throw JournalError.usage("kur komutu seçenek almaz.") }
        let config = try Config.load(createIfMissing: true)
        _ = try Vault(root: config.vaultURL)
        let result = try Scheduler.install(config: config)
        print("Zamanlayıcı kuruldu: her gün \(config.scheduleTime) → \(Paths.abbreviate(result.executable)) tamamla")
        print("Dosya: \(Paths.abbreviate(Scheduler.plistURL.path))")
        print("Günlük kaydı: \(Paths.abbreviate(Paths.logFile.path))")
        if !result.installed {
            print("Uyarı: ~/.local/bin/bkjournal bulunamadı; zamanlayıcı şu anki kopyayı çalıştıracak. Kalıcı kurulum için `./build.sh --install` sonra yeniden `bkjournal kur`.")
        }
        print("Not: macOS ilk çalıştırmada Belgeler klasörüne erişim izni isteyebilir.")
        return 0

    case "kaldir", "kaldır", "uninstall":
        guard arguments.isEmpty else { throw JournalError.usage("kaldir komutu seçenek almaz.") }
        let removed = try Scheduler.uninstall()
        print(removed ? "Zamanlayıcı kaldırıldı: \(Paths.abbreviate(Scheduler.plistURL.path))" : "Zamanlayıcı zaten kurulu değil.")
        return 0

    case "durum", "status":
        guard arguments.isEmpty else { throw JournalError.usage("durum komutu seçenek almaz.") }
        return try status()

    case "yardim", "yardım", "help", "--help", "-h":
        print(usage)
        return 0

    default:
        throw JournalError.usage("Bilinmeyen komut: \(command)\n\n\(usage)")
    }
}

func status() throws -> Int32 {
    let fm = FileManager.default
    let configExists = fm.fileExists(atPath: Paths.configFile.path)
    let config = try Config.load(createIfMissing: false)
    let calendar = Journal.localCalendar

    print("Ayar dosyası:    \(Paths.abbreviate(Paths.configFile.path))\(configExists ? "" : " (yok, varsayılanlar geçerli)")")
    print("Depo kökleri:    \(config.roots.joined(separator: ", "))")
    if !config.extraEmails.isEmpty { print("Ek e-postalar:   \(config.extraEmails.joined(separator: ", "))") }
    if !config.extraNames.isEmpty { print("Ek adlar:        \(config.extraNames.joined(separator: ", "))") }
    if !config.projectMap.isEmpty {
        print("Proje eşlemesi:  \(config.projectMap.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value.isEmpty ? "(bağlantı yok)" : $0.value)" }.joined(separator: ", "))")
    }

    let collector = GitCollector()
    let identity = collector.globalIdentity()
    print("Yazar:           \(identity.name ?? "(ad yok)") <\(identity.email ?? "e-posta yok")>")
    let skip = GitCollector.defaultSkip.union(config.skipDirectories)
    let repos = collector.discoverRepos(roots: config.rootURLs, maxDepth: config.maxDepth, skip: skip)
    print("Bulunan depo:    \(repos.count)\(repos.isEmpty ? "" : " (" + repos.map(\.name).joined(separator: ", ") + ")")")

    var exitCode: Int32 = 0
    print("Kasa:            \(Paths.abbreviate(config.vaultURL.path))")
    do {
        let vault = try Vault(root: config.vaultURL)
        let settings = vault.dailyNotesSettings()
        let today = LocalDay(date: Date(), calendar: calendar)
        let daily = try vault.dailyNoteURL(for: today, settings: settings, calendar: calendar)
        let weekly = try vault.weeklyNoteURL(for: ISOWeek(containing: today, calendar: calendar), settings: settings, weeklyFolder: config.weeklyFolder)
        print("Günlük not:      \(Paths.abbreviate(daily.path)) (biçim: \(settings.format))")
        print("Haftalık rapor:  \(Paths.abbreviate(weekly.path))")
        let template: String
        if settings.template.isEmpty {
            template = "ayarlı değil"
        } else if let text = vault.templateText(settings: settings) {
            template = settings.template + (Template.containsTemplater(text) ? " (Templater kodu içeriyor; yeni notlarda kullanılmaz)" : " (yeni notlarda doldurulur)")
        } else {
            template = settings.template + " (dosya bulunamadı)"
        }
        print("Şablon:          \(template)")
        print("Templater:       yeni dosyada tetikleme \(vault.templaterTriggersOnCreation() ? "açık" : "kapalı")")
        print("Proje notları:   \(vault.projectEntries(folder: config.projectsFolder).count) kayıt (\(config.projectsFolder))")
    } catch {
        printError("Hata: \(error.localizedDescription)")
        exitCode = 1
    }

    let state = State.load()
    if let day = state.lastSuccessfulDay {
        var line = "Son çalışma:     \(day)"
        if let at = state.lastRunAt {
            line += " " + MomentFormat.formatOrFallback(at, pattern: "HH:mm", calendar: calendar, fallback: "HH:mm")
        }
        print(line)
    } else {
        print("Son çalışma:     henüz yok")
    }

    let plist = Scheduler.plistExists
    let loaded = Scheduler.isLoaded
    let schedulerState: String
    switch (plist, loaded) {
    case (true, true): schedulerState = "kurulu ve yüklü"
    case (true, false): schedulerState = "dosya var ama yüklü değil (`bkjournal kur` ile yeniden kurun)"
    case (false, true): schedulerState = "yüklü ama dosyası yok (`bkjournal kaldir` ile temizleyin)"
    case (false, false): schedulerState = "kurulu değil"
    }
    print("Zamanlayıcı:     \(schedulerState) (saat \(config.scheduleTime), \(Paths.abbreviate(Scheduler.plistURL.path)))")
    return exitCode
}

do {
    exit(try run())
} catch {
    printError("Hata: \(error.localizedDescription)")
    exit(1)
}
