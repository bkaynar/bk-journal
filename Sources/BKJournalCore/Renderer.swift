import Foundation

/// Not bloklarının Türkçe içeriğini üretir. Çıktı yalnızca girdilere bağlıdır (zaman damgası yoktur);
/// böylece aynı veriler aynı metni verir ve dosya gereksiz yere yeniden yazılmaz.
public enum Renderer {
    public static let minus = "\u{2212}"
    public static let uncommittedHeading = "**Commit edilmemiş değişiklikler**"

    /// Commit başlıklarını Markdown/Obsidian açısından zararsız hale getirir:
    /// HTML etiketleri, yorum işaretleri (dolayısıyla blok işaretleri), Templater kodu,
    /// wiki bağlantıları ve Obsidian yorumları etkisizleşir.
    public static func safeText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "[[", with: "\\[\\[")
            .replacingOccurrences(of: "%%", with: "\\%\\%")
            .trimmingCharacters(in: .whitespaces)
    }

    static func branchLabel(_ branch: String?) -> String {
        guard let branch, !branch.isEmpty else { return "" }
        if branch.contains("`") || branch.contains("<") { return " · " + safeText(branch) }
        return " · `\(branch)`"
    }

    static func totals(_ commits: [Commit]) -> String {
        let projects = Set(commits.map(\.repoPath)).count
        let added = commits.reduce(0) { $0 + $1.insertions }
        let removed = commits.reduce(0) { $0 + $1.deletions }
        return "\(commits.count) commit, \(projects) proje, +\(added) / \(minus)\(removed) satır"
    }

    /// Commit'leri projeye göre gruplar; projeler ada, commit'ler zamana göre sıralanır.
    static func groups(_ commits: [Commit]) -> [(name: String, commits: [Commit])] {
        Dictionary(grouping: commits, by: \.repoPath)
            .map { (name: $0.value[0].repoName, path: $0.key, commits: $0.value.sorted { ($0.date, $0.hash) < ($1.date, $1.hash) }) }
            .sorted { ($0.name.lowercased(), $0.path) < ($1.name.lowercased(), $1.path) }
            .map { (name: $0.name, commits: $0.commits) }
    }

    static func heading(_ name: String, link: (String) -> ProjectLink?) -> String {
        link(name)?.wikiLink ?? safeText(name)
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: Günlük

    /// "Commit edilmemiş değişiklikler" bölümü; değişiklik yoksa nil.
    public static func uncommittedSection(_ statuses: [RepoStatus]) -> String? {
        guard !statuses.isEmpty else { return nil }
        var lines = [uncommittedHeading]
        for status in statuses.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
            var parts: [String] = []
            if status.changed > 0 { parts.append("\(status.changed) değişen") }
            if status.untracked > 0 { parts.append("\(status.untracked) izlenmeyen") }
            lines.append("- \(safeText(status.name)): \(parts.joined(separator: ", ")) dosya")
        }
        return lines.joined(separator: "\n")
    }

    /// Daha önce yazılmış bloktaki "Commit edilmemiş değişiklikler" bölümünü çıkarır.
    /// Geçmiş bir gün yeniden yazılırken o günün kaydı korunur.
    public static func extractUncommittedSection(fromBlock block: String) -> String? {
        guard let start = block.range(of: uncommittedHeading) else { return nil }
        var section = String(block[start.lowerBound...])
        if let end = section.range(of: MarkerBlock.end) { section = String(section[..<end.lowerBound]) }
        let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Günlük notun bloğu (işaretler dahil).
    public static func dailyBlock(
        commits: [Commit], uncommittedSection: String?, calendar: Calendar, link: (String) -> ProjectLink?
    ) -> String {
        var lines = ["## Çalışma Özeti", ""]
        if commits.isEmpty {
            lines.append("Bugün commit yok.")
        } else {
            lines.append("**\(totals(commits))**")
            for group in groups(commits) {
                lines.append("")
                lines.append("### \(heading(group.name, link: link))")
                for commit in group.commits {
                    lines.append("- \(time(commit.date, calendar: calendar)) \(safeText(commit.subject))\(branchLabel(commit.branch)) (+\(commit.insertions)/\(minus)\(commit.deletions))")
                }
            }
        }
        if let uncommittedSection {
            lines.append("")
            lines.append(uncommittedSection)
        }
        return MarkerBlock.wrap(lines.joined(separator: "\n"))
    }

    // MARK: Haftalık

    static func cell(_ text: String) -> String { safeText(text).replacingOccurrences(of: "|", with: "\\|") }

    /// Haftalık raporun bloğu (işaretler dahil). Staj/ders raporuna yapıştırılabilecek düzendedir.
    public static func weeklyBlock(week: ISOWeek, commits: [Commit], calendar: Calendar, link: (String) -> ProjectLink?) -> String {
        let days = week.days(calendar: calendar)
        var lines = ["## Haftalık Çalışma Raporu · \(week.label)", ""]
        let range = "\(TurkishDates.full(days[0])) – \(TurkishDates.full(days[6]))"
        guard !commits.isEmpty else {
            lines.append("**\(range):** Bu hafta commit yok.")
            return MarkerBlock.wrap(lines.joined(separator: "\n"))
        }
        lines.append("**\(range):** \(totals(commits))")
        lines += weeklyChart(commits)

        let byDay = Dictionary(grouping: commits) { LocalDay(date: $0.date, calendar: calendar) }
        lines += ["", "### Günlere göre", "", "| Gün | Commit | Proje | Eklenen | Silinen |", "| --- | ---: | ---: | ---: | ---: |"]
        for (index, day) in days.enumerated() {
            let label = "\(TurkishDates.dayMonth(day)) \(TurkishDates.dayNames[index])"
            if let list = byDay[day], !list.isEmpty {
                let projects = Set(list.map(\.repoPath)).count
                lines.append("| \(label) | \(list.count) | \(projects) | +\(list.reduce(0) { $0 + $1.insertions }) | \(minus)\(list.reduce(0) { $0 + $1.deletions }) |")
            } else {
                lines.append("| \(label) | – | – | – | – |")
            }
        }

        let grouped = groups(commits)
        lines += ["", "### Projelere göre", "", "| Proje | Commit | Değişen dosya | Eklenen | Silinen |", "| --- | ---: | ---: | ---: | ---: |"]
        for group in grouped {
            let list = group.commits
            lines.append("| \(cell(group.name)) | \(list.count) | \(list.reduce(0) { $0 + $1.filesChanged }) | +\(list.reduce(0) { $0 + $1.insertions }) | \(minus)\(list.reduce(0) { $0 + $1.deletions }) |")
        }

        lines += ["", "### Yapılan işler"]
        for group in grouped {
            lines.append("")
            lines.append("#### \(heading(group.name, link: link))")
            for commit in group.commits {
                let day = LocalDay(date: commit.date, calendar: calendar)
                let index = days.firstIndex(of: day) ?? 0
                lines.append("- \(TurkishDates.dayMonth(day)) \(TurkishDates.shortDayNames[index]): \(safeText(commit.subject))")
            }
        }
        return MarkerBlock.wrap(lines.joined(separator: "\n"))
    }
}
