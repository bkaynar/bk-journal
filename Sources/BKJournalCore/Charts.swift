import Foundation

/// Mermaid grafikleri ve grafikli çalışma panosu. Obsidian Mermaid'i eklenti gerektirmeden çizer.
extension Renderer {

    /// Mermaid etiketlerinde tırnak ve satır sonu grafiği bozar.
    static func chartLabel(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "`", with: "'")
            .replacingOccurrences(of: "<", with: "‹")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Pasta grafik. Yalnızca sıfırdan büyük dilimler çizilir; hiç dilim yoksa nil.
    static func pieChart(title: String, slices: [(label: String, value: Int)]) -> [String]? {
        let visible = slices.filter { $0.value > 0 }
        guard !visible.isEmpty else { return nil }
        var lines = ["```mermaid", "pie showData", "    title \(chartLabel(title))"]
        for slice in visible {
            lines.append("    \"\(chartLabel(slice.label))\" : \(slice.value)")
        }
        lines.append("```")
        return lines
    }

    /// Sütun grafik.
    static func barChart(title: String, yTitle: String, labels: [String], values: [Int]) -> [String] {
        let top = max(values.max() ?? 0, 1)
        return [
            "```mermaid",
            "xychart-beta",
            "    title \"\(chartLabel(title))\"",
            "    x-axis [\(labels.map { "\"\(chartLabel($0))\"" }.joined(separator: ", "))]",
            "    y-axis \"\(chartLabel(yTitle))\" 0 --> \(top)",
            "    bar [\(values.map(String.init).joined(separator: ", "))]",
            "```",
        ]
    }

    /// Projeleri commit sayısına göre (çoktan aza) sıralar.
    static func projectsByCommits(_ commits: [Commit]) -> [(name: String, commits: [Commit])] {
        groups(commits).sorted { ($1.commits.count, $0.name.lowercased()) < ($0.commits.count, $1.name.lowercased()) }
    }

    /// Haftalık rapora eklenen proje dağılımı grafiği.
    static func weeklyChart(_ commits: [Commit]) -> [String] {
        guard let pie = pieChart(
            title: "Projelere göre commit",
            slices: projectsByCommits(commits).map { ($0.name, $0.commits.count) }) else { return [] }
        return ["", "### Proje dağılımı", ""] + pie
    }

    /// Çalışma panosunun bloğu (işaretler dahil): son `days` günün grafikleri ve proje tablosu.
    public static func dashboardBlock(
        commits: [Commit], today: LocalDay, days: Int, calendar: Calendar, link: (String) -> ProjectLink?
    ) -> String {
        let first = today.adding(days: -(days - 1), calendar: calendar)
        let range = "\(TurkishDates.full(first)) – \(TurkishDates.full(today))"
        var lines = ["## Çalışma Panosu · son \(days) gün", ""]
        guard !commits.isEmpty else {
            lines.append("**\(range):** Bu dönemde commit yok.")
            return MarkerBlock.wrap(lines.joined(separator: "\n"))
        }

        let byDay = Dictionary(grouping: commits) { LocalDay(date: $0.date, calendar: calendar) }
        lines.append("**\(range):** \(totals(commits)), \(byDay.count) aktif gün")

        let projects = projectsByCommits(commits)
        if let pie = pieChart(title: "Projelere göre commit (son \(days) gün)", slices: projects.map { ($0.name, $0.commits.count) }) {
            lines += ["", "### Hangi projede ne kadar çalıştım", ""] + pie
        }

        let weekStart = today.adding(days: -6, calendar: calendar)
        let lastWeek = commits.filter { !(LocalDay(date: $0.date, calendar: calendar) < weekStart) }
        if days > 7, let pie = pieChart(title: "Projelere göre commit (son 7 gün)", slices: projectsByCommits(lastWeek).map { ($0.name, $0.commits.count) }) {
            lines += ["", "### Son 7 gün", ""] + pie
        }

        let allDays = (0..<days).map { first.adding(days: $0, calendar: calendar) }
        lines += ["", "### Günlük commit sayısı", ""]
        lines += barChart(
            title: "Günlük commit (\(TurkishDates.dayMonth(first)) – \(TurkishDates.dayMonth(today)))",
            yTitle: "Commit",
            labels: allDays.map { String($0.day) },
            values: allDays.map { byDay[$0]?.count ?? 0 })

        lines += ["", "### Projelere göre değişen satır", ""]
        lines += barChart(
            title: "Eklenen + silinen satır",
            yTitle: "Satır",
            labels: projects.map(\.name),
            values: projects.map { $0.commits.reduce(0) { $0 + $1.insertions + $1.deletions } })

        lines += ["", "### Projeler", "", "| Proje | Commit | Aktif gün | Eklenen | Silinen | Son çalışma |", "| --- | ---: | ---: | ---: | ---: | --- |"]
        for project in projects {
            let list = project.commits
            let activeDays = Set(list.map { LocalDay(date: $0.date, calendar: calendar) })
            let last = activeDays.max().map(TurkishDates.full) ?? "–"
            let name = link(project.name)?.wikiLink.replacingOccurrences(of: "|", with: "\\|") ?? cell(project.name)
            lines.append("| \(name) | \(list.count) | \(activeDays.count) | +\(list.reduce(0) { $0 + $1.insertions }) | \(minus)\(list.reduce(0) { $0 + $1.deletions }) | \(last) |")
        }
        return MarkerBlock.wrap(lines.joined(separator: "\n"))
    }
}
