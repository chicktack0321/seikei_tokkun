import Foundation

/// グラフ1本分の日次データ。学習していない日も0として含めるため、
/// `StudyLog` をそのまま使わず値型に詰め替える。
struct DailyStudy: Identifiable, Equatable {
    let date: Date
    let studiedQuestionCount: Int
    let correctCount: Int
    let attemptCount: Int
    /// その日時点で「覚えた」だった語数。学習しなかった日は直前の値を引き継ぐ。
    var masteredQuestionCount: Int = 0
    /// 上の内訳。集計範囲で絞ったグラフを描くために使う（`MasteryBreakdown`）。
    var masteredBreakdown: [String: Int] = [:]

    var id: Date { date }

    /// 集計範囲で絞った「覚えた」語数。
    /// 内訳を持たない日（この機能より前に記録された日）は絞り込めないので nil を返す。
    func masteredCount(scope: StudyScope) -> Int? {
        if scope.isDefault || masteredQuestionCount == 0 { return masteredQuestionCount }
        guard !masteredBreakdown.isEmpty else { return nil }
        return MasteryBreakdown.count(in: masteredBreakdown, scope: scope)
    }

    var accuracy: Double {
        attemptCount == 0 ? 0 : Double(correctCount) / Double(attemptCount)
    }

    /// その日に学習したか（連続日数の判定に使う）
    var didStudy: Bool { studiedQuestionCount > 0 }
}

/// 学習履歴の集計。日付の扱いを間違えると「グラフが1日ずれる」「連続日数が途切れる」といった
/// 見つけにくい不具合になるため、SwiftDataに触れない純粋関数にしてユニットテストしている。
enum StudyHistory {

    /// 直近 `days` 日分の日次データを、古い順・欠損日を0埋めして返す。
    /// 学習していない日を飛ばすとグラフの横軸が詰まって推移が読めなくなるため、必ず埋める。
    static func series(
        logs: [StudyLog],
        days: Int,
        endingOn today: Date = .now,
        calendar: Calendar = .current
    ) -> [DailyStudy] {
        guard days > 0 else { return [] }

        let endDay = calendar.startOfDay(for: today)
        // 同じ日のログが複数あっても最後の1件に寄せる（通常は @Attribute(.unique) で1件）
        let logsByDay = Dictionary(
            logs.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        // 期間より前の記録から、開始時点の習熟度を引き継ぐ。
        // 期間内に学習日が無いと折れ線が0から始まり、実際には覚えている語が
        // 消えたように見えてしまうため。
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
        let previous = logs
            .filter { calendar.startOfDay(for: $0.date) < startDay }
            .max(by: { $0.date < $1.date })
        var carriedMastered = previous?.masteredQuestionCount ?? 0
        var carriedBreakdown = previous?.masteredBreakdown ?? [:]

        return (0..<days).reversed().compactMap { offset -> DailyStudy? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else { return nil }
            let log = logsByDay[day]
            if let log {
                carriedMastered = log.masteredQuestionCount
                carriedBreakdown = log.masteredBreakdown
            }
            return DailyStudy(
                date: day,
                studiedQuestionCount: log?.studiedQuestionCount ?? 0,
                correctCount: log?.correctCount ?? 0,
                attemptCount: log?.attemptCount ?? 0,
                masteredQuestionCount: carriedMastered,
                masteredBreakdown: carriedBreakdown
            )
        }
    }

    /// 日次データを週単位にまとめる。
    /// 3か月以上を日ごとに描くと棒が1px以下になって読めないため、長期間の表示で使う。
    /// 解答数は合計、習熟度はその週の最終値（推移として見たいのは残高であって合計ではない）。
    static func weekly(
        from series: [DailyStudy],
        calendar: Calendar = .current
    ) -> [DailyStudy] {
        guard !series.isEmpty else { return [] }

        var buckets: [(start: Date, days: [DailyStudy])] = []
        for day in series {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: day.date)?.start
                ?? calendar.startOfDay(for: day.date)
            if let last = buckets.last, last.start == weekStart {
                buckets[buckets.count - 1].days.append(day)
            } else {
                buckets.append((weekStart, [day]))
            }
        }

        return buckets.map { bucket in
            DailyStudy(
                date: bucket.start,
                studiedQuestionCount: bucket.days.reduce(0) { $0 + $1.studiedQuestionCount },
                correctCount: bucket.days.reduce(0) { $0 + $1.correctCount },
                attemptCount: bucket.days.reduce(0) { $0 + $1.attemptCount },
                masteredQuestionCount: bucket.days.last?.masteredQuestionCount ?? 0,
                masteredBreakdown: bucket.days.last?.masteredBreakdown ?? [:]
            )
        }
    }

    /// 現在の連続学習日数。
    ///
    /// 当日まだ学習していなくても前日までの記録は途切れていないものとして数える。
    /// そうしないと、朝アプリを開いた瞬間に連続日数が0に見えてしまい、
    /// 続ける動機付けという本来の役割を果たさなくなる。
    static func currentStreak(
        logs: [StudyLog],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let studiedDays = Set(
            logs.filter { $0.studiedQuestionCount > 0 }
                .map { calendar.startOfDay(for: $0.date) }
        )
        guard !studiedDays.isEmpty else { return 0 }

        let startOfToday = calendar.startOfDay(for: today)
        // 当日の記録が無ければ前日を起点にする
        var cursor = studiedDays.contains(startOfToday)
            ? startOfToday
            : calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday

        var streak = 0
        while studiedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// 期間内の合計解答数（グラフの補足表示用）
    static func totalAttempts(in series: [DailyStudy]) -> Int {
        series.reduce(0) { $0 + $1.attemptCount }
    }

    /// 期間全体をならした正答率。日ごとの正答率を平均すると
    /// 1問しか解かなかった日が重く効いてしまうため、解答数で重み付けする。
    static func overallAccuracy(in series: [DailyStudy]) -> Double {
        let attempts = series.reduce(0) { $0 + $1.attemptCount }
        guard attempts > 0 else { return 0 }
        let correct = series.reduce(0) { $0 + $1.correctCount }
        return Double(correct) / Double(attempts)
    }
}
