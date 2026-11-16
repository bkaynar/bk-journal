import Foundation

public struct Repo: Sendable, Equatable {
    /// Ana çalışma klasörünün adı; proje adı olarak kullanılır.
    public let name: String
    public let path: URL
    /// Deponun ortak `.git` klasörü. Bağlı worktree'ler aynı değeri paylaşır.
    public let commonDir: String
}

public struct Commit: Sendable, Equatable {
    public let hash: String
    /// Yazar tarihi (commit'in yazıldığı an).
    public let date: Date
    public let subject: String
    /// En iyi tahminle dal adı; bulunamazsa nil.
    public let branch: String?
    public let filesChanged: Int
    public let insertions: Int
    public let deletions: Int
    public let repoName: String
    public let repoPath: String
}

public struct RepoStatus: Sendable, Equatable {
    public let name: String
    /// Değişmiş ya da sahnelenmiş izlenen dosya sayısı.
    public let changed: Int
    /// İzlenmeyen dosya sayısı.
    public let untracked: Int

    public init(name: String, changed: Int, untracked: Int) {
        self.name = name
        self.changed = changed
        self.untracked = untracked
    }
}

/// Bir commit'in kullanıcıya ait olup olmadığını belirler.
public struct Identity: Sendable, Equatable {
    public let emails: Set<String>
    public let names: Set<String>

