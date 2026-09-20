import XCTest
import SwiftData
@testable import SeijiKeizaiApp

/// 習熟度の内訳。
///
/// 推移グラフは日ごとのスナップショットでしか残せず、後から遡って再計算できない。
/// キーの作り方や集計を間違えると、過去のグラフが二度と正しく描けなくなる。
@MainActor
final class MasteryBreakdownTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
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

    private func makeQuestion(
        _ id: String,
        midCategory: MidCategory,
        difficulty: QuestionDifficulty
    ) -> QuestionMaster {
        let question = QuestionMaster(
            questionId: id,
            questionText: "問題文 \(id)",
            choiceA: "A", choiceB: "B", choiceC: "C", choiceD: "D",
            correctChoice: .a,
            explanation: "解説",
            explanationA: "正解。", explanationB: "不正解。",
            explanationC: "不正解。", explanationD: "不正解。",
            field: midCategory.field,
            midCategory: midCategory,
            curriculumVersion: "2022課程",
            difficulty: difficulty
        )
        context.insert(question)
        return question
    }

    func testKeyCombinesMidCategoryAndDifficulty() {
        let question = makeQuestion("SEI_KINYU_0001", midCategory: .finance, difficulty: .advanced)
        XCTAssertEqual(MasteryBreakdown.key(for: question), "KINYU|3")
    }

    /// 中分類で絞れる
    func testCountFiltersByMidCategory() {
        let breakdown = ["KINYU|1": 3, "KINYU|2": 5, "ZAISEI|2": 7]

        var scope = StudyScope.default
        scope.midCategory = .finance

        XCTAssertEqual(MasteryBreakdown.count(in: breakdown, scope: scope), 8)
    }

    /// 分野で絞ると、その分野に属する中分類が合算される。
    /// 分野をキーに焼いていると中分類での絞り込みが後から作れないため、中分類で持って集計側で束ねる。
    func testCountFiltersByField() {
        let breakdown = ["KINYU|2": 5, "ZAISEI|2": 7, "MINSHU|1": 3, "TOCHI|2": 2]

        var scope = StudyScope.default
        scope.setField(.economics)

        XCTAssertEqual(MasteryBreakdown.count(in: breakdown, scope: scope), 12, "KINYU + ZAISEI")
    }

    func testCountFiltersByDifficulty() {
        let breakdown = ["KINYU|1": 3, "KINYU|3": 5, "ZAISEI|3": 7]

        var scope = StudyScope.default
        scope.difficulty = .advanced

        XCTAssertEqual(MasteryBreakdown.count(in: breakdown, scope: scope), 12)
    }

    func testCountCombinesFieldAndDifficulty() {
        let breakdown = ["KINYU|1": 3, "KINYU|3": 5, "ZAISEI|3": 7, "MINSHU|3": 11]

        var scope = StudyScope.default
        scope.setField(.economics)
        scope.difficulty = .advanced

        XCTAssertEqual(MasteryBreakdown.count(in: breakdown, scope: scope), 12, "MINSHUは分野違いで除外")
    }

    /// 保存データが壊れていても落ちない（未知の中分類・不正な形式は無視する）
    func testCountIgnoresMalformedKeys() {
        let breakdown = ["KINYU|2": 5, "壊れたキー": 100, "XXX|2": 50, "KINYU": 30]

        XCTAssertEqual(MasteryBreakdown.count(in: breakdown, scope: .default), 5)
    }

    func testSnapshotUsesTotalWhenScopeIsDefault() {
        let snapshot = MasterySnapshot(total: 42, breakdown: ["KINYU|2": 5])
        // 既定の範囲では内訳を足さずに合計をそのまま使う（内訳が無い古い記録でも数が出る）
        XCTAssertEqual(snapshot.count(scope: .default), 42)
    }

    func testSnapshotCountsByField() {
        let snapshot = MasterySnapshot(
            total: 20,
            breakdown: ["KINYU|2": 5, "ZAISEI|1": 3, "MINSHU|2": 7, "SEINEN|3": 5]
        )

        let byField = snapshot.countsByField()

        XCTAssertEqual(byField[.economics], 8)
        XCTAssertEqual(byField[.politics], 7)
        XCTAssertEqual(byField[.civics], 5)
    }

    // MARK: - リポジトリ経由のスナップショット

    /// マスターから取り下げた問題は「習得済み」に数えない。
    /// 進捗の行は残す設計なので、行だけを数えると一覧やホームの表示と数が合わなくなる。
    func testSnapshotCountsOnlyQuestionsThatStillExist() {
        let question = makeQuestion("SEI_KINYU_0001", midCategory: .finance, difficulty: .standard)
        let repository = ProgressRepository(context: context)

        // 実在する問題を習得済みにする
        let progress = repository.progress(for: question.questionId)
        progress.markAsMemorized()

        // マスターに存在しない問題の進捗（取り下げた問題の残骸）
        let orphan = repository.progress(for: "SEI_KINYU_9999")
        orphan.markAsMemorized()

        let snapshot = repository.masteredSnapshot()

        XCTAssertEqual(snapshot.total, 1, "マスターに残っている問題だけを数える")
        XCTAssertEqual(snapshot.breakdown, ["KINYU|2": 1])
    }

    /// 解答のたびに全問走査しないよう、増減ぶんだけを足し引きしていること
    func testRecordAnswerUpdatesBreakdownIncrementally() {
        let question = makeQuestion("SEI_KINYU_0001", midCategory: .finance, difficulty: .standard)
        let repository = ProgressRepository(context: context)

        // box=3（習得済み）へ到達するまで正解を重ねる
        for _ in 0..<3 {
            repository.recordAnswer(question: question, isCorrect: true)
        }

        let log = repository.todayLog()
        XCTAssertEqual(log?.masteredQuestionCount, 1)
        XCTAssertEqual(log?.masteredBreakdown["KINYU|2"], 1)

        // 間違えると習得済みから外れ、内訳からもセルごと消える
        repository.recordAnswer(question: question, isCorrect: false)

        XCTAssertEqual(log?.masteredQuestionCount, 0)
        XCTAssertNil(log?.masteredBreakdown["KINYU|2"], "0になったセルは残さない")
    }

    func testRecordAnswerAccumulatesDailyTotals() {
        let question = makeQuestion("SEI_KINYU_0001", midCategory: .finance, difficulty: .standard)
        let repository = ProgressRepository(context: context)

        repository.recordAnswer(question: question, isCorrect: true)
        repository.recordAnswer(question: question, isCorrect: false)
        repository.recordAnswer(question: question, isCorrect: true)

        let log = repository.todayLog()
        XCTAssertEqual(log?.attemptCount, 3)
        XCTAssertEqual(log?.correctCount, 2)
        XCTAssertEqual(log?.studiedQuestionCount, 3, "同じ問題を解き直した分も延べで数える")
        XCTAssertEqual(log?.accuracy ?? 0, 2.0 / 3.0, accuracy: 0.001)
    }
}
