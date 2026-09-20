import Foundation
import SwiftData
import Observation

/// 出題1問分。表示用にシャッフル済みの選択肢を持つ。
struct QuizQuestion: Identifiable {
    /// 表示位置に並べ替えた選択肢。
    /// `label` はシード上のA〜Dで、解説を引き当てるのに使う（表示上の記号とは別物）。
    struct DisplayChoice: Identifiable {
        let label: ChoiceLabel
        let text: String

        var id: String { label.rawValue }
    }

    let id: String // questionId
    let question: QuestionMaster
    let choices: [DisplayChoice]
    let correctIndex: Int

    /// 表示上の選択肢記号（位置で決まる。シード上のラベルとは一致しない）
    static func displayLabel(at index: Int) -> String {
        guard index >= 0, index < ChoiceLabel.allCases.count else { return "" }
        return ChoiceLabel.allCases[index].rawValue
    }
}

@Observable
@MainActor
final class QuizViewModel {
    /// 1セットの問題数。
    ///
    /// 1問ごとに解説を読む時間が乗るため10問。1セットが長いと、
    /// 解説を飛ばして進むようになり学習の本体が失われる。
    static let questionCount = 10

    private(set) var phase: StudySessionPhase = .notStarted
    /// 直近に開始したセットの出題対象。画面タイトルと結果の文言を切り替えるのに使う。
    private(set) var scope: QuizScope = .mixed
    private(set) var questions: [QuizQuestion] = []
    private(set) var currentQuestionIndex = 0
    /// 選んだ選択肢の表示位置。nil は未解答（= 解説をまだ出していない）
    private(set) var selectedChoiceIndex: Int?
    private(set) var correctAnswerCount = 0

    /// 間違えた問題。結果画面からそのまま解き直しに使えるよう、問題ごと保持する。
    private(set) var missedQuestions: [QuestionMaster] = []
    /// このセットで新たに「習得済み」に到達した問題数
    private(set) var newlyMemorizedCount = 0
    /// 分野ごとの正誤。次にどの分野をやるかを決められるよう、結果画面で必ず出す。
    private(set) var fieldResults: [ExamField: (correct: Int, total: Int)] = [:]

    private var startedAt: Date?
    private(set) var elapsedSeconds = 0

    /// 出題できなかったときにスタート画面へ出す案内。
    /// 「復習を解き終えて期限切れの問題が無くなった」は正常な結果なので、
    /// エラーではなく状況の説明として見せる。
    private(set) var notice: String?

    /// いま選んでいる出題範囲に何問入るか。0問のまま始めさせないために表示する
    private(set) var scopePoolCount = 0

    private var questionRepository: QuestionRepository?
    private var progressRepository: ProgressRepository?

    var currentQuestion: QuizQuestion? {
        guard currentQuestionIndex < questions.count else { return nil }
        return questions[currentQuestionIndex]
    }

    /// 解答済みか（= 解説パネルを出す状態か）
    var hasAnswered: Bool { selectedChoiceIndex != nil }

    var isLastQuestion: Bool { currentQuestionIndex + 1 >= questions.count }

