import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class StudyHistoryViewModel {
    /// グラフの表示期間
    enum Period: String, CaseIterable, Identifiable {
        case twoWeeks
        case month
        case threeMonths
        case sixMonths
        case year

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .twoWeeks: return 14
            case .month: return 30
            case .threeMonths: return 90
            case .sixMonths: return 180
            case .year: return 365
            }
        }

        var displayName: String {
            switch self {
            case .twoWeeks: return "2週間"
            case .month: return "1か月"
            case .threeMonths: return "3か月"
            case .sixMonths: return "6か月"
            case .year: return "1年"
            }
        }

        /// 横軸の日付ラベルを何日おきに出すか。長期間で毎日出すと潰れて読めなくなる。
        var axisStrideDays: Int {
            switch self {
            case .twoWeeks: return 3
            case .month: return 7
            case .threeMonths: return 21
            case .sixMonths: return 45
            case .year: return 90
            }
        }

        /// 長期間では棒が細くなりすぎるので、日次ではなく週ごとにまとめる
        var aggregatesByWeek: Bool {
            switch self {
            case .twoWeeks, .month: return false
            case .threeMonths, .sixMonths, .year: return true
            }
        }
    }

    /// 折れ線の1点。集計範囲で絞れない日は点を打たないため、系列とは別に持つ。
    struct MasteryPoint: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    var selectedPeriod: Period = .twoWeeks {
        didSet { reload() }
    }

    /// 習得済みの問題数を数える範囲。ホームの習熟度と同じ設定を共有する
    /// （同じ「習得済み」が画面ごとに違う範囲で出ていると、どちらが本当か分からない）。
    var scope = StudySettings.masteryScope {
        didSet {
            guard scope != oldValue else { return }
            StudySettings.masteryScope = scope
        }
    }

    /// グラフに描く系列。長期間では週ごとにまとめてある。
    private(set) var series: [DailyStudy] = []
    /// 日次のままの系列。「学習した日数」は週にまとめると数えられなくなるため別に持つ。
    private(set) var dailySeries: [DailyStudy] = []
    private(set) var streak = 0

    private var progressRepository: ProgressRepository?

    var totalAttempts: Int { StudyHistory.totalAttempts(in: dailySeries) }
    var overallAccuracy: Double { StudyHistory.overallAccuracy(in: dailySeries) }
    var studiedDayCount: Int { dailySeries.filter(\.didStudy).count }
    var hasAnyRecord: Bool { totalAttempts > 0 }

    /// 習得済みの問題数の折れ線。内訳を持たない日は点を打たない。
    var masteryPoints: [MasteryPoint] {
        series.compactMap { entry in
            entry.masteredCount(scope: scope).map { MasteryPoint(date: entry.date, count: $0) }
        }
    }

    /// 絞り込みに必要な内訳が無い日があるか。
    var hasDaysWithoutBreakdown: Bool {
        series.contains { $0.masteredCount(scope: scope) == nil }
    }

    /// 期間の終わりの時点で「習得済み」だった問題数
    var masteredQuestionCount: Int { masteryPoints.last?.count ?? 0 }
    /// 期間中の増加分。伸びが見えると継続の動機になる。
    var masteredGain: Int {
        guard let first = masteryPoints.first, let last = masteryPoints.last else { return 0 }
        return max(0, last.count - first.count)
    }

    func configure(context: ModelContext) {
        guard progressRepository == nil else { return }
        progressRepository = ProgressRepository(context: context)
        reload()
    }

    func reload() {
        guard let progressRepository else { return }
        // 折れ線の開始値を引き継ぐため、期間より少し前のログも読む
        let logs = progressRepository.recentLogs(days: selectedPeriod.days + 7)
        var daily = StudyHistory.series(logs: logs, days: selectedPeriod.days)

        // 右端は「いま」の値にする。
        // ログに焼いてあるのは解答した瞬間の値で、その後に復習期限が来た問題は
        // 「要復習」へ戻る。凍結値のままだと、時間が経つほど一覧やホームの数と食い違う。
        if !daily.isEmpty {
            let live = progressRepository.masteredSnapshot()
            daily[daily.count - 1].masteredQuestionCount = live.total
            daily[daily.count - 1].masteredBreakdown = live.breakdown
        }

        // 集計後の系列（グラフ描画用）と、日次の系列（合計値の算出用）を分けて持つ
        dailySeries = daily
        series = selectedPeriod.aggregatesByWeek ? StudyHistory.weekly(from: daily) : daily

        streak = StudyHistory.currentStreak(logs: progressRepository.logsForStreak())
    }
}
