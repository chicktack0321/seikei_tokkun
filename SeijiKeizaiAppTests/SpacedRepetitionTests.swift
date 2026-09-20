import XCTest
@testable import SeijiKeizaiApp

/// 間隔反復の判定。
///
/// ここが壊れても画面上は正常に見え、学習効果だけが静かに落ちるためテストで固定する。
final class SpacedRepetitionTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testInitialStatusIsNotStudied() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        XCTAssertEqual(progress.status(), .notStudied)
        // 未出題は「いつでも出題してよい」なので期限切れ扱いにする
        XCTAssertTrue(progress.isDue())
    }

    func testCorrectAnswerAdvancesBox() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        let day1 = date(2026, 4, 1)

        progress.record(isCorrect: true, reviewedAt: day1, calendar: calendar)

        XCTAssertEqual(progress.reviewBox, 1)
        XCTAssertEqual(progress.correctCount, 1)
        XCTAssertEqual(progress.attemptCount, 1)
        // box=1 は間隔1日
        XCTAssertEqual(progress.nextReviewAt, calendar.startOfDay(for: date(2026, 4, 2)))
    }

    func testWrongAnswerResetsBoxToZero() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        let day1 = date(2026, 4, 1)

        // 3回正解して box=3（習得済み）まで進める
        for _ in 0..<3 {
            progress.record(isCorrect: true, reviewedAt: day1, calendar: calendar)
        }
        XCTAssertEqual(progress.status(at: day1), .memorized)

        progress.record(isCorrect: false, reviewedAt: day1, calendar: calendar)

        XCTAssertEqual(progress.reviewBox, 0, "間違えたら最短間隔に戻る")
        // box=0 は間隔0日 = その日のうちに再出題される
        XCTAssertEqual(progress.nextReviewAt, calendar.startOfDay(for: day1))
        XCTAssertTrue(progress.isDue(at: day1))
    }

    func testMemorizedRequiresSevenDayInterval() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        let day1 = date(2026, 4, 1)

        // 1回正解しただけでは「習得済み」にしない。
        // 翌日には解けない問題まで習得扱いにすると、習熟度の表示が実態と乖離する。
        progress.record(isCorrect: true, reviewedAt: day1, calendar: calendar)
        XCTAssertEqual(progress.status(at: day1), .learning)

        progress.record(isCorrect: true, reviewedAt: day1, calendar: calendar)
        XCTAssertEqual(progress.status(at: day1), .learning, "box=2（間隔3日）はまだ学習中")

        progress.record(isCorrect: true, reviewedAt: day1, calendar: calendar)
        XCTAssertEqual(progress.reviewBox, UserProgress.masteredBox)
        XCTAssertEqual(progress.status(at: day1), .memorized, "box=3（間隔7日）で習得済み")
    }

    func testStatusBecomesNeedsReviewWhenDuePasses() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        let day1 = date(2026, 4, 1)

        for _ in 0..<3 {
            progress.record(isCorrect: true, reviewedAt: day1, calendar: calendar)
        }
        XCTAssertEqual(progress.status(at: day1), .memorized)

        // 7日後に期限が来る。過ぎれば習得済みではなく要復習になる
        XCTAssertEqual(progress.status(at: date(2026, 4, 7)), .memorized)
        XCTAssertEqual(progress.status(at: date(2026, 4, 8)), .needsReview)
    }

    /// 朝に解いても夜に解いても、期限は同じ日付に来る必要がある。
    /// 時刻で丸めていないと「昨日の夜やった問題が今日の朝はまだ出ない」という挙動になる。
    func testNextReviewIsRoundedToDay() {
        let morning = UserProgress(questionId: "SEI_KINYU_0001")
        let night = UserProgress(questionId: "SEI_KINYU_0002")

        morning.record(isCorrect: true, reviewedAt: date(2026, 4, 1, hour: 7), calendar: calendar)
        night.record(isCorrect: true, reviewedAt: date(2026, 4, 1, hour: 23), calendar: calendar)

        XCTAssertEqual(morning.nextReviewAt, night.nextReviewAt)
    }

    func testIntervalTableProgression() {
        XCTAssertEqual(UserProgress.intervalDays(forBox: 0), 0)
        XCTAssertEqual(UserProgress.intervalDays(forBox: 1), 1)
        XCTAssertEqual(UserProgress.intervalDays(forBox: 2), 3)
        XCTAssertEqual(UserProgress.intervalDays(forBox: 3), 7)
        XCTAssertEqual(UserProgress.intervalDays(forBox: 4), 14)
        XCTAssertEqual(UserProgress.intervalDays(forBox: 5), 30)
        // 範囲外は端に丸める（保存データが壊れていても落ちない）
        XCTAssertEqual(UserProgress.intervalDays(forBox: 99), 30)
        XCTAssertEqual(UserProgress.intervalDays(forBox: -1), 0)
    }

    func testBoxDoesNotExceedMaximum() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        for _ in 0..<20 {
            progress.record(isCorrect: true, reviewedAt: date(2026, 4, 1), calendar: calendar)
        }
        XCTAssertEqual(progress.reviewBox, UserProgress.maxReviewBox)
    }

    func testMarkAsMemorizedSkipsToMasteredBox() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        let day1 = date(2026, 4, 1)

        progress.markAsMemorized(at: day1, calendar: calendar)

        XCTAssertEqual(progress.reviewBox, UserProgress.masteredBox)
        XCTAssertEqual(progress.status(at: day1), .memorized)
        // 未出題のまま習得済みにすると status が notStudied を返してしまうので、
        // 解答回数を1にしておく必要がある
        XCTAssertEqual(progress.attemptCount, 1)
    }

    func testMarkForReviewResetsToDue() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        let day1 = date(2026, 4, 1)

        for _ in 0..<3 {
            progress.record(isCorrect: true, reviewedAt: day1, calendar: calendar)
        }
        progress.markForReview(at: day1, calendar: calendar)

        XCTAssertEqual(progress.reviewBox, 0)
        XCTAssertTrue(progress.isDue(at: day1))
        XCTAssertEqual(progress.status(at: day1), .needsReview)
    }

    func testAccuracy() {
        let progress = UserProgress(questionId: "SEI_KINYU_0001")
        XCTAssertEqual(progress.accuracy, 0, "未出題はゼロ除算せずに0を返す")

        progress.record(isCorrect: true)
        progress.record(isCorrect: false)
        progress.record(isCorrect: true)
        progress.record(isCorrect: true)

        XCTAssertEqual(progress.accuracy, 0.75, accuracy: 0.001)
    }
}