    var progressFraction: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentQuestionIndex) / Double(questions.count)
    }

    func configure(context: ModelContext) {
        guard questionRepository == nil else { return }
        questionRepository = QuestionRepository(context: context)
        progressRepository = ProgressRepository(context: context)
        refreshScopeCount()
    }

    /// 出題範囲を変えたときに、スタート画面の問題数表示を合わせる
    func refreshScopeCount() {
        guard let questionRepository else { return }
        scopePoolCount = questionRepository.countStudyPool(scope: StudySettings.studyScope)
    }

    func startNewQuiz(scope: QuizScope = .mixed) {
        guard let questionRepository, let progressRepository else { return }
        self.scope = scope

        // 出題対象の取得は1回だけ。問題ごとにフェッチすると出題数に比例して
        // 全件スキャンが走り、問題数が増えたときに開始が目に見えて遅くなる。
        //
        // 復習期限が来た問題を優先して出題する（ランダム出題では忘れかけた問題に当たらない）。
        // 解き直しだけは上限も出題範囲も掛けない。直前のセットで実際に出題された問題なので、
        // ここで弾くと「間違えた問題だけ」と言いながら一部しか出ないことになる。
        let sampled: [QuestionMaster]
        switch scope {
        case .mixed:
            let progress = progressRepository.allProgress()
            let ordered = StudyQueue.prioritize(
                questions: questionRepository.fetchStudyPool(),
                progress: progress
            )
            sampled = Array(ordered.prefix(Self.questionCount))

        case .reviewOnly:
            // ホームの「復習する問題がN問あります」から来た場合は、
            // 未学習の問題を混ぜずに期限が来た問題だけを出す
            let progress = progressRepository.allProgress()
            let ordered = StudyQueue.dueQuestions(
                questions: questionRepository.fetchStudyPool(),
                progress: progress
            )
            sampled = Array(ordered.prefix(Self.questionCount))

        case .retryMissed(let questionIds):
            sampled = StudyQueue.select(questionIds: questionIds, from: questionRepository.fetchAll())
        }

        questions = sampled.map { buildQuestion(for: $0) }
        currentQuestionIndex = 0
        correctAnswerCount = 0
        selectedChoiceIndex = nil
        missedQuestions = []
        newlyMemorizedCount = 0
        fieldResults = [:]
        elapsedSeconds = 0
        startedAt = .now
        notice = nil

        // 出題対象が0問になるのは正常な状態（復習を解き終えた直後など）。
        // これを結果画面（.finished）で表示すると「0/0問正解」という意味のない結果が出るうえ、
        // スタート画面へ戻る手段が無くなって演習を始められなくなる。
        guard !questions.isEmpty else {
            notice = scope.emptyNotice
            phase = .notStarted
            GameAudio.shared.stopBGM()
            return
        }

        // 当日の「習得済み」問題数の基準をここで作る。解答中は増減ぶんしか足し引きしないので、
        // 日付をまたいで復習期限が来た問題や、一覧から直接変えた分はこの時点で取り込む。
        progressRepository.refreshMasterySnapshot()

        phase = .inProgress
        GameAudio.shared.play(.start)
        GameAudio.shared.startBGM()
    }

    /// 結果画面に渡す集計
    var resultSummary: QuizResultSummary {
        QuizResultSummary(
            scope: scope,
            correctCount: correctAnswerCount,
            totalCount: questions.count,
            newlyMemorizedCount: newlyMemorizedCount,
            elapsedSeconds: elapsedSeconds,
            missedQuestions: missedQuestions.map {
                QuizResultSummary.MissedQuestion(
                    id: $0.questionId,
                    questionText: $0.questionText,
                    midCategory: $0.midCategory,
                    correctChoiceText: $0.correctChoiceText,
                    explanation: $0.explanation
                )
            },
            fieldResults: ExamField.allCases.compactMap { field in
                guard let result = fieldResults[field], result.total > 0 else { return nil }
                return QuizResultSummary.FieldResult(
                    field: field,
                    correctCount: result.correct,
                    totalCount: result.total
                )
            }
        )
    }

    /// 選択肢の表示順を毎回シャッフルする。
    ///
    /// シード上の並び（A→D）で固定すると「この問題の答えは3番目」という位置記憶で解けてしまい、
    /// 間隔反復が測っているものが「知識」ではなく「並び順の記憶」になる。
    ///
    /// 正解の位置は並べ替えた配列から求めて保持する。表示テキストの検索で探すと、
    /// 同じ文字列の選択肢があった場合に誤った位置を正解と見なしてしまう。
    private func buildQuestion(for question: QuestionMaster) -> QuizQuestion {
        let shuffled = ChoiceLabel.allCases.shuffled().map {
            QuizQuestion.DisplayChoice(label: $0, text: question.choiceText(for: $0))
        }
        let correctIndex = shuffled.firstIndex { $0.label == question.correctChoice } ?? 0

        return QuizQuestion(
            id: question.questionId,
            question: question,
            choices: shuffled,
            correctIndex: correctIndex
        )
    }

    /// 解答する。ここで正誤が確定し、解説パネルが出る。
    func selectAnswer(_ index: Int) {
        guard phase == .inProgress, selectedChoiceIndex == nil, let question = currentQuestion else { return }
        selectedChoiceIndex = index

        let isCorrect = index == question.correctIndex
        if isCorrect { correctAnswerCount += 1 }
        GameAudio.shared.play(isCorrect ? .correct : .miss)
        record(question: question, isCorrect: isCorrect)
    }

    private func record(question: QuizQuestion, isCorrect: Bool) {
        guard let progressRepository else { return }

        let outcome = progressRepository.recordAnswer(question: question.question, isCorrect: isCorrect)

        if outcome.reachedMemorized {
            newlyMemorizedCount += 1
        }
        if !isCorrect {
            missedQuestions.append(question.question)
        }

        let field = question.question.field
        var result = fieldResults[field] ?? (correct: 0, total: 0)
        result.total += 1
        if isCorrect { result.correct += 1 }
        fieldResults[field] = result
    }

    func goToNextQuestion() {
        guard hasAnswered else { return }
        guard !isLastQuestion else {
            finish()
            return
        }
        currentQuestionIndex += 1
        selectedChoiceIndex = nil
    }

    private func finish() {
        if let startedAt {
            elapsedSeconds = max(0, Int(Date.now.timeIntervalSince(startedAt)))
        }
        phase = .finished
        GameAudio.shared.stopBGM()
        // 1問ごとの保存は待ち時間になるのでやめ、区切りでまとめて書き出す
        progressRepository?.save()
        // 結果画面のグレードと揃える。A以上（75%以上）なら祝う音にする。
        GameAudio.shared.play(resultSummary.accuracyPercent >= 75 ? .fanfare : .setComplete)
    }

    /// 進行中のセットを破棄してスタート画面に戻す。
    /// これが無いと、始めてしまったら最後まで解くしか抜ける手段がない。
    func abortSession() {
        returnToStart()
    }

    /// 結果画面からスタート画面へ戻す。
    /// 結果を見たあと別の出題で解き直せるよう、必ず戻り道を用意しておく。
    func returnToStart() {
        GameAudio.shared.stopBGM()
        progressRepository?.save()
        questions = []
        currentQuestionIndex = 0
        selectedChoiceIndex = nil
        correctAnswerCount = 0
        notice = nil
        phase = .notStarted
        refreshScopeCount()
    }

    /// 別タブへ移動した・アプリが背面に回ったとき。
    ///
    /// 制限時間を持たないので進行は止めなくてよいが、そのまま終了されても
    /// 解答が消えないようにここで書き出しておく。
    func suspendSession() {
        GameAudio.shared.stopBGM()
        progressRepository?.save()
    }

    /// 画面に戻ったとき。BGMを鳴らし直す。
    func resumeSession() {
        guard phase == .inProgress else { return }
        GameAudio.shared.startBGM()
    }
}
