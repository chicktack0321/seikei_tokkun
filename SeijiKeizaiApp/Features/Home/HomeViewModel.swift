import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class HomeViewModel {
    /// 分野ごとの習熟度。分野で配点の比重が違うため、ホームの主表示にする。
    struct FieldProgress: Identifiable {
        let field: ExamField
        let totalCount: Int
        let memorizedCount: Int

        var id: String { field.rawValue }

        var fraction: Double {
            totalCount == 0 ? 0 : Double(memorizedCount) / Double(totalCount)
        }

        var percent: Int { Int((fraction * 100).rounded()) }
    }

    /// 習熟度の集計対象になっている問題数（絞り込みを反映する）
    private(set) var totalQuestionCount = 0
    private(set) var summary: ProgressSummary = .empty
    private(set) var todayStudiedCount = 0
    private(set) var todayAccuracy: Double = 0
    /// 復習期限が来ている問題の数。学習を再開する動機付けとしてホームに出す。
    private(set) var dueCount = 0
    /// ホームのミニグラフ用（直近1週間）
    private(set) var weeklySeries: [DailyStudy] = []
    /// 連続学習日数
    private(set) var streak = 0
    /// 分野別習熟度。絞り込みの影響を受けず常に全問で集計する（分野の仕上がりを見る数字なので）
    private(set) var fieldProgress: [FieldProgress] = []

    private var questionRepository: QuestionRepository?
    private var progressRepository: ProgressRepository?

    var memorizedCount: Int { summary.count(of: .memorized) }
    var needsReviewCount: Int { summary.count(of: .needsReview) }
    var overallAccuracy: Double { summary.accuracy }

    /// いちばん遅れている分野。次に何をやるべきかの案内に使う。
    ///
    /// まだどの分野も習得済みが0のうちは返さない。全分野が同率0%のときに最小値を取ると、
    /// 並び順で決まった分野を「いちばん遅れている」と言い切ることになり、根拠のない案内になる。
    /// 学習前の入口は「演習を始める」で足りている。
    var weakestField: FieldProgress? {
        let candidates = fieldProgress.filter { $0.totalCount > 0 }
        guard candidates.contains(where: { $0.memorizedCount > 0 }) else { return nil }
        return candidates.min { $0.fraction < $1.fraction }
    }

    /// 習熟度の内訳。
    ///
    /// 一度も解いていない問題には進捗の行が無い（使わない行を同じ数だけ作らない方針）。
    /// そのぶんの「未学習」は行を数えても出てこないので、
    /// 全問数から学習済みの問題数を引いて求める。
    var statusCounts: [LearningStatus: Int] {
        var counts = summary.statusCounts
        let studied = LearningStatus.allCases
            .filter { $0 != .notStudied }
            .reduce(0) { $0 + (counts[$1] ?? 0) }
        counts[.notStudied] = max(0, totalQuestionCount - studied)
        return counts
    }

    func configure(context: ModelContext) {
        guard questionRepository == nil else { return }
        questionRepository = QuestionRepository(context: context)
        progressRepository = ProgressRepository(context: context)
        reload()
    }

    /// 習熟度を集計する範囲。全問をまとめて見るとバーがほとんど動かず、
    /// 進んでいる実感が得られないため、分野・中分類・難易度で切って見られるようにする。
    var masteryScope = StudySettings.masteryScope {
        didSet {
            guard masteryScope != oldValue else { return }
            StudySettings.masteryScope = masteryScope
            reloadMastery()
        }
    }

    /// 集計範囲は履歴の画面とも共有しているため、向こうで変えられていることがある。
    /// ホームへ戻ったときに読み直さないと、同じ範囲設定なのに画面ごとに違う数字が出る。
    func syncScopeFromSettings() {
        guard masteryScope != StudySettings.masteryScope else { return }
        masteryScope = StudySettings.masteryScope
    }

    /// 習熟度だけを集計し直す。絞り込みを変えたときは全体を読み直す必要がない。
    func reloadMastery() {
        guard let questionRepository, let progressRepository else { return }

        // 出題用のプールではなく、収録している問題全体から絞り込む。
        let questions = questionRepository.fetchQuestions(matching: masteryScope)
        totalQuestionCount = questions.count
        summary = progressRepository.summarize(questions: questions)
    }

    /// 分野別の習熟度。
    ///
    /// こちらは `masteryScope` の絞り込みを**適用しない**。分野ごとの仕上がりを見る数字なので、
    /// 「金融だけに絞ったときの経済分野」のような部分集合を出すと意味が変わる。
    private func reloadFieldProgress() {
        guard let questionRepository, let progressRepository else { return }
        let totals = questionRepository.countsByField()
        let mastered = progressRepository.masteredSnapshot().countsByField()

        fieldProgress = ExamField.allCases.map { field in
            FieldProgress(
                field: field,
                totalCount: totals[field] ?? 0,
                memorizedCount: mastered[field] ?? 0
            )
        }
    }

    func reload() {
        guard let questionRepository, let progressRepository else { return }
        reloadMastery()
        reloadFieldProgress()

        dueCount = StudyQueue.dueCount(
            questions: questionRepository.fetchStudyPool(),
            progress: progressRepository.allProgress()
        )

        let log = progressRepository.todayLog()
        todayStudiedCount = log?.studiedQuestionCount ?? 0
        todayAccuracy = log?.accuracy ?? 0

        weeklySeries = StudyHistory.series(logs: progressRepository.recentLogs(days: 7), days: 7)
        streak = StudyHistory.currentStreak(logs: progressRepository.logsForStreak())
    }
}
