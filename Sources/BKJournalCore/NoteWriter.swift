import Foundation

public enum WriteOutcome: Sendable, Equatable {
    case created
    case updated
    case unchanged
}

/// Yeni not oluşturulurken şablonun nasıl ele alındığı.
public enum TemplateDecision: Sendable, Equatable {
    /// Not zaten vardı; şablon kullanılmadı.
    case notNeeded
    /// Şablon yalnızca çekirdek yer tutucuları içeriyordu, doldurularak kullanıldı.
    case coreTemplate
    /// Şablonda Templater kodu vardı; ham kod kopyalanmadı, sade not oluşturuldu.
    case templaterSkipped
    /// Şablon ayarlanmamış ya da dosyası yok; sade not oluşturuldu.
    case noTemplate
}

/// Yazılacak dosyanın planı. `--kuru` ile yalnızca plan gösterilir.
public struct NotePlan: Sendable {
    public let url: URL
    public let data: Data
    public let outcome: WriteOutcome
    public let template: TemplateDecision
}

public enum NoteWriter {
    /// Hedef notun yeni içeriğini hesaplar; diske yazmaz.
    /// - Parameter newNotePrefix: Not yoksa bloğun önüne konacak metin ve şablon kararı.
    public static func plan(url: URL, block: String, newNotePrefix: () -> (String, TemplateDecision)) throws -> NotePlan {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let existing: Data
            do { existing = try Data(contentsOf: url) } catch {
                throw JournalError.writeFailed(url.path, error.localizedDescription)
            }
            let updated = try MarkerBlock.apply(block: block, to: existing, path: url.path)
            return NotePlan(url: url, data: updated, outcome: updated == existing ? .unchanged : .updated, template: .notNeeded)
        }
        let (prefix, decision) = newNotePrefix()
        // Şablonun kendisinde işaretler varsa blok oraya yerleşir; yoksa sona eklenir.
        let content = try MarkerBlock.apply(block: block, to: Data(prefix.utf8), path: url.path)
        return NotePlan(url: url, data: content, outcome: .created, template: decision)
    }

    /// Planı uygular. İçerik aynıysa hiçbir şey yazmaz.
    public static func commit(_ plan: NotePlan) throws {
        guard plan.outcome != .unchanged else { return }
        try writeAtomically(plan.data, to: plan.url)
    }

    /// Aynı klasörde geçici dosyaya yazar, sonra `rename` ile yerine koyar; yarım dosya hiçbir an görünmez.
    public static func writeAtomically(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        // Not sembolik bağlantıysa bağlantının kendisi değil, gösterdiği dosya değiştirilir.
        let target = fm.fileExists(atPath: url.path) ? url.resolvingSymlinksInPath() : url
        let directory = target.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".bk-journal-\(UUID().uuidString).tmp")
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: temp)
            if let permissions = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions] {
                try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
            }
            guard rename(temp.path, target.path) == 0 else {
                throw JournalError.writeFailed(target.path, String(cString: strerror(errno)))
            }
        } catch {
            try? fm.removeItem(at: temp)
            if error is JournalError { throw error }
            throw JournalError.writeFailed(target.path, error.localizedDescription)
        }
    }
}

/// Obsidian'ın çekirdek şablon yer tutucuları: `{{date}}`, `{{time}}`, `{{title}}` ve `{{date:BİÇİM}}`.
public enum Template {
    /// Şablonda Templater kodu var mı?
    public static func containsTemplater(_ text: String) -> Bool { text.contains("<%") }

    public static func substitute(_ text: String, title: String, date: Date, now: Date, calendar: Calendar) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\{\{\s*(date|time|title)\s*(?::([^}]*))?\}\}"#, options: [.caseInsensitive]) else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let kind = ns.substring(with: match.range(at: 1)).lowercased()
            let custom = match.range(at: 2).location == NSNotFound
                ? "" : ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            switch kind {
            case "title":
                result += title
            case "time":
                result += MomentFormat.formatOrFallback(now, pattern: custom.isEmpty ? "HH:mm" : custom, calendar: calendar, fallback: "HH:mm")
            default:
                result += MomentFormat.formatOrFallback(date, pattern: custom.isEmpty ? MomentFormat.fallback : custom, calendar: calendar)
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Yeni günlük notun, bloktan önceki kısmı.
    public static func newNotePrefix(template: String?, title: String, date: Date, now: Date, calendar: Calendar) -> (String, TemplateDecision) {
        let minimal = "# \(title)\n"
        guard let template, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (minimal, .noTemplate)
        }
        if containsTemplater(template) { return (minimal, .templaterSkipped) }
        return (substitute(template, title: title, date: date, now: now, calendar: calendar), .coreTemplate)
    }
}
