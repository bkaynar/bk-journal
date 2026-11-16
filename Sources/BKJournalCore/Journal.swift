import Foundation

public struct NoteReport: Sendable {
    /// Günlük not için gün, haftalık rapor için haftanın etiketi.
    public let label: String
    public let block: String
    public let plan: NotePlan
    public let commitCount: Int
}

public struct CatchUpReport: Sendable {
    public var days: [NoteReport] = []
    public var weeks: [NoteReport] = []
    /// Grafikli çalışma panosu (ayarlarda kapalıysa nil).
    public var dashboard: NoteReport?
    /// İşlenemeyen notlar ve nedenleri.
    public var failures: [(label: String, message: String)] = []
    /// Son çalışmadan bu yana 7 günden fazla geçtiği için eski günler atlandıysa true.
    public var capped = false
}

/// Toplama ve yazma adımlarını birleştirir.
public struct Journal: Sendable {
    public let config: Config
    public let vault: Vault
    public let settings: DailyNotesSettings
    public let calendar: Calendar
    public let now: Date
    public let collector: GitCollector
    public let repos: [Repo]
    public let identity: Identity
    public let projects: [ProjectEntry]

    public static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    public init(
        config: Config, calendar: Calendar = Journal.localCalendar, now: Date = Date(),
        collector: GitCollector = GitCollector(), identity: Identity? = nil
    ) throws {
        self.config = config
        self.calendar = calendar
        self.now = now
        self.collector = collector
        vault = try Vault(root: config.vaultURL)
        settings = vault.dailyNotesSettings()
        projects = vault.projectEntries(folder: config.projectsFolder)

        let skip = GitCollector.defaultSkip.union(config.skipDirectories)
        let excluded = Set(config.excludeRepos.map { $0.lowercased() })
        repos = collector.discoverRepos(roots: config.rootURLs, maxDepth: config.maxDepth, skip: skip)
            .filter { !excluded.contains($0.name.lowercased()) }
        guard !repos.isEmpty else { throw JournalError.noRepos(config.roots) }

        if let identity {
            self.identity = identity
        } else {
            let global = collector.globalIdentity()
            self.identity = Identity(
                emails: [global.email].compactMap { $0 } + config.extraEmails,
                names: [global.name].compactMap { $0 } + config.extraNames)
        }
        guard !self.identity.isEmpty else {
            throw JournalError.usage("Yazar bilgisi bulunamadı. `git config --global user.email` ayarlayın ya da config.json içine \"extraEmails\" ekleyin.")
        }
    }

    public var today: LocalDay { LocalDay(date: now, calendar: calendar) }

    func link(_ repoName: String) -> ProjectLink? {
        ProjectMatcher.link(forRepo: repoName, entries: projects, overrides: config.projectMap)
    }

    /// `[first, last]` günlerinde (uçlar dahil) yazılmış commit'ler.
    public func commits(from first: LocalDay, through last: LocalDay) -> [Commit] {
        collector.collect(
            repos: repos, from: first.start(in: calendar),
            to: last.adding(days: 1, calendar: calendar).start(in: calendar), identity: identity)
    }

    func ensureNotFuture(_ day: LocalDay) throws {
        guard day <= today else { throw JournalError.futureDate(day.description) }
    }

    // MARK: Günlük not

    /// Bir günün notunu planlar; diske yazmaz. `commits` verilirse yeniden toplanmaz.
    public func planDay(_ day: LocalDay, commits provided: [Commit]? = nil) throws -> NoteReport {
        try ensureNotFuture(day)
        let url = try vault.dailyNoteURL(for: day, settings: settings, calendar: calendar)
        let all = provided ?? commits(from: day, through: day)
        let dayCommits = all.filter { LocalDay(date: $0.date, calendar: calendar) == day }

        // Commit edilmemiş değişiklikler çalıştırma anının görüntüsüdür: bugün için yeniden ölçülür,
        // geçmiş günlerde notta daha önce yazılmış olan korunur.
        let section: String?
        if day == today {
            section = Renderer.uncommittedSection(collector.uncommitted(repos: repos))
        } else if let data = try? Data(contentsOf: url), let old = MarkerBlock.existingBlock(in: data) {
            section = Renderer.extractUncommittedSection(fromBlock: old)
        } else {
            section = nil
        }

        let block = Renderer.dailyBlock(commits: dayCommits, uncommittedSection: section, calendar: calendar, link: link)
        let title = url.deletingPathExtension().lastPathComponent
        let plan = try NoteWriter.plan(url: url, block: block) {
            Template.newNotePrefix(
                template: vault.templateText(settings: settings), title: title,
                date: day == today ? now : day.start(in: calendar), now: now, calendar: calendar)
        }
        return NoteReport(label: day.description, block: block, plan: plan, commitCount: dayCommits.count)
    }