    public init(emails: [String], names: [String]) {
        self.emails = Set(emails.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
        self.names = Set(names.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    public func matches(name: String, email: String) -> Bool {
        emails.contains(email.lowercased()) || names.contains(name.lowercased())
    }

    public var isEmpty: Bool { emails.isEmpty && names.isEmpty }
}

/// `git log` çıktısından ayrıştırılan ham kayıt.
public struct RawCommit: Sendable, Equatable {
    public let hash: String
    public let timestamp: TimeInterval
    public let authorName: String
    public let authorEmail: String
    public let ref: String
    public let subject: String
    public let filesChanged: Int
    public let insertions: Int
    public let deletions: Int
}

/// Depoları bulur ve commit'leri toplar. Yalnızca salt okunur git komutları çalıştırır:
/// `log`, `rev-parse`, `status`, `config --get`.
public struct GitCollector: Sendable {
    public var gitPath = "/usr/bin/git"
    /// Testlerde genel git ayarlarını yalıtmak için ek ortam değişkenleri.
    public var extraEnvironment: [String: String] = [:]
    public var timeout: TimeInterval = 60

    /// İçine girilmeyen klasörler.
    public static let defaultSkip: Set<String> = [
        "node_modules", ".build", "build", "Pods", "DerivedData", "dist", "target", "vendor",
        ".git", ".gradle", ".dart_tool", ".next", ".venv", "venv", "__pycache__", "Carthage", ".idea",
    ]

    static let recordSeparator = "\u{1e}"
    static let fieldSeparator = "\u{1f}"

    public init() {}

    private var environment: [String: String] {
        var env = ["GIT_OPTIONAL_LOCKS": "0", "LC_ALL": "C", "GIT_TERMINAL_PROMPT": "0"]
        for (key, value) in extraEnvironment { env[key] = value }
        return env
    }

    private func git(_ arguments: [String], in directory: URL?, timeout: TimeInterval? = nil) -> ShellOutput {
        Shell.run(gitPath, arguments, cwd: directory, environment: environment, timeout: timeout ?? self.timeout)
    }

    // MARK: Kimlik

    /// `git config --global` içindeki e-posta ve ad.
    public func globalIdentity() -> (email: String?, name: String?) {
        func value(_ key: String) -> String? {
            let out = git(["config", "--global", "--get", key], in: nil, timeout: 10)
            let text = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return out.succeeded && !text.isEmpty ? text : nil
        }
        return (value("user.email"), value("user.name"))
    }

    // MARK: Depo keşfi

    /// Köklerin altında en fazla `maxDepth` derinlikte `.git` içeren klasörleri bulur.
    /// Aynı nesne veritabanını paylaşan klasörler (bağlı worktree'ler) tek depo sayılır.
    public func discoverRepos(roots: [URL], maxDepth: Int = 3, skip: Set<String> = GitCollector.defaultSkip) -> [Repo] {
        let fm = FileManager.default
        var candidates: [URL] = []

        func hasGit(_ dir: URL) -> Bool {
            fm.fileExists(atPath: dir.appendingPathComponent(".git").path)
        }

        func scan(_ dir: URL, depth: Int) {
            guard depth < maxDepth,
                  let children = try? fm.contentsOfDirectory(
                      at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return }
            for child in children.sorted(by: { $0.path < $1.path }) {
                let name = child.lastPathComponent
                // Gizli klasörlere girilmez (.claude/worktrees gibi).
                guard !name.hasPrefix("."), !skip.contains(name),
                      let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                if hasGit(child) { candidates.append(child) }
                scan(child, depth: depth + 1)
            }
        }

        for root in roots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if hasGit(root) { candidates.append(root) }
            scan(root, depth: 0)
        }

        var byCommonDir: [String: Repo] = [:]
        for candidate in candidates {
            let out = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: candidate, timeout: 15)
            guard out.succeeded else { continue }
            var common = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !common.isEmpty else { continue }
            if !common.hasPrefix("/") { common = candidate.appendingPathComponent(common).path }
            let commonURL = URL(fileURLWithPath: common).resolvingSymlinksInPath().standardizedFileURL
            let key = commonURL.path
            guard byCommonDir[key] == nil else { continue }
            // Ortak klasör `<ana klasör>/.git` ise proje adı ana klasörden alınır;
            // böylece yalnızca bir worktree bulunsa bile doğru adlandırılır.
            var main = candidate
            if commonURL.lastPathComponent == ".git" {
                let parent = commonURL.deletingLastPathComponent()
                if fm.fileExists(atPath: parent.path) { main = parent }
            }
            byCommonDir[key] = Repo(name: main.lastPathComponent, path: main, commonDir: key)
        }
        return byCommonDir.values.sorted {
            ($0.name.lowercased(), $0.path.path) < ($1.name.lowercased(), $1.path.path)
        }
    }

    // MARK: Commit toplama

    /// `[from, to)` aralığında yazılmış, kullanıcıya ait, birleştirme olmayan commit'ler.
    /// Tüm depolar taranır, aynı hash bir kez sayılır, sonuç zamana göre sıralanır.
    public func collect(repos: [Repo], from: Date, to: Date, identity: Identity) -> [Commit] {
        let lock = NSLock()
        var perRepo = [[Commit]](repeating: [], count: repos.count)
        DispatchQueue.concurrentPerform(iterations: repos.count) { index in
            let found = commits(in: repos[index], from: from, to: to, identity: identity)
            lock.lock()
            perRepo[index] = found
            lock.unlock()
        }
        var chosen: [String: Commit] = [:]
        for commit in perRepo.flatMap({ $0 }) {
            if let existing = chosen[commit.hash] {
                // Aynı commit iki ayrı kopyada varsa yerel dalında bulunduğu depo tercih edilir.
                if !Self.isLocalBranch(existing.branch), Self.isLocalBranch(commit.branch) { chosen[commit.hash] = commit }
            } else {
                chosen[commit.hash] = commit
            }
        }
        return chosen.values.sorted { ($0.date, $0.repoName, $0.hash) < ($1.date, $1.repoName, $1.hash) }
    }

    private static func isLocalBranch(_ branch: String?) -> Bool {
        guard let branch else { return false }
        return !branch.hasPrefix("origin/") && !branch.hasPrefix("upstream/")
    }

    /// Tek bir depodaki commit'ler.
    public func commits(in repo: Repo, from: Date, to: Date, identity: Identity) -> [Commit] {
        // --since committer tarihine bakar; yazar tarihi aralıkta olan her commit'in committer tarihi
        // de en az `from` olduğundan ön eleme için yeterlidir. Kesin süzme aşağıda yazar tarihiyle yapılır.
        let since = ISO8601DateFormatter().string(from: from)
        let format = ["%H", "%at", "%an", "%ae", "%S", "%s"].joined(separator: "%x1f")
        // Dal adı için `%S` (commit'e hangi ref üzerinden ulaşıldığı) kullanılır. Aynı commit birden çok
        // dalın ucundaysa ilk verilen ref kazanır; bu yüzden önce main/master, sonra HEAD, sonra diğerleri verilir.
        // (Köşeli parantez, git'in kalıba "/*" eklemesini önler; eşleşme yoksa hata vermez.)
        func log(includeHead: Bool) -> ShellOutput {
            git([
                "-c", "log.showSignature=false",
                "log", "--no-merges", "--no-color", "--since=\(since)", "--numstat", "--format=%x1e\(format)",
                "--glob=refs/heads/mai[n]", "--glob=refs/heads/maste[r]",
            ] + (includeHead ? ["HEAD"] : []) + ["--exclude=refs/stash", "--all"], in: repo.path)
        }
        var out = log(includeHead: true)
        // Henüz commit'i olmayan bir dalda HEAD çözülemez; o durumda HEAD'siz denenir.
        if !out.succeeded && !out.timedOut { out = log(includeHead: false) }
        guard out.succeeded else { return [] }
        let raws = Self.parseLog(out.stdout)

        var headBranch: String?
        if raws.contains(where: { $0.ref == "HEAD" }) {
            let head = git(["rev-parse", "--abbrev-ref", "HEAD"], in: repo.path, timeout: 10)
            let name = head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if head.succeeded, !name.isEmpty, name != "HEAD" { headBranch = name }
        }

        var seen = Set<String>()
        var result: [Commit] = []
        for raw in raws {
            let date = Date(timeIntervalSince1970: raw.timestamp)
            guard date >= from, date < to,
                  identity.matches(name: raw.authorName, email: raw.authorEmail),
                  seen.insert(raw.hash).inserted else { continue }
            result.append(Commit(
                hash: raw.hash, date: date, subject: raw.subject,
                branch: raw.ref == "HEAD" ? headBranch : Self.branchName(fromRef: raw.ref),
                filesChanged: raw.filesChanged, insertions: raw.insertions, deletions: raw.deletions,
                repoName: repo.name, repoPath: repo.path.path))
        }
        return result
    }

    /// `--format=%x1e%H%x1f%at%x1f%an%x1f%ae%x1f%S%x1f%s --numstat` çıktısını ayrıştırır.
    public static func parseLog(_ output: String) -> [RawCommit] {
        var result: [RawCommit] = []
        for record in output.components(separatedBy: recordSeparator) {
            let lines = record.components(separatedBy: "\n")
            guard let header = lines.first, !header.isEmpty else { continue }
            let fields = header.components(separatedBy: fieldSeparator)
            guard fields.count >= 6, let timestamp = TimeInterval(fields[1]) else { continue }
            var files = 0, insertions = 0, deletions = 0
            for line in lines.dropFirst() where !line.isEmpty {
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3 else { continue }
                files += 1
                // İkili dosyalarda sayı yerine "-" gelir.
                insertions += Int(parts[0]) ?? 0
                deletions += Int(parts[1]) ?? 0
            }
            result.append(RawCommit(
                hash: fields[0], timestamp: timestamp, authorName: fields[2], authorEmail: fields[3],
                ref: fields[4], subject: fields[5...].joined(separator: fieldSeparator),
                filesChanged: files, insertions: insertions, deletions: deletions))
        }
        return result
    }

    /// `refs/heads/main` → `main`, `refs/remotes/origin/x` → `origin/x`. Etiket ve HEAD için nil.
    public static func branchName(fromRef ref: String) -> String? {
        if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst("refs/heads/".count)) }
        if ref.hasPrefix("refs/remotes/") {
            let name = String(ref.dropFirst("refs/remotes/".count))
            return name.hasSuffix("/HEAD") ? nil : name
        }
        return nil
    }

    // MARK: Commit edilmemiş değişiklikler

    /// Çalışma klasöründe commit edilmemiş değişiklik bulunan depolar (yalnızca sayılar).
    public func uncommitted(repos: [Repo]) -> [RepoStatus] {
        let lock = NSLock()
        var statuses = [RepoStatus?](repeating: nil, count: repos.count)
        DispatchQueue.concurrentPerform(iterations: repos.count) { index in
            let out = git(["status", "--porcelain", "--untracked-files=normal"], in: repos[index].path, timeout: 30)
            guard out.succeeded else { return }
            let (changed, untracked) = Self.parseStatus(out.stdout)
            guard changed + untracked > 0 else { return }
            lock.lock()
            statuses[index] = RepoStatus(name: repos[index].name, changed: changed, untracked: untracked)
            lock.unlock()
        }
        return statuses.compactMap { $0 }
    }

    public static func parseStatus(_ output: String) -> (changed: Int, untracked: Int) {
        var changed = 0, untracked = 0
        for line in output.split(separator: "\n") where line.count >= 3 {
            if line.hasPrefix("??") { untracked += 1 } else { changed += 1 }
        }
        return (changed, untracked)
    }
}
