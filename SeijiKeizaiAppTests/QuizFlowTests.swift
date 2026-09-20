import XCTest
import SwiftData
@testable import SeijiKeizaiApp

/// 演習の進行と、選択肢シャッフルの正しさ。
///
/// シャッフルは「表示位置と正解位置の対応」が崩れても画面上は動いて見えるが、
/// 正解を選んでも不正解になるという最悪の壊れ方をするため必ず確認する。
@MainActor
final class QuizFlowTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: QuizViewModel!

    override func setUp() async throws {
        let schema = Schema([QuestionMaster.self, UserProgress.self, StudyLog.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = container.mainContext

        // 出題範囲の設定は UserDefaults に載るため、テスト間で持ち越さないよう既定に戻す
        StudySettings.studyScope = .default

        viewModel = QuizViewModel()
    }

    override func tearDown() async throws {
        StudySettings.studyScope = .default
        viewModel = nil
        container = nil
        context = nil
    }

    @discardableResult
    private func insertQuestion(
        _ id: String,
        correct: ChoiceLabel = .b,
        midCategory: MidCategory = .finance,
        difficulty: QuestionDifficulty = .standard
    ) -> QuestionMaster {
        let question = QuestionMaster(
            questionId: id,
            questionText: "問題文 \(id)",
            choiceA: "\(id)-A",
            choiceB: "\(id)-B",
            choiceC: "\(id)-C",
            choiceD: "\(id)-D",
            correctChoice: correct,
            explanation: "\(id) の解説",
            explanationA: "正解。",
            explanationB: "不正解。",
            explanationC: "不正解。",
            explanationD: "不正解。",
            field: midCategory.field,
            midCategory: midCategory,
            curriculumVersion: "2022課程",
            difficulty: difficulty
        )
        context.insert(question)
        return question
    }

    /// 全問正解できるよう、正解の表示位置を選び続ける
    private func answerAll(correct: Bool) {
        while viewModel.phase == .inProgress {
            guard let question = viewModel.currentQuestion else { break }
            let index = correct
                ? question.correctIndex
                : (question.correctIndex + 1) % question.choices.count
            viewModel.selectAnswer(index)
            viewModel.goToNextQuestion()
        }
    }

    // MARK: - 選択肢のシャッフル

    /// シード上のラベルがどこへ移動しても、correctIndex は正解の選択肢を指している必要がある
    func testCorrectIndexPointsToCorrectChoiceAfterShuffle() {
        for label in ChoiceLabel.allCases {
            insertQuestion("SEI_KINYU_000\(label.rawValue)", correct: label)
        }
        viewModel.configure(context: context)

        // シャッフルは乱数なので、複数回試して常に対応が取れていることを見る
        for _ in 0..<30 {
            viewModel.startNewQuiz()
            XCTAssertEqual(viewModel.phase, .inProgress)

            for question in viewModel.questions {
                let displayed = question.choices[question.correctIndex]
                XCTAssertEqual(
                    displayed.label,
                    question.question.correctChoice,
                    "correctIndex が指す選択肢は、シード上の正解ラベルと一致しなければならない"
                )
                XCTAssertEqual(
                    displayed.text,
                    question.question.correctChoiceText,
                    "correctIndex が指す選択肢の本文は、正解の本文と一致しなければならない"
                )
            }
            viewModel.returnToStart()
        }
    }

    /// 4つの選択肢が過不足なく並ぶ（シャッフルで欠落・重複しない）
    func testShuffleKeepsAllChoices() {
        let question = insertQuestion("SEI_KINYU_0001")
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        let displayed = viewModel.questions[0]
        XCTAssertEqual(displayed.choices.count, 4)
        XCTAssertEqual(
            Set(displayed.choices.map(\.label)),
            Set(ChoiceLabel.allCases),
            "A〜Dがそれぞれ一度ずつ現れる"
        )
        XCTAssertEqual(
            Set(displayed.choices.map(\.text)),
            Set([question.choiceA, question.choiceB, question.choiceC, question.choiceD])
        )
    }

    /// 位置記憶で解けてしまわないよう、表示順は毎回変わりうる
    func testShuffleProducesVaryingOrders() {
        insertQuestion("SEI_KINYU_0001")
        viewModel.configure(context: context)

        var seenOrders: Set<[String]> = []
        for _ in 0..<40 {
            viewModel.startNewQuiz()
            seenOrders.insert(viewModel.questions[0].choices.map(\.label.rawValue))
            viewModel.returnToStart()
        }

        XCTAssertGreaterThan(
            seenOrders.count, 1,
            "40回試して並びが1通りしか出ないなら、シャッフルが効いていない"
        )
    }

    // MARK: - 進行

    /// 解答すると解説の表示状態になり、次の問題へは進まない。
    /// ここが崩れると解説を読む間もなく次へ流れてしまい、学習の本体が失われる。
    func testAnsweringShowsExplanationWithoutAdvancing() {
        insertQuestion("SEI_KINYU_0001")
        insertQuestion("SEI_KINYU_0002")
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        XCTAssertFalse(viewModel.hasAnswered)
        XCTAssertEqual(viewModel.currentQuestionIndex, 0)

        viewModel.selectAnswer(0)

        XCTAssertTrue(viewModel.hasAnswered, "解答したら解説を出す状態になる")
        XCTAssertEqual(viewModel.currentQuestionIndex, 0, "解答しただけでは次の問題へ進まない")

        viewModel.goToNextQuestion()

        XCTAssertEqual(viewModel.currentQuestionIndex, 1)
        XCTAssertFalse(viewModel.hasAnswered, "次の問題では未解答に戻る")
    }

    /// 二度押しで別の選択肢に上書きされない
    func testSecondAnswerIsIgnored() {
        insertQuestion("SEI_KINYU_0001")
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        let question = viewModel.currentQuestion!
        let wrongIndex = (question.correctIndex + 1) % question.choices.count

        viewModel.selectAnswer(wrongIndex)
        viewModel.selectAnswer(question.correctIndex)

        XCTAssertEqual(viewModel.selectedChoiceIndex, wrongIndex)
        XCTAssertEqual(viewModel.correctAnswerCount, 0)
    }

    /// 未解答のまま次へ進めない（選択肢を読まずに飛ばせてしまう）
    func testCannotAdvanceBeforeAnswering() {
        insertQuestion("SEI_KINYU_0001")
        insertQuestion("SEI_KINYU_0002")
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        viewModel.goToNextQuestion()

        XCTAssertEqual(viewModel.currentQuestionIndex, 0)
        XCTAssertEqual(viewModel.phase, .inProgress)
    }

    func testFinishingSetMovesToResult() {
        insertQuestion("SEI_KINYU_0001")
        insertQuestion("SEI_KINYU_0002")
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        answerAll(correct: true)

        XCTAssertEqual(viewModel.phase, .finished)
        XCTAssertEqual(viewModel.resultSummary.correctCount, 2)
        XCTAssertEqual(viewModel.resultSummary.totalCount, 2)
        XCTAssertEqual(viewModel.resultSummary.accuracyPercent, 100)
    }

    func testSetIsCappedAtQuestionCount() {
        for i in 1...25 {
            insertQuestion(String(format: "SEI_KINYU_%04d", i))
        }
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        XCTAssertEqual(viewModel.questions.count, QuizViewModel.questionCount)
    }

    // MARK: - 結果

    /// 分野別の内訳が正しく集計される（どの分野が落ちているかが結果画面の主表示）
    func testFieldResultsAreAggregated() {
        insertQuestion("SEI_KINYU_0001", midCategory: .finance)
        insertQuestion("SEI_ZAISEI_0001", midCategory: .publicFinance)
        insertQuestion("SEI_MINSHU_0001", midCategory: .democracy)
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        answerAll(correct: true)

        let byField = Dictionary(
            uniqueKeysWithValues: viewModel.resultSummary.fieldResults.map { ($0.field, $0) }
        )
        XCTAssertEqual(byField[.economics]?.totalCount, 2, "金融と財政はどちらも経済分野")
        XCTAssertEqual(byField[.economics]?.correctCount, 2)
        XCTAssertEqual(byField[.politics]?.totalCount, 1)
        XCTAssertNil(byField[.civics], "出題されなかった分野は結果に出さない")
    }

    func testMissedQuestionsAreCollected() {
        insertQuestion("SEI_KINYU_0001")
        insertQuestion("SEI_KINYU_0002")
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        answerAll(correct: false)

        XCTAssertEqual(viewModel.resultSummary.correctCount, 0)
        XCTAssertEqual(viewModel.resultSummary.missedQuestions.count, 2)
    }

    /// 「間違えた問題だけ解き直す」は、出題範囲や上限に関係なく渡した問題を全部出す
    func testRetryMissedIgnoresScopeAndCap() {
        insertQuestion("SEI_KINYU_0001", difficulty: .advanced)
        insertQuestion("SEI_ZAISEI_0001", midCategory: .publicFinance, difficulty: .advanced)
        viewModel.configure(context: context)

        // 出題範囲を「政治分野のみ」に絞る。解き直しはこれを無視する必要がある
        var scope = StudyScope.default
        scope.setField(.politics)
        StudySettings.studyScope = scope

        viewModel.startNewQuiz(scope: .retryMissed(questionIds: ["SEI_KINYU_0001", "SEI_ZAISEI_0001"]))

        XCTAssertEqual(viewModel.phase, .inProgress)
        XCTAssertEqual(
            viewModel.questions.map(\.id),
            ["SEI_KINYU_0001", "SEI_ZAISEI_0001"],
            "解き直しは出題範囲で絞らず、渡した順に出す"
        )
    }

    // MARK: - 出題対象が0問のとき

    /// 0問で結果画面に入ると「0/0問正解」という無意味な結果が出るうえ、
    /// スタート画面へ戻る手段が無くなって演習を始められなくなる
    func testEmptyPoolStaysOnStartScreenWithNotice() {
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        XCTAssertEqual(viewModel.phase, .notStarted)
        XCTAssertNotNil(viewModel.notice)
    }

    func testReviewOnlyWithNothingDueShowsCompletionNotice() {
        insertQuestion("SEI_KINYU_0001")
        viewModel.configure(context: context)

        viewModel.startNewQuiz(scope: .reviewOnly)

        XCTAssertEqual(viewModel.phase, .notStarted)
        XCTAssertEqual(
            viewModel.notice,
            "復習の期限が来ている問題はありません。おつかれさまでした。",
            "解き終えた状態はエラーではなく達成として伝える"
        )
    }

    // MARK: - 進捗の記録

    func testAnswersAreRecordedToProgress() {
        insertQuestion("SEI_KINYU_0001")
        viewModel.configure(context: context)
        viewModel.startNewQuiz()

        answerAll(correct: true)

        let progress = ProgressRepository(context: context).allProgress()["SEI_KINYU_0001"]
        XCTAssertEqual(progress?.attemptCount, 1)
        XCTAssertEqual(progress?.correctCount, 1)
        XCTAssertEqual(progress?.reviewBox, 1)
    }

    func testNewlyMemorizedIsCountedOnce() {
        let question = insertQuestion("SEI_KINYU_0001")
        viewModel.configure(context: context)

        // あらかじめ box=2 まで進めておき、このセットの正解で習得済みへ到達させる
        let repository = ProgressRepository(context: context)
        let progress = repository.progress(for: question.questionId)
        progress.record(isCorrect: true)
        progress.record(isCorrect: true)
        XCTAssertEqual(progress.status(), .learning)

        viewModel.startNewQuiz()
        answerAll(correct: true)

        XCTAssertEqual(progress.status(), .memorized)
        XCTAssertEqual(viewModel.resultSummary.newlyMemorizedCount, 1)
    }
}
