import Foundation

/// `.obsidian/daily-notes.json` içeriği.
public struct DailyNotesSettings: Sendable, Equatable {
    public var format: String
    public var folder: String
    public var template: String

    public init(format: String = MomentFormat.fallback, folder: String = "", template: String = "") {
        self.format = format
        self.folder = folder
        self.template = template
    }
}

/// `10 Projeler` altındaki bir not ya da klasör.
public struct ProjectEntry: Sendable, Equatable {
    /// Görünen ad (uzantısız dosya adı ya da klasör adı).
    public let name: String
    /// Kasa köküne göre, `.md` uzantısız bağlantı hedefi.
    public let linkTarget: String

    public init(name: String, linkTarget: String) {
        self.name = name
        self.linkTarget = linkTarget
    }
}

/// Obsidian kasası. Yalnızca şunları okur: `.obsidian/daily-notes.json`, günlük not şablonu,
/// Templater ayar dosyası ve proje klasöründeki dosya/klasör ADLARI.
public struct Vault: Sendable {
    public let root: URL

    public init(root: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw JournalError.vaultMissing(root.path)
        }
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Günlük not ayarları her çalıştırmada dosyadan okunur. Dosya ya da alan yoksa Obsidian'ın varsayılanları geçerlidir.
    public func dailyNotesSettings() -> DailyNotesSettings {
        var settings = DailyNotesSettings()
        let url = root.appendingPathComponent(".obsidian/daily-notes.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return settings }
        if let format = json["format"] as? String, !format.isEmpty { settings.format = format }
        if let folder = json["folder"] as? String { settings.folder = Self.trimSlashes(folder) }
        if let template = json["template"] as? String { settings.template = Self.trimSlashes(template) }
        return settings
    }

    static func trimSlashes(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    /// Kasaya göreli yolu doğrular ve tam yola çevirir. Kasanın dışına çıkan yollar reddedilir.
    public func resolve(relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw JournalError.outsideVault(url.path) }
        return url
    }

    /// Verilen günün günlük notu: `<kasa>/<klasör>/<biçimlenmiş tarih>.md`.
    public func dailyNoteURL(for day: LocalDay, settings: DailyNotesSettings, calendar: Calendar) throws -> URL {
        let name = MomentFormat.formatOrFallback(day.start(in: calendar), pattern: settings.format, calendar: calendar)
        let relative = (settings.folder.isEmpty ? "" : settings.folder + "/") + name + ".md"
        return try resolve(relativePath: relative)
    }

    /// Haftalık rapor: `<klasör>/<YYYY>-W<WW>.md`. Klasör verilmezse `<günlük klasörü>/Haftalık`.
    public func weeklyNoteURL(for week: ISOWeek, settings: DailyNotesSettings, weeklyFolder: String) throws -> URL {
        var folder = Self.trimSlashes(weeklyFolder)
        if folder.isEmpty { folder = (settings.folder.isEmpty ? "" : settings.folder + "/") + "Haftalık" }
        return try resolve(relativePath: folder + "/" + week.label + ".md")
    }

    /// Günlük not şablonunun metni. Şablon ayarlanmamışsa ya da dosya yoksa nil.
    public func templateText(settings: DailyNotesSettings) -> String? {
        guard !settings.template.isEmpty else { return nil }
        let relative = settings.template.hasSuffix(".md") ? settings.template : settings.template + ".md"
        guard let url = try? resolve(relativePath: relative), let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Templater'ın "yeni dosya oluşturulunca tetikle" ayarı açık mı? Eklenti ayar dosyası yoksa kapalı sayılır.
    public func templaterTriggersOnCreation() -> Bool {
        let url = root.appendingPathComponent(".obsidian/plugins/templater-obsidian/data.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["trigger_on_file_creation"] as? Bool ?? false
    }

    /// Proje klasöründeki notlar ve klasörler. Dosya içerikleri okunmaz, yalnızca adlara bakılır.
    public func projectEntries(folder: String) -> [ProjectEntry] {
        let fm = FileManager.default
        let folder = Self.trimSlashes(folder)
        guard !folder.isEmpty, let base = try? resolve(relativePath: folder),
              let names = try? fm.contentsOfDirectory(atPath: base.path) else { return [] }
        var notes: [ProjectEntry] = []
        var folders: [ProjectEntry] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            var isDir: ObjCBool = false
            let path = base.appendingPathComponent(name).path
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                // Klasörün içinde kendi adını taşıyan not ("klasör notu") varsa ona, yoksa
                // oluşturulduğunda klasörün içine düşecek aynı adlı nota bağlanır.
                let children = (try? fm.contentsOfDirectory(atPath: path)) ?? []
                let key = ProjectMatcher.normalize(name)
                let folderNote = children.sorted().first {
                    $0.hasSuffix(".md") && ProjectMatcher.normalize(String($0.dropLast(3))) == key
                }
                let noteName = folderNote.map { String($0.dropLast(3)) } ?? name
                folders.append(ProjectEntry(name: name, linkTarget: "\(folder)/\(name)/\(noteName)"))
            } else if name.hasSuffix(".md") {
                let base = String(name.dropLast(3))
                notes.append(ProjectEntry(name: base, linkTarget: "\(folder)/\(base)"))
            }
        }
        // Aynı ada sahip not ve klasör varsa not öne geçer.
        return notes + folders
    }
}

/// Başlıkta kullanılacak wiki bağlantısı.
public struct ProjectLink: Sendable, Equatable {
    public let target: String
    public let display: String

    public init(target: String, display: String) {
        self.target = target
        self.display = display
    }

    public var wikiLink: String { target == display ? "[[\(display)]]" : "[[\(target)|\(display)]]" }
}

public enum ProjectMatcher {
    /// Küçük harf, yalnızca harf ve rakam. Türkçe harfler ASCII karşılıklarına indirgenir:
    /// `Trafik360` → `trafik360`, `bio.re` → `biore`, `İşletim Sistemleri` → `isletimsistemleri`.
    public static func normalize(_ text: String) -> String {
        var out = ""
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar {
            case "ı", "İ", "I": out += "i"
            case "ş", "Ş": out += "s"
            case "ğ", "Ğ": out += "g"
            case "ü", "Ü": out += "u"
            case "ö", "Ö": out += "o"
            case "ç", "Ç": out += "c"
            default:
                if CharacterSet.alphanumerics.contains(scalar) {
                    let folded = String(scalar).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                    out += folded.lowercased()
                }
            }
        }
        return out
    }

    /// Depo adına karşılık gelen proje notunu bulur. `overrides` (config.json → projectMap) önceliklidir:
    /// değer boşsa bağlantı verilmez; bir proje adıyla eşleşiyorsa o kullanılır; aksi halde değer bağlantı hedefidir.
    public static func link(forRepo repoName: String, entries: [ProjectEntry], overrides: [String: String] = [:]) -> ProjectLink? {
        let key = normalize(repoName)
        let override = overrides[repoName] ?? overrides.first { normalize($0.key) == key }?.value
        if let override {
            let value = override.trimmingCharacters(in: .whitespaces)
            if value.isEmpty { return nil }
            if let entry = entries.first(where: { normalize($0.name) == normalize(value) }) {
                return ProjectLink(target: entry.linkTarget, display: entry.name)
            }
            let target = value.hasSuffix(".md") ? String(value.dropLast(3)) : value
            return ProjectLink(target: target, display: (target as NSString).lastPathComponent)
        }
        guard !key.isEmpty, let entry = entries.first(where: { normalize($0.name) == key }) else { return nil }
        return ProjectLink(target: entry.linkTarget, display: entry.name)
    }
}
