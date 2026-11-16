import XCTest
@testable import BKJournalCore

final class DatesTests: XCTestCase {
    let calendar = Support.istanbul

    func testLocalDayParsing() {
        XCTAssertEqual(LocalDay(string: "2026-11-16"), LocalDay(year: 2026, month: 11, day: 16))
        XCTAssertNil(LocalDay(string: "2026-02-30"))
        XCTAssertNil(LocalDay(string: "2026-13-01"))
        XCTAssertNil(LocalDay(string: "16.11.2026"))
        XCTAssertNil(LocalDay(string: "2026-1-5"))
        XCTAssertEqual(LocalDay(string: "2024-02-29")?.description, "2024-02-29")
    }

    func testLocalDayUsesCalendarTimeZone() {
        // 21:30 UTC, İstanbul'da ertesi günün 00:30'udur.
        let instant = Support.date("2026-11-09T21:30:00Z")
        XCTAssertEqual(LocalDay(date: instant, calendar: calendar), Support.day("2026-11-10"))
        XCTAssertEqual(Support.day("2026-11-10").start(in: calendar), Support.date("2026-11-09T21:00:00Z"))
    }

    func testAddingDaysAcrossMonthAndYear() {
        XCTAssertEqual(Support.day("2026-12-31").adding(days: 1, calendar: calendar), Support.day("2027-01-01"))
        XCTAssertEqual(Support.day("2026-03-01").adding(days: -1, calendar: calendar), Support.day("2026-02-28"))
    }

    func testAddingDaysAcrossDaylightSaving() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        XCTAssertEqual(Support.day("2026-03-28").adding(days: 2, calendar: berlin), Support.day("2026-03-30"))
        XCTAssertEqual(Support.day("2026-10-24").adding(days: 2, calendar: berlin), Support.day("2026-10-26"))
    }

    func testISOWeek() {
        func week(_ text: String) -> ISOWeek { ISOWeek(containing: Support.day(text), calendar: calendar) }
        XCTAssertEqual(week("2026-11-16").label, "2026-W47")   // Pazartesi
        XCTAssertEqual(week("2026-11-22").label, "2026-W47")   // Pazar
        XCTAssertEqual(week("2026-11-23").label, "2026-W48")
        XCTAssertEqual(week("2026-11-18").monday, Support.day("2026-11-16"))
        // Yıl sınırları: hafta yılı takvim yılından farklı olabilir.
        XCTAssertEqual(week("2027-01-01").label, "2026-W53")
        XCTAssertEqual(week("2027-01-03").monday, Support.day("2026-12-28"))
        XCTAssertEqual(week("2024-12-30").label, "2025-W01")
        XCTAssertEqual(week("2021-01-03").label, "2020-W53")
        XCTAssertEqual(week("2026-01-01").label, "2026-W01")
        let days = week("2026-11-19").days(calendar: calendar)
        XCTAssertEqual(days.first, Support.day("2026-11-16"))
        XCTAssertEqual(days.last, Support.day("2026-11-22"))
        XCTAssertEqual(days.count, 7)
    }

    func testMomentFormatTokens() {
        let date = Support.date("2026-03-05T06:07:08Z") // İstanbul: 09:07:08
        func f(_ pattern: String) -> String? { MomentFormat.format(date, pattern: pattern, calendar: calendar) }
        XCTAssertEqual(f("YYYY-MM-DD"), "2026-03-05")
        XCTAssertEqual(f("DD.MM.YYYY"), "05.03.2026")
        XCTAssertEqual(f("D.M.YY"), "5.3.26")
        XCTAssertEqual(f("YYYY/MM/YYYY-MM-DD"), "2026/03/2026-03-05")
        XCTAssertEqual(f("YYYYMMDD"), "20260305")
        XCTAssertEqual(f("HH:mm:ss"), "09:07:08")
        XCTAssertEqual(f("GGGG-[W]WW"), "2026-W10")
        XCTAssertEqual(f("[Gün] DD"), "Gün 05")
        // Dile bağlı ya da bilinmeyen belirteçler desteklenmez.
        XCTAssertNil(f("dddd, D MMMM YYYY"))
        XCTAssertNil(f("YYYY-MM-Do"))
        XCTAssertNil(f("[kapanmamış"))
    }

    func testMomentFormatFallback() {
        let date = Support.date("2026-03-05T06:07:08Z")
        XCTAssertEqual(MomentFormat.formatOrFallback(date, pattern: "dddd D MMMM", calendar: calendar), "2026-03-05")
        XCTAssertEqual(MomentFormat.formatOrFallback(date, pattern: "", calendar: calendar), "2026-03-05")
        XCTAssertEqual(MomentFormat.formatOrFallback(date, pattern: "DD-MM-YYYY", calendar: calendar), "05-03-2026")
    }

    func testCatchUpDays() {
        let today = Support.day("2026-11-16")
        func days(_ last: String?) -> [String] {
            CatchUp.days(lastSuccessful: last.map(Support.day), today: today, calendar: calendar).map(\.description)
        }
        XCTAssertEqual(days(nil), ["2026-11-16"])
        XCTAssertEqual(days("2026-11-16"), ["2026-11-16"])
        XCTAssertEqual(days("2026-11-14"), ["2026-11-14", "2026-11-15", "2026-11-16"])
        // 7 gün sınırı.
        XCTAssertEqual(days("2026-10-01"), ["2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15", "2026-11-16"])
        // Saat geri alınmışsa yalnızca bugün.
        XCTAssertEqual(days("2026-12-01"), ["2026-11-16"])
    }

    func testCatchUpWeeks() {
        func weeks(_ days: [String], today: String) -> [String] {
            CatchUp.weeks(for: days.map(Support.day), today: Support.day(today), calendar: calendar).map(\.label)
        }
        // Pazartesi çalışması: Pazar günü de işlendiği için biten hafta yazılır.
        XCTAssertEqual(weeks(["2026-11-15", "2026-11-16"], today: "2026-11-16"), ["2026-W46"])
        // Hafta ortası: biten hafta yok.
        XCTAssertEqual(weeks(["2026-11-17", "2026-11-18"], today: "2026-11-18"), [])
        // Pazar akşamı: içinde bulunulan hafta da yazılır.
        XCTAssertEqual(weeks(["2026-11-21", "2026-11-22"], today: "2026-11-22"), ["2026-W47"])
        // İki haftaya yayılan tamamlama.
        XCTAssertEqual(weeks(["2026-11-06", "2026-11-09", "2026-11-16"], today: "2026-11-16"), ["2026-W45", "2026-W46"])
    }

    func testScheduleTimeParsing() throws {
        var config = Config()
        XCTAssertEqual(try config.scheduleHourMinute().hour, 23)
        XCTAssertEqual(try config.scheduleHourMinute().minute, 30)
        config.scheduleTime = "7:05"
        XCTAssertEqual(try config.scheduleHourMinute().hour, 7)
        config.scheduleTime = "25:00"
        XCTAssertThrowsError(try config.scheduleHourMinute())
        config.scheduleTime = "akşam"
        XCTAssertThrowsError(try config.scheduleHourMinute())
    }
}