    // MARK: Haftalık rapor

    /// Bir ISO haftasının raporunu planlar; diske yazmaz.
    public func planWeek(_ week: ISOWeek, commits provided: [Commit]? = nil) throws -> NoteReport {
        try ensureNotFuture(week.monday)
        let days = week.days(calendar: calendar)
        let all = provided ?? commits(from: days[0], through: days[6])
        let weekCommits = all.filter { days.contains(LocalDay(date: $0.date, calendar: calendar)) }
        let url = try vault.weeklyNoteURL(for: week, settings: settings, weeklyFolder: config.weeklyFolder)
        let block = Renderer.weeklyBlock(week: week, commits: weekCommits, calendar: calendar, link: link)
        let plan = try NoteWriter.plan(url: url, block: block) {
            ("# Haftalık Rapor \(week.label)\n", .noTemplate)
        }
        return NoteReport(label: week.label, block: block, plan: plan, commitCount: weekCommits.count)
    }

    // MARK: Çalışma panosu

    var dashboardDayCount: Int { max(1, min(config.dashboardDays, 366)) }

    /// Panonun kapsadığı ilk gün.
    var dashboardFirstDay: LocalDay { today.adding(days: -(dashboardDayCount - 1), calendar: calendar) }

    /// Grafikli çalışma panosunu planlar; diske yazmaz. Ayarlarda pano kapalıysa nil döner.
    public func planDashboard(commits provided: [Commit]? = nil) throws -> NoteReport? {
        guard !config.dashboardNote.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let first = dashboardFirstDay
        let all = provided ?? commits(from: first, through: today)
        let window = all.filter {
            let day = LocalDay(date: $0.date, calendar: calendar)
            return !(day < first) && !(today < day)
        }
        let url = try vault.dashboardNoteURL(path: config.dashboardNote)
        let block = Renderer.dashboardBlock(commits: window, today: today, days: dashboardDayCount, calendar: calendar, link: link)
        let title = url.deletingPathExtension().lastPathComponent
        let plan = try NoteWriter.plan(url: url, block: block) {
            ("# \(title)\n", .noTemplate)
        }
        return NoteReport(label: title, block: block, plan: plan, commitCount: window.count)
    }

    // MARK: Tamamlama

    /// Son başarılı çalışmadan bugüne kadarki günleri (en fazla 7) ve biten haftaları işler.
    /// `write` false ise yalnızca planlar. Hepsi başarılıysa ve `write` ise durum dosyası güncellenir.
    public func catchUp(stateURL: URL = Paths.stateFile, write: Bool) throws -> CatchUpReport {
        let state = State.load(from: stateURL)
        let last = state.lastSuccessfulDay.flatMap { LocalDay(string: $0) }
        let days = CatchUp.days(lastSuccessful: last, today: today, calendar: calendar)
        let weeks = CatchUp.weeks(for: days, today: today, calendar: calendar)

        var report = CatchUpReport()
        if let last, let first = days.first, last < first { report.capped = true }

        // Tek seferde toplanır: en erken gün ya da en erken haftanın Pazartesi'si.
        // Pano açıksa onun penceresi de kapsanır.
        let dashboardEnabled = !config.dashboardNote.trimmingCharacters(in: .whitespaces).isEmpty
        let earliest = ([days.first].compactMap { $0 } + weeks.map(\.monday) + (dashboardEnabled ? [dashboardFirstDay] : [])).min() ?? today
        let all = commits(from: earliest, through: today)

        for day in days {
            do {
                let result = try planDay(day, commits: all)
                if write { try NoteWriter.commit(result.plan) }
                report.days.append(result)
            } catch {
                report.failures.append((day.description, error.localizedDescription))
            }
        }
        for week in weeks {
            do {
                let result = try planWeek(week, commits: all)
                if write { try NoteWriter.commit(result.plan) }
                report.weeks.append(result)
            } catch {
                report.failures.append((week.label, error.localizedDescription))
            }
        }
        do {
            if let result = try planDashboard(commits: all) {
                if write { try NoteWriter.commit(result.plan) }
                report.dashboard = result
            }
        } catch {
            report.failures.append(("Çalışma Panosu", error.localizedDescription))
        }
        if write, report.failures.isEmpty {
            try State(lastSuccessfulDay: today.description, lastRunAt: now).save(to: stateURL)
        }
        return report
    }
}
