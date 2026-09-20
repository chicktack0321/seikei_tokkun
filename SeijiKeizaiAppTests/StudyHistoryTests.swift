import XCTest
@testable import SeijiKeizaiApp

/// 学習履歴の集計。
///
/// 日付の扱いを間違えると「グラフが1日ずれる」「連続日数が途切れる」といった
/// 見つけにくい不具合になるため、純粋関数として切り出してテストする。
final class StudyHistoryTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func log(
        _ year: Int, _ month: Int, _ day: Int,
        studied: Int = 0,
        correct: Int = 0,
        attempts: Int = 0,
        mastered: Int = 0,
        breakdown: [String: Int] = [:]
    ) -> StudyLog {
        StudyLog(
            date: calendar.startOfDay(for: date(year, month, day)),
            studiedQuestionCount: studied,
            correctCount: correct,
            attemptCount: attempts,
            masteredQuestionCount: mastered,
            masteredBreakdown: breakdown
        )
    }

    /// 学習していない日を飛ばすと横軸が詰まって推移が読めなくなるため、必ず0で埋める
    func testSeriesFillsMissingDaysWithZero() {
        let logs = [
            log(2026, 4, 8, studied: 10, correct: 8, attempts: 10),
            log(2026, 4, 10, studied: 5, correct: 3, attempts: 5)
        ]

        let series = StudyHistory.series(
            logs: logs,
            days: 5,
            endingOn: date(2026, 4, 10),
            calendar: calendar
        )

        XCTAssertEqual(series.count, 5)
        XCTAssertEqual(series.map(\.studiedQuestionCount), [0, 0, 10, 0, 5])
        // 古い順に並ぶ
        XCTAssertEqual(series.first?.date, calendar.startOfDay(for: date(2026, 4, 6)))
        XCTAssertEqual(series.last?.date, calendar.startOfDay(for: date(2026, 4, 10)))
    }

    /// 期間より前の習熟度を引き継ぐ。
    /// 引き継がないと、期間内に学習日が無いときに折れ線が0から始まり、
    /// 実際には習得済みの問題が消えたように見える。
    func testSeriesCarriesMasteredCountFromBeforeRange() {
        let logs = [
            log(2026, 4, 1, studied: 20, attempts: 20, mastered: 30),
            log(2026, 4, 9, studied: 5, attempts: 5, mastered: 35)
        ]

        let series = StudyHistory.series(
            logs: logs,
            days: 3,
            endingOn: date(2026, 4, 10),
            calendar: calendar
        )

        XCTAssertEqual(series.map(\.masteredQuestionCount), [30, 35, 35])
    }

    /// 当日まだ学習していなくても、前日までの記録は途切れたことにしない。
    /// 厳密に当日で切ると、朝アプリを開いた瞬間に0日と表示され継続の動機付けにならない。
    func testStreakCountsFromYesterdayWhenTodayHasNoRecord() {
        let logs = [
            log(2026, 4, 7, studied: 3, attempts: 3),
            log(2026, 4, 8, studied: 3, attempts: 3),
            log(2026, 4, 9, studied: 3, attempts: 3)
        ]

        let streak = StudyHistory.currentStreak(
            logs: logs,
            today: date(2026, 4, 10),
            calendar: calendar
        )

        XCTAssertEqual(streak, 3)
    }

    func testStreakIncludesTodayWhenStudied() {
        let logs = [
            log(2026, 4, 9, studied: 3, attempts: 3),
            log(2026, 4, 10, studied: 3, attempts: 3)
        ]

        XCTAssertEqual(
            StudyHistory.currentStreak(logs: logs, today: date(2026, 4, 10), calendar: calendar),
            2
        )
    }

    /// 2日以上空くと連続は切れる
    func testStreakBreaksAfterTwoMissedDays() {
        let logs = [
            log(2026, 4, 5, studied: 3, attempts: 3),
            log(2026, 4, 6, studied: 3, attempts: 3)
        ]

        XCTAssertEqual(
            StudyHistory.currentStreak(logs: logs, today: date(2026, 4, 10), calendar: calendar),
            0
        )
    }

    /// 解答数が0の日は「学習した日」に数えない。
    ///
    /// `StudyLog` の行は解答時以外にも作られうる（習熟度スナップショットの焼き直しなど）ので、
    /// 行の有無ではなく解答数で判定する必要がある。
    func testStreakIgnoresDaysWithZeroAnswers() {
        // 4/7 と 4/9 に解答があり、4/8 は行はあるが0問。
        // 0問の日を学習日として数えると、実際は途切れているのに3日連続に見えてしまう。
        let logs = [
            log(2026, 4, 7, studied: 3, attempts: 3),
            log(2026, 4, 8, studied: 0, attempts: 0),
            log(2026, 4, 9, studied: 3, attempts: 3)
        ]

        XCTAssertEqual(
            StudyHistory.currentStreak(logs: logs, today: date(2026, 4, 9), calendar: calendar),
            1,
            "0問の日は連続を繋がない"
        )
    }

    /// 期間の正答率は解答数で重み付けする。
    /// 日ごとの正答率を単純平均すると、1問だけ解いた日が重く効いてしまう。
    func testOverallAccuracyIsWeightedByAttempts() {
        let series = [
            DailyStudy(date: date(2026, 4, 9), studiedQuestionCount: 1, correctCount: 1, attemptCount: 1),
            DailyStudy(date: date(2026, 4, 10), studiedQuestionCount: 99, correctCount: 50, attemptCount: 99)
        ]

        let accuracy = StudyHistory.overallAccuracy(in: series)

        // 単純平均なら (100% + 50.5%) / 2 = 75.3% になるが、重み付けでは 51/100 = 51%
        XCTAssertEqual(accuracy, 51.0 / 100.0, accuracy: 0.001)
    }

    func testOverallAccuracyWithNoAttempts() {
        let series = [
            DailyStudy(date: date(2026, 4, 10), studiedQuestionCount: 0, correctCount: 0, attemptCount: 0)
        ]
        XCTAssertEqual(StudyHistory.overallAccuracy(in: series), 0, "ゼロ除算しない")
    }

    /// 週まとめは解答数を合計し、習熟度はその週の最終値を取る。
    /// 習熟度は残高であって合計ではないため、足し上げると桁が変わってしまう。
    func testWeeklyAggregation() {
        let daily = (1...14).map { day in
            DailyStudy(
                date: calendar.startOfDay(for: date(2026, 4, day)),
                studiedQuestionCount: 1,
                correctCount: 1,
                attemptCount: 1,
                masteredQuestionCount: day
            )
        }

        let weekly = StudyHistory.weekly(from: daily, calendar: calendar)

        XCTAssertGreaterThan(weekly.count, 1)
        XCTAssertEqual(weekly.reduce(0) { $0 + $1.studiedQuestionCount }, 14, "解答数は合計される")
        XCTAssertEqual(weekly.last?.masteredQuestionCount, 14, "習熟度は週の最終値")
    }

    func testTotalAttempts() {
        let series = [
            DailyStudy(date: date(2026, 4, 9), studiedQuestionCount: 5, correctCount: 4, attemptCount: 5),
            DailyStudy(date: date(2026, 4, 10), studiedQuestionCount: 3, correctCount: 3, attemptCount: 3)
        ]
        XCTAssertEqual(StudyHistory.totalAttempts(in: series), 8)
    }
}
