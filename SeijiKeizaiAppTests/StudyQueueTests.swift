import XCTest
import SwiftData
@testable import SeijiKeizaiApp

/// 出題順の優先度。
///
/// ランダム出題に退行しても画面上は正常に動いて見えるため、順序をテストで固定する。
@MainActor
final class StudyQueueTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = Calendar(identifier: .gregorian)

    override func setUp() async throws {
        // SwiftData の @Model はコンテキストに挿入せずとも生成できるが、
        // 実際の使われ方に合わせてインメモリのストアを用意する
        let schema = Schema([QuestionMaster.self, UserProgress.self, StudyLog.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func makeQuestion(_ id: String, midCategory: MidCategory = .finance) -> QuestionMaster {
        let question = QuestionMaster(
            questionId: id,
            questionText: "問題文 \(id)",
            choiceA: "選択肢A",
            choiceB: "選択肢B",
            choiceC: "選択肢C",
            choiceD: "選択肢D",
            correctChoice: .a,
            explanation: "解説",
            explanationA: "正解。",
            explanationB: "不正解。",
            explanationC: "不正解。",
            explanationD: "不正解。",
            field: midCategory.field,
            midCategory: midCategory,
            curriculumVersion: "2022課程"
        )
        context.insert(question)
        return question
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    /// 期限切れ → 未学習 → 期限前、の順に並ぶ
    func testPriorityOrder() {
        let now = date(2026, 4, 10)

        let due = makeQuestion("SEI_KINYU_0001")
        let unstudied = makeQuestion("SEI_KINYU_0002")
        let scheduled = makeQuestion("SEI_KINYU_0003")

        let dueProgress = UserProgress(questionId: due.questionId)
        dueProgress.record(isCorrect: true, reviewedAt: date(2026, 4, 1), calendar: calendar)

        let scheduledProgress = UserProgress(questionId: scheduled.questionId)
        scheduledProgress.record(isCorrect: true, reviewedAt: now, calendar: calendar)

        let ordered = StudyQueue.prioritize(
            questions: [scheduled, unstudied, due],
            progress: [
                due.questionId: dueProgress,
                scheduled.questionId: scheduledProgress
            ],
            now: now
        )

        XCTAssertEqual(ordered.map(\.questionId), [
            due.questionId,
            unstudied.questionId,
            scheduled.questionId
        ])
    }

    /// 期限前の問題どうしは、期限が近い順に並ぶ
    func testScheduledQuestionsSortedByDueDate() {
        let now = date(2026, 4, 10)

        let soon = makeQuestion("SEI_KINYU_0001")
        let later = makeQuestion("SEI_KINYU_0002")

        let soonProgress = UserProgress(questionId: soon.questionId)
        // box=1 → 1日後
        soonProgress.record(isCorrect: true, reviewedAt: now, calendar: calendar)

        let laterProgress = UserProgress(questionId: later.questionId)
        // box=3 → 7日後
        for _ in 0..<3 {
            laterProgress.record(isCorrect: true, reviewedAt: now, calendar: calendar)
        }

        let ordered = StudyQueue.prioritize(
            questions: [later, soon],
            progress: [soon.questionId: soonProgress, later.questionId: laterProgress],
            now: now
        )

        XCTAssertEqual(ordered.map(\.questionId), [soon.questionId, later.questionId])
    }

    /// 解いた記録はあるが日程が入っていないデータは復習対象として扱う
    func testProgressWithoutScheduleIsTreatedAsDue() {
        let now = date(2026, 4, 10)
        let question = makeQuestion("SEI_KINYU_0001")
        let unstudied = makeQuestion("SEI_KINYU_0002")

        let progress = UserProgress(questionId: question.questionId, attemptCount: 1, nextReviewAt: nil)

        let ordered = StudyQueue.prioritize(
            questions: [unstudied, question],
            progress: [question.questionId: progress],
            now: now
        )

        XCTAssertEqual(ordered.first?.questionId, question.questionId)
    }

    /// 復習のみの出題では、未学習の問題を混ぜない
    func testDueQuestionsExcludesUnstudied() {
        let now = date(2026, 4, 10)

        let due = makeQuestion("SEI_KINYU_0001")
        let unstudied = makeQuestion("SEI_KINYU_0002")

        let dueProgress = UserProgress(questionId: due.questionId)
        dueProgress.record(isCorrect: false, reviewedAt: date(2026, 4, 1), calendar: calendar)

        let result = StudyQueue.dueQuestions(
            questions: [due, unstudied],
            progress: [due.questionId: dueProgress],
            now: now
        )

        XCTAssertEqual(result.map(\.questionId), [due.questionId])
    }

    func testDueCountMatchesDueQuestions() {
        let now = date(2026, 4, 10)

        let due1 = makeQuestion("SEI_KINYU_0001")
        let due2 = makeQuestion("SEI_KINYU_0002")
        let notDue = makeQuestion("SEI_KINYU_0003")
        let unstudied = makeQuestion("SEI_KINYU_0004")

        var progress: [String: UserProgress] = [:]
        for question in [due1, due2] {
            let p = UserProgress(questionId: question.questionId)
            p.record(isCorrect: false, reviewedAt: date(2026, 4, 1), calendar: calendar)
            progress[question.questionId] = p
        }
        let notDueProgress = UserProgress(questionId: notDue.questionId)
        for _ in 0..<3 {
            notDueProgress.record(isCorrect: true, reviewedAt: now, calendar: calendar)
        }
        progress[notDue.questionId] = notDueProgress

        let questions = [due1, due2, notDue, unstudied]
        XCTAssertEqual(StudyQueue.dueCount(questions: questions, progress: progress, now: now), 2)
        XCTAssertEqual(
            StudyQueue.dueQuestions(questions: questions, progress: progress, now: now).count,
            2
        )
    }

    /// 「間違えた問題だけ解き直す」は、渡した順序をそのまま保つ
    func testSelectPreservesGivenOrder() {
        let q1 = makeQuestion("SEI_KINYU_0001")
        let q2 = makeQuestion("SEI_ZAISEI_0001", midCategory: .publicFinance)
        let q3 = makeQuestion("SEI_SHIJO_0001", midCategory: .market)

        let selected = StudyQueue.select(
            questionIds: [q3.questionId, q1.questionId],
            from: [q1, q2, q3]
        )

        XCTAssertEqual(selected.map(\.questionId), [q3.questionId, q1.questionId])
    }

    /// マスターから取り下げられた問題のIDが残っていても落ちない
    func testSelectSkipsUnknownIds() {
        let q1 = makeQuestion("SEI_KINYU_0001")

        let selected = StudyQueue.select(
            questionIds: ["SEI_KINYU_9999", q1.questionId],
            from: [q1]
        )

        XCTAssertEqual(selected.map(\.questionId), [q1.questionId])
    }
}
