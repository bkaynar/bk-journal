import XCTest
@testable import BKJournalCore

final class RendererTests: XCTestCase {
    let calendar = Support.istanbul

    private func commit(_ hash: String, _ iso: String, _ subject: String, repo: String, branch: String? = "main",
                        files: Int = 1, plus: Int = 1, minus: Int = 0) -> Commit {
        Commit(hash: hash, date: Support.date(iso), subject: subject, branch: branch, filesChanged: files,
               insertions: plus, deletions: minus, repoName: repo, repoPath: "/kod/" + repo)
    }

    private let entries = [ProjectEntry(name: "Trafik360", linkTarget: "10 Projeler/Trafik360/Trafik360")]
    private func link(_ name: String) -> ProjectLink? { ProjectMatcher.link(forRepo: name, entries: entries) }

    func testDailyBlock() {
        let commits = [
            commit("b", "2026-11-10T11:30:00Z", "Harita katmanı eklendi", repo: "trafik360", branch: "ozellik/harita", files: 4, plus: 120, minus: 30),
            commit("a", "2026-11-10T06:05:00Z", "Giriş hatası düzeltildi", repo: "trafik360", plus: 10, minus: 2),
            commit("c", "2026-11-10T07:00:00Z", "README güncellendi", repo: "bk-clean", branch: nil, plus: 5, minus: 5),
        ]
        let section = Renderer.uncommittedSection([
            RepoStatus(name: "trafik360", changed: 3, untracked: 1),
            RepoStatus(name: "anket", changed: 0, untracked: 2),
            RepoStatus(name: "Biore", changed: 1, untracked: 0),
        ])
        let block = Renderer.dailyBlock(commits: commits, uncommittedSection: section, calendar: calendar, link: link)
        XCTAssertEqual(block, """
        <!-- bk-journal:start -->
        ## Çalışma Özeti

        **3 commit, 2 proje, +135 / −37 satır**

        ### bk-clean
        - 10:00 README güncellendi (+5/−5)

        ### [[10 Projeler/Trafik360/Trafik360|Trafik360]]
        - 09:05 Giriş hatası düzeltildi · `main` (+10/−2)
        - 14:30 Harita katmanı eklendi · `ozellik/harita` (+120/−30)

        **Commit edilmemiş değişiklikler**
        - anket: 2 izlenmeyen dosya
        - Biore: 1 değişen dosya
        - trafik360: 3 değişen, 1 izlenmeyen dosya
        <!-- bk-journal:end -->
        """)
    }

    func testEmptyDay() {
        let block = Renderer.dailyBlock(commits: [], uncommittedSection: nil, calendar: calendar, link: link)
        XCTAssertEqual(block, "<!-- bk-journal:start -->\n## Çalışma Özeti\n\nBugün commit yok.\n<!-- bk-journal:end -->")
        XCTAssertNil(Renderer.uncommittedSection([]))
    }

    func testUncommittedSectionRoundTrip() {
        let section = Renderer.uncommittedSection([RepoStatus(name: "anket", changed: 1, untracked: 2)])
        let block = Renderer.dailyBlock(commits: [], uncommittedSection: section, calendar: calendar, link: link)
        XCTAssertEqual(Renderer.extractUncommittedSection(fromBlock: block), section)
        XCTAssertNil(Renderer.extractUncommittedSection(fromBlock: MarkerBlock.wrap("## Çalışma Özeti\n\nBugün commit yok.")))
    }

    func testDangerousSubjectsAreNeutralized() {
        let commits = [
            commit("a", "2026-11-10T06:00:00Z", "kötü <!-- bk-journal:end --> konu", repo: "x"),
            commit("b", "2026-11-10T06:01:00Z", "<% tp.file.delete() %> ve [[Gizli Not]] %%yorum%%", repo: "x", branch: "a`b"),
            commit("c", "2026-11-10T06:02:00Z", "List<String> düzeltildi", repo: "x", branch: "<%dal%>"),
        ]
        let block = Renderer.dailyBlock(commits: commits, uncommittedSection: nil, calendar: calendar, link: link)
        // İşaretler yalnızca birer kez geçer; blok aralığı bozulmaz.
        XCTAssertEqual(block.components(separatedBy: MarkerBlock.end).count, 2)
        XCTAssertEqual(block.components(separatedBy: MarkerBlock.start).count, 2)
        XCTAssertFalse(block.contains("<%"), "Templater kodu çalıştırılabilir halde kalmamalı")
        XCTAssertFalse(block.contains("[[Gizli"))
        XCTAssertFalse(block.contains("%%"))
        XCTAssertTrue(block.contains("List&lt;String> düzeltildi"))
        XCTAssertEqual(try MarkerBlock.range(in: Data(("üst\n" + block + "\nalt").utf8)), 5..<(5 + block.utf8.count))
    }

    func testWeeklyBlock() {
        let week = ISOWeek(containing: Support.day("2026-11-10"), calendar: calendar)
        let commits = [
            commit("a", "2026-11-09T06:05:00Z", "Giriş hatası düzeltildi", repo: "trafik360", files: 2, plus: 10, minus: 2),
            commit("b", "2026-11-09T07:00:00Z", "README güncellendi", repo: "bk-clean", files: 1, plus: 5, minus: 5),
            commit("c", "2026-11-11T11:30:00Z", "Harita katmanı eklendi", repo: "trafik360", files: 4, plus: 120, minus: 30),
            // Pazar 23:30 yerel saat: hâlâ aynı hafta.
            commit("d", "2026-11-15T20:30:00Z", "Hafta sonu düzeltmesi", repo: "trafik360", files: 1, plus: 1, minus: 1),
        ]
        let block = Renderer.weeklyBlock(week: week, commits: commits, calendar: calendar, link: link)
        XCTAssertEqual(block, """
        <!-- bk-journal:start -->
        ## Haftalık Çalışma Raporu · 2026-W46

        **09.11.2026 – 15.11.2026:** 4 commit, 2 proje, +136 / −38 satır

        ### Günlere göre

        | Gün | Commit | Proje | Eklenen | Silinen |
        | --- | ---: | ---: | ---: | ---: |
        | 09.11 Pazartesi | 2 | 2 | +15 | −7 |
        | 10.11 Salı | – | – | – | – |
        | 11.11 Çarşamba | 1 | 1 | +120 | −30 |
        | 12.11 Perşembe | – | – | – | – |
        | 13.11 Cuma | – | – | – | – |
        | 14.11 Cumartesi | – | – | – | – |
        | 15.11 Pazar | 1 | 1 | +1 | −1 |

        ### Projelere göre

        | Proje | Commit | Değişen dosya | Eklenen | Silinen |
        | --- | ---: | ---: | ---: | ---: |
        | bk-clean | 1 | 1 | +5 | −5 |
        | trafik360 | 3 | 7 | +131 | −33 |

        ### Yapılan işler

        #### bk-clean
        - 09.11 Pzt: README güncellendi

        #### [[10 Projeler/Trafik360/Trafik360|Trafik360]]
        - 09.11 Pzt: Giriş hatası düzeltildi
        - 11.11 Çar: Harita katmanı eklendi
        - 15.11 Paz: Hafta sonu düzeltmesi
        <!-- bk-journal:end -->
        """)
    }

    func testEmptyWeek() {
        let week = ISOWeek(containing: Support.day("2026-11-10"), calendar: calendar)
        let block = Renderer.weeklyBlock(week: week, commits: [], calendar: calendar, link: link)
        XCTAssertTrue(block.contains("**09.11.2026 – 15.11.2026:** Bu hafta commit yok."))
    }
}
