import Foundation

/// Veri klasörü ve içindeki dosyalar.
public enum Paths {
    /// `~/Library/Application Support/BKJournal`. Testlerde ve denemelerde
    /// `BKJOURNAL_DATA_DIR` ortam değişkeniyle başka bir klasöre yönlendirilebilir.
    public static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["BKJOURNAL_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BKJournal", isDirectory: true)
    }

    public static var configFile: URL { dataDirectory.appendingPathComponent("config.json") }
    public static var stateFile: URL { dataDirectory.appendingPathComponent("state.json") }
    public static var logFile: URL { dataDirectory.appendingPathComponent("bkjournal.log") }

    public static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    public static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// `config.json` dosyasından okunan ayarlar. Dosyada olmayan alanlar varsayılan değerleri alır.
public struct Config: Codable, Sendable, Equatable {
    /// Git depolarının aranacağı klasörler.
    public var roots: [String] = ["~/Documents/GitHub", "~/IdeaProjects"]
    /// Obsidian kasası.
    public var vault: String = "~/Documents/obsidian"
    /// `git config --global user.email` değerine ek olarak sizin sayılacak e-posta adresleri.
    public var extraEmails: [String] = []
    /// `git config --global user.name` değerine ek olarak sizin sayılacak yazar adları.
    public var extraNames: [String] = []
    /// Proje notlarının bulunduğu kasa klasörü.
    public var projectsFolder: String = "10 Projeler"
    /// Haftalık raporların yazılacağı kasa klasörü. Boşsa `<günlük not klasörü>/Haftalık` kullanılır.
    public var weeklyFolder: String = ""
    /// Depo adı → proje notu eşlemesi. Değer boşsa o depo için bağlantı verilmez.
    public var projectMap: [String: String] = [:]
    /// Zamanlayıcının `bkjournal tamamla` komutunu çalıştıracağı saat (SS:dd).
    public var scheduleTime: String = "23:30"
    /// Depo aramasının inebileceği en fazla klasör derinliği.
    public var maxDepth: Int = 3
    /// Varsayılanlara ek olarak içine girilmeyecek klasör adları.
    public var skipDirectories: [String] = []
    /// Özete alınmayacak depo adları.
    public var excludeRepos: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let d = Config()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? d.roots
        vault = try c.decodeIfPresent(String.self, forKey: .vault) ?? d.vault
        extraEmails = try c.decodeIfPresent([String].self, forKey: .extraEmails) ?? d.extraEmails
        extraNames = try c.decodeIfPresent([String].self, forKey: .extraNames) ?? d.extraNames
        projectsFolder = try c.decodeIfPresent(String.self, forKey: .projectsFolder) ?? d.projectsFolder
        weeklyFolder = try c.decodeIfPresent(String.self, forKey: .weeklyFolder) ?? d.weeklyFolder
        projectMap = try c.decodeIfPresent([String: String].self, forKey: .projectMap) ?? d.projectMap
        scheduleTime = try c.decodeIfPresent(String.self, forKey: .scheduleTime) ?? d.scheduleTime
        maxDepth = try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? d.maxDepth
        skipDirectories = try c.decodeIfPresent([String].self, forKey: .skipDirectories) ?? d.skipDirectories
        excludeRepos = try c.decodeIfPresent([String].self, forKey: .excludeRepos) ?? d.excludeRepos
    }

    /// Ayar dosyasını okur. Dosya yoksa varsayılanlar döner; `createIfMissing` ise dosya da oluşturulur.
    /// Dosya var ama okunamıyorsa sessizce varsayılana dönülmez, hata verilir.
    public static func load(from url: URL = Paths.configFile, createIfMissing: Bool = false) throws -> Config {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let config = Config()
            if createIfMissing {
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(config) { try? data.write(to: url, options: .atomic) }
            }
            return config
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Config.self, from: data)
        } catch let error as DecodingError {
            throw JournalError.configUnreadable(url.path, describe(error))
        } catch {
            throw JournalError.configUnreadable(url.path, error.localizedDescription)
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let key = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "\"\(key)\" alanının türü yanlış."
        case .dataCorrupted:
            return "Dosya geçerli bir JSON değil."
        case .keyNotFound(let key, _):
            return "\"\(key.stringValue)\" alanı eksik."
        @unknown default:
            return "Dosya çözümlenemedi."
        }
    }

    public var vaultURL: URL { Paths.expand(vault) }
    public var rootURLs: [URL] { roots.map(Paths.expand) }

    /// `scheduleTime` değerini saat ve dakikaya ayırır.
    public func scheduleHourMinute() throws -> (hour: Int, minute: Int) {
        let parts = scheduleTime.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else {
            throw JournalError.invalidScheduleTime(scheduleTime)
        }
        return (h, m)
    }
}

/// `state.json`: son başarılı çalışmanın kaydı.
public struct State: Codable, Sendable, Equatable {
    /// `tamamla` komutunun en son başarıyla işlediği gün (YYYY-MM-DD).
    public var lastSuccessfulDay: String?
    /// Son başarılı çalışmanın zamanı.
    public var lastRunAt: Date?

    public init(lastSuccessfulDay: String? = nil, lastRunAt: Date? = nil) {
        self.lastSuccessfulDay = lastSuccessfulDay
        self.lastRunAt = lastRunAt
    }

    /// Dosya yoksa ya da bozuksa boş durum döner; en kötü ihtimalle yalnızca bugün işlenir.
    public static func load(from url: URL = Paths.stateFile) -> State {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let state = try? decoder.decode(State.self, from: data) else {
            return State()
        }
        return state
    }

    public func save(to url: URL = Paths.stateFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            throw JournalError.stateUnwritable(url.path, error.localizedDescription)
        }
    }
}

/// `tamamla` komutunun hangi günleri ve haftaları işleyeceğini hesaplar.
public enum CatchUp {
    public static let maxDays = 7

    /// Son başarılı günden (o gün dahil; gece yarısına kadar atılan commit'ler kaçmasın) bugüne kadar,
    /// en fazla `maxDays` gün. Kayıt yoksa yalnızca bugün.
    public static func days(lastSuccessful: LocalDay?, today: LocalDay, calendar: Calendar) -> [LocalDay] {
        let earliest = today.adding(days: -(maxDays - 1), calendar: calendar)
        var first = today
        if let last = lastSuccessful, last < today { first = max(last, earliest) }
        var result: [LocalDay] = []
        var day = first
        while day <= today {
            result.append(day)
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    /// İşlenen günlerin haftalarından bitmiş olanlar; bugün Pazar ise içinde bulunulan hafta da eklenir.
    public static func weeks(for days: [LocalDay], today: LocalDay, calendar: Calendar) -> [ISOWeek] {
        let current = ISOWeek(containing: today, calendar: calendar)
        let isSunday = current.monday.adding(days: 6, calendar: calendar) == today
        var seen = Set<ISOWeek>()
        var result: [ISOWeek] = []
        for day in days {
            let week = ISOWeek(containing: day, calendar: calendar)
            guard week < current || (week == current && isSunday) else { continue }
            if seen.insert(week).inserted { result.append(week) }
        }
        return result
    }
}
