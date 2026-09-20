import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class QuestionListViewModel {
    private(set) var questions: [QuestionMaster] = []
    private(set) var progressById: [String: UserProgress] = [:]
    /// 絞り込み前の総問題数。「0件」が絞り込みのせいか未投入かを区別して見せるのに使う
    private(set) var totalCount = 0

    /// 絞り込み条件。
    ///
    /// 変更時の再取得は `didSet` ではなく View 側の `onChange` で行う。
    /// `@Observable` は `didSet` を持つ格納プロパティを監視対象から外すため、
    /// ここに副作用を置くと絞り込みチップの表示だけが更新されずに取り残される。
    var filter = QuestionFilter()

    private var questionRepository: QuestionRepository?
    private var progressRepository: ProgressRepository?

    /// SwiftDataの ModelContext は Viewの `.task` から渡す（init時点ではまだ利用できないため）
    func configure(context: ModelContext) {
        guard questionRepository == nil else { return }
        questionRepository = QuestionRepository(context: context)
        progressRepository = ProgressRepository(context: context)
        reload()
    }

    func reload() {
        guard let questionRepository, let progressRepository else { return }
        progressById = progressRepository.allProgress()
        totalCount = questionRepository.fetchCount()

        // 絞り込みは `QuestionFilter` に一本化してメモリ上で行う。
        // ステータスは別テーブル(UserProgress)にあってDB側の述語では引けず、
        // 条件を分けると同じ判定が2か所に散る。収録数は1,000問規模の想定なので
        // 全件取得でも体感できる差は出ない。
        questions = filter.apply(to: questionRepository.fetchAll(), progress: progressById)
    }

    func status(for question: QuestionMaster) -> LearningStatus {
        progressById[question.questionId]?.status ?? .notStudied
    }

    /// 「この問題をやり直す」。最短間隔に戻して次の演習で優先的に出題されるようにする
    func markForReview(_ question: QuestionMaster) {
        guard let progressRepository else { return }
        progressRepository.progress(for: question.questionId).markForReview()
        commitStatusChange()
    }

    /// 「この問題は分かっている」。既に確実な問題を毎回出題されないようにする逃げ道
    func markAsMemorized(_ question: QuestionMaster) {
        guard let progressRepository else { return }
        progressRepository.progress(for: question.questionId).markAsMemorized()
        commitStatusChange()
    }

    /// 解答を経ない状態変更なので、当日の習熟度スナップショットを焼き直してから保存する。
    /// でないとホームや履歴の「習得済み」の数が、一覧の表示と食い違う。
    private func commitStatusChange() {
        guard let progressRepository else { return }
        progressRepository.refreshMasterySnapshot()
        progressRepository.save()
        reload()
    }
}
