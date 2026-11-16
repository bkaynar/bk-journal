import Foundation

/// Saat dilimi bilgisi taşımayan takvim günü.
public struct LocalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Verilen anın, takvimin saat dilimindeki günü.
    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// `YYYY-MM-DD` biçimini okur; gerçek bir gün değilse nil döner.
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let back = utc.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Günün yerel saat dilimindeki başlangıcı (00:00).
    public func start(in calendar: Calendar) -> Date {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        return calendar.startOfDay(for: noon)
    }

    public func adding(days: Int, calendar: Calendar) -> LocalDay {
        // Öğlen üzerinden hesaplanır; yaz saati geçişlerinde gün kaymaz.
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        let moved = calendar.date(byAdding: .day, value: days, to: noon) ?? noon
        return LocalDay(date: moved, calendar: calendar)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// ISO 8601 haftası: Pazartesi başlar, yılın ilk haftası ilk Perşembe'yi içeren haftadır.
public struct ISOWeek: Hashable, Comparable, Sendable {
    public let year: Int
    public let week: Int
    public let monday: LocalDay

    public init(containing day: LocalDay, calendar: Calendar) {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let noon = iso.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: noon)
        year = c.yearForWeekOfYear ?? day.year
        week = c.weekOfYear ?? 1
        // weekday: 1 = Pazar … 7 = Cumartesi. Pazartesi'ye uzaklık:
        let offset = ((c.weekday ?? 2) + 5) % 7
        monday = day.adding(days: -offset, calendar: calendar)
    }

    /// Pazartesi'den Pazar'a yedi gün.
    public func days(calendar: Calendar) -> [LocalDay] {
        (0..<7).map { monday.adding(days: $0, calendar: calendar) }
    }

    /// Dosya adı: `2026-W47`.
    public var label: String { String(format: "%04d-W%02d", year, week) }

    public static func < (a: ISOWeek, b: ISOWeek) -> Bool { a.monday < b.monday }
}

/// Obsidian'ın kullandığı Moment.js tarih biçimlerinin dosya adları için gereken alt kümesi.
public enum MomentFormat {
    public static let fallback = "YYYY-MM-DD"

    /// Desteklenen belirteçler; uzun olan önce denenir.
    private static let tokens = ["YYYY", "GGGG", "YY", "MM", "DD", "HH", "mm", "ss", "WW", "M", "D", "H", "m", "s", "W"]

    /// Biçimi uygular. Tanınmayan bir belirteç varsa nil döner (ay/gün adları dile bağlı olduğu için desteklenmez).
    public static func format(_ date: Date, pattern: String, calendar: Calendar) -> String? {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let week = ISOWeek(containing: LocalDay(date: date, calendar: calendar), calendar: calendar)
        let chars = Array(pattern)
        var out = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "[" {
                // Köşeli parantez içi olduğu gibi yazılır.
                guard let close = chars[(i + 1)...].firstIndex(of: "]") else { return nil }
                out += String(chars[(i + 1)..<close])
                i = close + 1
                continue
            }
            if ch.isLetter {
                var end = i
                while end < chars.count, chars[end] == ch { end += 1 }
                let run = String(chars[i..<end])
                guard tokens.contains(run) else { return nil }
                switch run {
                case "YYYY": out += String(format: "%04d", c.year ?? 0)
                case "YY": out += String(format: "%02d", (c.year ?? 0) % 100)
                case "GGGG": out += String(format: "%04d", week.year)
                case "MM": out += String(format: "%02d", c.month ?? 0)
                case "M": out += String(c.month ?? 0)
                case "DD": out += String(format: "%02d", c.day ?? 0)
                case "D": out += String(c.day ?? 0)
                case "HH": out += String(format: "%02d", c.hour ?? 0)
                case "H": out += String(c.hour ?? 0)
                case "mm": out += String(format: "%02d", c.minute ?? 0)
                case "m": out += String(c.minute ?? 0)
                case "ss": out += String(format: "%02d", c.second ?? 0)
                case "s": out += String(c.second ?? 0)
                case "WW": out += String(format: "%02d", week.week)
                case "W": out += String(week.week)
                default: return nil
                }
                i = end
                continue
            }
            out.append(ch)
            i += 1
        }
        return out
    }

    /// Biçim çözülemezse `yedek` biçimi (varsayılan `YYYY-MM-DD`) kullanılır.
    public static func formatOrFallback(_ date: Date, pattern: String, calendar: Calendar, fallback: String = MomentFormat.fallback) -> String {
        if !pattern.isEmpty, let text = format(date, pattern: pattern, calendar: calendar) { return text }
        return format(date, pattern: fallback, calendar: calendar) ?? ""
    }
}

public enum TurkishDates {
    /// Pazartesi'den başlayan gün adları.
    public static let dayNames = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
    public static let shortDayNames = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]

    /// `16.11`
    public static func dayMonth(_ day: LocalDay) -> String { String(format: "%02d.%02d", day.day, day.month) }
    /// `16.11.2026`
    public static func full(_ day: LocalDay) -> String { String(format: "%02d.%02d.%04d", day.day, day.month, day.year) }
}
