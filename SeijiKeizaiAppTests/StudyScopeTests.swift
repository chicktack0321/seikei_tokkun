import XCTest
import SwiftData
@testable import SeijiKeizaiApp

/// 出題範囲の絞り込み。
///
/// 出題されない理由は「自分で範囲を絞った」以外にありえない（完全無料で全問が
/// 常に出題対象）ので、絞り込みの判定がそのまま出題プールに効くことを確認する。
@MainActor
final class StudyScopeTests: XCTestCase {

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

    @discardableResult
    private func insert(
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

    // MARK: - StudyScope の判定

    func testDefaultScopeIncludesEveryDifficulty() {
        let scope = StudyScope.default

        for difficulty in QuestionDifficulty.allCases {
            let question = insert(
                "SEI_KINYU_000\(difficulty.rawValue)",
                midCategory: .finance,
                difficulty: difficulty
            )
            XCTAssertTrue(
                scope.contains(question),
                "既定の出題範囲からはどの難易度も外さない（\(difficulty.displayName)が外れている）"
            )
        }
    }

    func testDifficultyFilter() {
        var scope = StudyScope.default
        scope.difficulty = .basic

        let basic = insert("SEI_KINYU_0001", midCategory: .finance, difficulty: .basic)
        let advanced = insert("SEI_KINYU_0002", midCategory: .finance, difficulty: .advanced)

        XCTAssertTrue(scope.contains(basic))
        XCTAssertFalse(scope.contains(advanced))
    }

    func testFieldFilter() {
        var scope = StudyScope.default
        scope.setField(.politics)

        let politics = insert("SEI_MINSHU_0001", midCategory: .democracy, difficulty: .basic)
        let economics = insert("SEI_KINYU_0001", midCategory: .finance, difficulty: .basic)

        XCTAssertTrue(scope.contains(politics))
        XCTAssertFalse(scope.contains(economics))
    }

    /// 中分類を選んだら、分野の指定より中分類が優先される
    func testMidCategoryOverridesField() {
        var scope = StudyScope.default
        scope.midCategory = .finance

        let finance = insert("SEI_KINYU_0001", midCategory: .finance, difficulty: .basic)
        let publicFinance = insert("SEI_ZAISEI_0001", midCategory: .publicFinance, difficulty: .basic)

        XCTAssertTrue(scope.contains(finance))
        XCTAssertFalse(scope.contains(publicFinance))
        XCTAssertEqual(scope.effectiveField, .economics, "中分類から分野が決まる")
    }

    /// 分野を変えたら、その分野に属さない中分類の選択は捨てる。
    /// 残すと「政治 / 金融」のような0問確定の組み合わせが作れてしまう。
    func testChangingFieldClearsIncompatibleMidCategory() {
        var scope = StudyScope.default
        scope.setField(.economics)
        scope.midCategory = .finance

        scope.setField(.politics)

        XCTAssertNil(scope.midCategory)
        XCTAssertEqual(scope.field, .politics)
    }

    func testChangingFieldKeepsCompatibleMidCategory() {
        var scope = StudyScope.default
        scope.setField(.economics)
        scope.midCategory = .finance

        scope.setField(.economics)

        XCTAssertEqual(scope.midCategory, .finance, "同じ分野に属する中分類は残す")
    }

    func testSummaryDescribesOnlySpecifiedConditions() {
        XCTAssertEqual(StudyScope.default.summary, "すべて")

        var scope = StudyScope.default
        scope.setField(.civics)
        XCTAssertEqual(scope.summary, "公共")

        scope.difficulty = .advanced
        XCTAssertEqual(scope.summary, "公共 / 応用")

        scope.midCategory = .localGovernment
        XCTAssertEqual(scope.summary, "地方自治 / 応用", "中分類を選んだら分野ではなく中分類を出す")
    }

    // MARK: - リポジトリ経由の出題プール

    /// 出題プールは、利用者が選んだ範囲だけで決まる
    func testStudyPoolFollowsScopeOnly() {
        insert("SEI_MINSHU_0001", midCategory: .democracy, difficulty: .basic)
        insert("SEI_MINSHU_0002", midCategory: .democracy, difficulty: .advanced)
        insert("SEI_KINYU_0001", midCategory: .finance, difficulty: .basic)
        insert("SEI_KINYU_0002", midCategory: .finance, difficulty: .advanced)

        let repository = QuestionRepository(context: context)

        var scope = StudyScope.default
        scope.setField(.politics)

        // 分野で絞れば政治の2問。難易度では絞られない（全問が常に出題対象）
        let politics = repository.fetchStudyPool(scope: scope)
        XCTAssertEqual(politics.map(\.questionId), ["SEI_MINSHU_0001", "SEI_MINSHU_0002"])

        scope.difficulty = .basic
        XCTAssertEqual(repository.fetchStudyPool(scope: scope).map(\.questionId), ["SEI_MINSHU_0001"])

        XCTAssertEqual(repository.fetchStudyPool(scope: .default).count, 4, "既定では全問が出題対象")
    }

    /// 習熟度の集計も、出題と同じ範囲の解釈に従う
    func testMasteryScopeAppliesTheSameFilter() {
        insert("SEI_KINYU_0001", midCategory: .finance, difficulty: .basic)
        insert("SEI_ZAISEI_0001", midCategory: .publicFinance, difficulty: .advanced)

        let repository = QuestionRepository(context: context)
        XCTAssertEqual(repository.fetchQuestions(matching: .default).count, 2)

        var scope = StudyScope.default
        scope.midCategory = .finance
        XCTAssertEqual(repository.fetchQuestions(matching: scope).map(\.questionId), ["SEI_KINYU_0001"])
    }

    func testCountsByField() {
        insert("SEI_SEINEN_0001", midCategory: .adolescence, difficulty: .basic)
        insert("SEI_MINSHU_0001", midCategory: .democracy, difficulty: .basic)
        insert("SEI_KINYU_0001", midCategory: .finance, difficulty: .basic)
        insert("SEI_ZAISEI_0001", midCategory: .publicFinance, difficulty: .basic)

        let counts = QuestionRepository(context: context).countsByField()

        XCTAssertEqual(counts[.civics], 1)
        XCTAssertEqual(counts[.politics], 1)
        XCTAssertEqual(counts[.economics], 2)
        XCTAssertNil(counts[.international], "問題が無い分野は数えない")
    }

    func testCountByDifficulty() {
        insert("SEI_KINYU_0001", midCategory: .finance, difficulty: .advanced)
        insert("SEI_KINYU_0002", midCategory: .finance, difficulty: .advanced)
        insert("SEI_KINYU_0003", midCategory: .finance, difficulty: .basic)

        let repository = QuestionRepository(context: context)

        XCTAssertEqual(repository.count(difficulty: .advanced), 2)
        XCTAssertEqual(repository.count(difficulty: .basic), 1)
        XCTAssertEqual(repository.count(difficulty: .standard), 0)
    }
}
