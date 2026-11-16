import XCTest
@testable import BKJournalCore

final class GitCollectorTests: XCTestCase {
    var root: URL!
    let calendar = Support.istanbul
    let collector = Support.collector

    override func setUpWithError() throws { root = try Support.makeTempDir() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func collect(_ day: String, repos: [Repo]? = nil, identity: Identity = Support.identity) -> [Commit] {
        let d = Support.day(day)
        return collector.collect(
            repos: repos ?? collector.discoverRepos(roots: [root]),
            from: d.start(in: calendar), to: d.adding(days: 1, calendar: calendar).start(in: calendar), identity: identity)
    }

    // MARK: Ayrıştırma

    func testParseLogWithNumstat() {
        let rs = "\u{1e}", fs = "\u{1f}"
        let output = """
        \(rs)aaa111\(fs)1794300000\(fs)Deneme Kullanıcı\(fs)ben@ornek.dev\(fs)refs/heads/main\(fs)Giriş ekranı düzeltildi

        10\t2\tSources/a.swift
        0\t5\tREADME.md
        -\t-\tlogo.png
        3\t0\tyol/{eski => yeni}/dosya.txt
        \(rs)bbb222\(fs)1794290000\(fs)Başka Biri\(fs)baska@ornek.dev\(fs)refs/remotes/origin/dev\(fs)
        \(rs)ccc333\(fs)1794280000\(fs)A\(fs)a@b.c\(fs)refs/tags/v1\(fs)konu\(fs)içinde ayraç

        1\t1\tx

        """
        let commits = GitCollector.parseLog(output)
        XCTAssertEqual(commits.count, 3)
        XCTAssertEqual(commits[0].hash, "aaa111")
        XCTAssertEqual(commits[0].timestamp, 1794300000)
        XCTAssertEqual(commits[0].subject, "Giriş ekranı düzeltildi")
        XCTAssertEqual(commits[0].filesChanged, 4)
        XCTAssertEqual(commits[0].insertions, 13)
        XCTAssertEqual(commits[0].deletions, 7)
        XCTAssertEqual(commits[1].subject, "")
        XCTAssertEqual(commits[1].filesChanged, 0)
        XCTAssertEqual(commits[1].authorEmail, "baska@ornek.dev")
        XCTAssertEqual(commits[2].subject, "konu\(fs)içinde ayraç")
        XCTAssertEqual(commits[2].insertions, 1)
        XCTAssertEqual(GitCollector.parseLog(""), [])
    }

    func testBranchNames() {
        XCTAssertEqual(GitCollector.branchName(fromRef: "refs/heads/main"), "main")
        XCTAssertEqual(GitCollector.branchName(fromRef: "refs/heads/ozellik/giriş"), "ozellik/giriş")
        XCTAssertEqual(GitCollector.branchName(fromRef: "refs/remotes/origin/dev"), "origin/dev")
        XCTAssertNil(GitCollector.branchName(fromRef: "refs/remotes/origin/HEAD"))
        XCTAssertNil(GitCollector.branchName(fromRef: "refs/tags/v1"))
        XCTAssertNil(GitCollector.branchName(fromRef: "HEAD"))
        XCTAssertNil(GitCollector.branchName(fromRef: ""))
    }

    func testParseStatus() {
        let (changed, untracked) = GitCollector.parseStatus(" M a.swift\nA  b.swift\n?? yeni.txt\n?? klasör/\nR  x -> y\n")
        XCTAssertEqual(changed, 3)
        XCTAssertEqual(untracked, 2)
    }

    func testIdentityMatching() {
        let identity = Identity(emails: ["Ben@Ornek.dev", " ek@ornek.dev "], names: ["Deneme Kullanıcı"])
        XCTAssertTrue(identity.matches(name: "x", email: "ben@ornek.DEV"))
        XCTAssertTrue(identity.matches(name: "x", email: "ek@ornek.dev"))
        XCTAssertTrue(identity.matches(name: "deneme kullanıcı", email: "baska@adres.com"))
        XCTAssertFalse(identity.matches(name: "Başka Biri", email: "baska@ornek.dev"))
        XCTAssertTrue(Identity(emails: [""], names: []).isEmpty)
    }

    // MARK: Gerçek (geçici) depolar

    func testDayBoundariesUseLocalTimeZone() throws {
        let repo = root.appendingPathComponent("proje")
        try Support.initRepo(repo)
        // İstanbul UTC+3. Hedef gün: 2026-11-10.
        try Support.commit(repo, file: "a", content: "1\n", message: "önceki gün 23:59", date: "2026-11-09T23:59:30+03:00")
        try Support.commit(repo, file: "a", content: "2\n", message: "gün başı 00:00", date: "2026-11-10T00:00:00+03:00")
        // UTC'ye göre 9 Kasım, yerelde 10 Kasım 00:30.
        try Support.commit(repo, file: "a", content: "3\n", message: "utc önceki gün", date: "2026-11-09T21:30:00+00:00")
        try Support.commit(repo, file: "a", content: "4\n", message: "öğlen", date: "2026-11-10T12:15:00+03:00")
        try Support.commit(repo, file: "a", content: "5\n", message: "gün sonu 23:59", date: "2026-11-10T23:59:59+03:00")
        // UTC'ye göre 10 Kasım, yerelde 11 Kasım 01:30.
        try Support.commit(repo, file: "a", content: "6\n", message: "utc aynı gün ama yerelde ertesi", date: "2026-11-10T22:30:00+00:00")
        try Support.commit(repo, file: "a", content: "7\n", message: "ertesi gün 00:00", date: "2026-11-11T00:00:00+03:00")

        let commits = collect("2026-11-10")
        XCTAssertEqual(commits.map(\.subject), ["gün başı 00:00", "utc önceki gün", "öğlen", "gün sonu 23:59"])
        XCTAssertEqual(commits.map { Renderer.time($0.date, calendar: calendar) }, ["00:00", "00:30", "12:15", "23:59"])
        XCTAssertEqual(collect("2026-11-09").map(\.subject), ["önceki gün 23:59"])
        XCTAssertEqual(collect("2026-11-11").map(\.subject), ["ertesi gün 00:00", "utc aynı gün ama yerelde ertesi"])
        XCTAssertEqual(collect("2026-11-12"), [])
        XCTAssertEqual(commits.first?.repoName, "proje")
        XCTAssertEqual(commits.first?.branch, "main")
    }

    func testAuthorDateIsUsedNotCommitterDate() throws {
        let repo = root.appendingPathComponent("proje")
        try Support.initRepo(repo)
        try Support.write("x\n", to: repo.appendingPathComponent("a"))
        Support.git(["add", "-A"], in: repo)
        // 10 Kasım'da yazılmış, 12 Kasım'da yeniden düzenlenmiş (rebase/amend) bir commit.
        var env = Support.gitEnvironment
        env["GIT_AUTHOR_DATE"] = "2026-11-10T15:00:00+03:00"
        env["GIT_COMMITTER_DATE"] = "2026-11-12T09:00:00+03:00"
        let out = Shell.run("/usr/bin/git", ["-c", "user.name=\(Support.me.name)", "-c", "user.email=\(Support.me.email)", "commit", "-q", "-m", "sonradan düzenlendi"], cwd: repo, environment: env)
        XCTAssertTrue(out.succeeded, out.stderr)
        XCTAssertEqual(collect("2026-11-10").map(\.subject), ["sonradan düzenlendi"])
        XCTAssertEqual(collect("2026-11-12"), [])
    }

    func testAuthorFiltering() throws {
        let repo = root.appendingPathComponent("proje")
        try Support.initRepo(repo)
        let day = "2026-11-10T10:0"
        try Support.commit(repo, file: "a", content: "1\n", message: "benim", date: day + "0:00+03:00")
        try Support.commit(repo, file: "a", content: "2\n", message: "başkasının", date: day + "1:00+03:00", author: Support.other)
        try Support.commit(repo, file: "a", content: "3\n", message: "adım aynı e-posta farklı", date: day + "2:00+03:00",
                           author: (Support.me.name, "eski@adres.com"))
        try Support.commit(repo, file: "a", content: "4\n", message: "ek e-posta", date: day + "3:00+03:00",
                           author: ("Takma Ad", "ek@ornek.dev"))
        try Support.commit(repo, file: "a", content: "5\n", message: "büyük harfli e-posta", date: day + "4:00+03:00",
                           author: ("Takma Ad", "BEN@ornek.dev"))

        XCTAssertEqual(collect("2026-11-10").map(\.subject), ["benim", "adım aynı e-posta farklı", "büyük harfli e-posta"])
        let withExtra = Identity(emails: [Support.me.email, "ek@ornek.dev"], names: [])
        XCTAssertEqual(collect("2026-11-10", identity: withExtra).map(\.subject), ["benim", "ek e-posta", "büyük harfli e-posta"])
    }

    func testNumstatFromRealCommits() throws {
        let repo = root.appendingPathComponent("proje")
        try Support.initRepo(repo)
        try Support.commit(repo, file: "a.txt", content: "bir\niki\nüç\n", message: "ilk", date: "2026-11-10T09:00:00+03:00")
        try Support.write("bir\nİKİ\nüç\ndört\n", to: repo.appendingPathComponent("a.txt"))
        try Support.write("yeni\n", to: repo.appendingPathComponent("klasör/b ç.txt"))
        try Data([0, 1, 2, 0, 255, 254, 0, 0]).write(to: repo.appendingPathComponent("ikili.bin"))
        Support.git(["add", "-A"], in: repo)
        Support.git(["commit", "-q", "-m", "ikinci"], in: repo, date: "2026-11-10T10:00:00+03:00")

        let commits = collect("2026-11-10")
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual([commits[0].filesChanged, commits[0].insertions, commits[0].deletions], [1, 3, 0])
        // a.txt: +2/−1, yeni dosya: +1, ikili dosya: sayılmaz ama dosya olarak sayılır.
        XCTAssertEqual([commits[1].filesChanged, commits[1].insertions, commits[1].deletions], [3, 3, 1])
    }

    func testWorktreeIsNotCountedTwice() throws {
        let repo = root.appendingPathComponent("trafik360")
        try Support.initRepo(repo)
        try Support.commit(repo, file: "a", content: "1\n", message: "ana dal", date: "2026-11-10T09:00:00+03:00")
        // Biri kökün hemen altında, biri deponun içinde iki bağlı worktree.
        let sibling = root.appendingPathComponent("trafik360-ozellik")
        Support.git(["worktree", "add", "-q", "-b", "ozellik", sibling.path], in: repo)
        let nested = repo.appendingPathComponent("worktrees/deneme")
        Support.git(["worktree", "add", "-q", "-b", "deneme", nested.path], in: repo)
        try Support.commit(sibling, file: "b", content: "1\n", message: "worktree içinde", date: "2026-11-10T10:00:00+03:00")

        let repos = collector.discoverRepos(roots: [root])
        XCTAssertEqual(repos.map(\.name), ["trafik360"], "worktree'ler ayrı depo sayılmamalı")
        XCTAssertEqual(repos.first?.path.path, repo.path)

        let commits = collect("2026-11-10", repos: repos)
        XCTAssertEqual(commits.map(\.subject), ["ana dal", "worktree içinde"])
        XCTAssertEqual(commits.map(\.branch), ["main", "ozellik"])
        XCTAssertEqual(Set(commits.map(\.hash)).count, 2)
    }

    func testOnlyWorktreeFoundStillNamedAfterMainRepo() throws {
        // Ana depo arama kökünün dışında, yalnızca worktree kökün içinde.
        let outside = try Support.makeTempDir()
        defer { try? FileManager.default.removeItem(at: outside) }
        let repo = outside.appendingPathComponent("asıl-proje")
        try Support.initRepo(repo)
        try Support.commit(repo, file: "a", content: "1\n", message: "ilk", date: "2026-11-10T09:00:00+03:00")
        Support.git(["worktree", "add", "-q", "-b", "dal", root.appendingPathComponent("gecici-kopya").path], in: repo)
        let repos = collector.discoverRepos(roots: [root])
        XCTAssertEqual(repos.map(\.name), ["asıl-proje"])
    }

    func testSameCommitInTwoClonesCountedOnce() throws {
        let repo = root.appendingPathComponent("b-asıl")
        try Support.initRepo(repo)
        try Support.commit(repo, file: "a", content: "1\n", message: "ortak commit", date: "2026-11-10T09:00:00+03:00")
        // Ayrı nesne veritabanı olan tam kopya; yerel dalı silinip yalnızca origin/main bırakılır.
        let clone = root.appendingPathComponent("a-kopya")
        Support.git(["clone", "-q", "--no-hardlinks", repo.path, clone.path], in: root)
        Support.git(["checkout", "-q", "--detach"], in: clone)
        Support.git(["branch", "-q", "-D", "main"], in: clone)

        let repos = collector.discoverRepos(roots: [root])
        XCTAssertEqual(repos.map(\.name), ["a-kopya", "b-asıl"])
        let commits = collect("2026-11-10", repos: repos)
        XCTAssertEqual(commits.count, 1)
        // Yerel dalında bulunduğu depo tercih edilir.
        XCTAssertEqual(commits.first?.repoName, "b-asıl")
        XCTAssertEqual(commits.first?.branch, "main")
    }

    func testAllBranchesMergesAndStash() throws {
        let repo = root.appendingPathComponent("proje")
        try Support.initRepo(repo)
        try Support.commit(repo, file: "a", content: "1\n", message: "main 1", date: "2026-11-10T09:00:00+03:00")
        Support.git(["checkout", "-q", "-b", "ozellik/giris"], in: repo)
        try Support.commit(repo, file: "b", content: "1\n", message: "dalda", date: "2026-11-10T10:00:00+03:00")
        Support.git(["checkout", "-q", "main"], in: repo)
        try Support.commit(repo, file: "c", content: "1\n", message: "main 2", date: "2026-11-10T11:00:00+03:00")
        Support.git(["merge", "-q", "--no-ff", "-m", "Merge branch 'ozellik/giris'", "ozellik/giris"], in: repo, date: "2026-11-10T12:00:00+03:00")
        // Birleştirilmemiş, yalnızca kendi dalında duran commit.
        Support.git(["checkout", "-q", "-b", "deneysel"], in: repo)
        try Support.commit(repo, file: "d", content: "1\n", message: "yalnızca dalda", date: "2026-11-10T13:00:00+03:00")
        Support.git(["checkout", "-q", "main"], in: repo)
        // Stash kayıtları commit sayılmaz.
        try Support.write("değişti\n", to: repo.appendingPathComponent("a"))
        Support.git(["stash", "-q"], in: repo, date: "2026-11-10T14:00:00+03:00")

        let commits = collect("2026-11-10")
        XCTAssertEqual(commits.map(\.subject), ["main 1", "dalda", "main 2", "yalnızca dalda"])
        XCTAssertEqual(commits.last?.branch, "deneysel")
    }

    func testDiscoveryDepthAndSkippedFolders() throws {
        try Support.initRepo(root.appendingPathComponent("bir"))
        try Support.initRepo(root.appendingPathComponent("grup/iki"))
        try Support.initRepo(root.appendingPathComponent("grup/alt/üç"))
        try Support.initRepo(root.appendingPathComponent("grup/alt/derin/dört"))        // derinlik 4
        try Support.initRepo(root.appendingPathComponent("bir/node_modules/paket"))
        try Support.initRepo(root.appendingPathComponent("bir/.build/checkouts/bagimlilik"))
        try Support.initRepo(root.appendingPathComponent("grup/Pods/Kutuphane"))
        try Support.initRepo(root.appendingPathComponent("build/cikti"))
        try Support.initRepo(root.appendingPathComponent(".gizli/depo"))

        let repos = collector.discoverRepos(roots: [root, root.appendingPathComponent("olmayan")])
        XCTAssertEqual(repos.map(\.name), ["bir", "iki", "üç"])
        XCTAssertEqual(collector.discoverRepos(roots: [root], maxDepth: 1).map(\.name), ["bir"])
        XCTAssertEqual(collector.discoverRepos(roots: [root.appendingPathComponent("olmayan")]), [])
    }

    func testUncommittedCounts() throws {
        let clean = root.appendingPathComponent("temiz")
        try Support.initRepo(clean)
        try Support.commit(clean, file: "a", content: "1\n", message: "ilk", date: "2026-11-10T09:00:00+03:00")
        let dirty = root.appendingPathComponent("kirli")
        try Support.initRepo(dirty)
        try Support.commit(dirty, file: "a", content: "1\n", message: "ilk", date: "2026-11-10T09:00:00+03:00")
        try Support.commit(dirty, file: "b", content: "1\n", message: "iki", date: "2026-11-10T09:01:00+03:00")
        try Support.write("değişti\n", to: dirty.appendingPathComponent("a"))
        try Support.write("değişti\n", to: dirty.appendingPathComponent("b"))
        try Support.write("yeni\n", to: dirty.appendingPathComponent("yeni.txt"))

        let statuses = collector.uncommitted(repos: collector.discoverRepos(roots: [root]))
        XCTAssertEqual(statuses, [RepoStatus(name: "kirli", changed: 2, untracked: 1)])
    }

    func testEmptyRepoGivesNoCommits() throws {
        try Support.initRepo(root.appendingPathComponent("boş"))
        XCTAssertEqual(collect("2026-11-10"), [])
    }
}
