import Foundation
import SwiftData

/// UserProgress / StudyLog への読み書きを集約する層
@MainActor
struct ProgressRepository {
    let context: ModelContext

    func progress(for questionId: String) -> UserProgress {
        let descriptor = FetchDescriptor<UserProgress>(predicate: #Predicate { $0.questionId == questionId })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = UserProgress(questionId: questionId)
        context.insert(created)
        return created
    }

    func allProgress() -> [String: UserProgress] {
        let all = (try? context.fetch(FetchDescriptor<UserProgress>())) ?? []
        return Dictionary(all.map { ($0.questionId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 1問の採点結果。呼び出し側が「習得済み」への到達を数えるのに使う
    struct AnswerOutcome {
        let wasMemorized: Bool
        let isMemorized: Bool

        var reachedMemorized: Bool { !wasMemorized && isMemorized }
    }

    /// 1問分の採点結果を UserProgress と当日の StudyLog の両方に反映する。
    ///
    /// ここは解答のたびに通る道なので、問題数ぶんの走査を持ち込まないこと。
    /// 当日の基準値はセッション開始時に `refreshMasterySnapshot` で作り、
    /// ここでは増減ぶんだけを足し引きする。
    ///
    /// - Parameter question: 呼び出し側が持っているものをそのまま渡す。
    ///   内訳のセルを決めるのに中分類と難易度が要るが、ここで引き直すと
    ///   1解答につき問題の取得が1回増える。
    @discardableResult
    func recordAnswer(question: QuestionMaster, isCorrect: Bool, at date: Date = .now) -> AnswerOutcome {
        let p = progress(for: question.questionId)
        let wasMemorized = p.status(at: date) == .memorized
        p.record(isCorrect: isCorrect, reviewedAt: date)
        let isMemorized = p.status(at: date) == .memorized

        // studiedQuestionCount は延べ数（同じ問題を複数回復習した場合もその都度カウント）とする。
        let log = studyLog(for: date)
        log.attemptCount += 1
        log.studiedQuestionCount += 1
        if isCorrect { log.correctCount += 1 }

        // 習熟度は現在の状態しか残らないので、その日の最新値を残しておく。
        // でないと推移グラフを後から描けない。増減はこの問題が境目をまたいだときだけ起きる。
        if wasMemorized != isMemorized {
            let delta = isMemorized ? 1 : -1
            log.masteredQuestionCount = max(0, log.masteredQuestionCount + delta)
            let key = MasteryBreakdown.key(for: question)
            let updated = (log.masteredBreakdown[key] ?? 0) + delta
            if updated > 0 {
                log.masteredBreakdown[key] = updated
            } else {
                log.masteredBreakdown.removeValue(forKey: key)
            }
        }

        // ここでは保存しない。1問ごとの save はそれ自体が待ち時間になる。
        // mainContext の自動保存に任せ、区切りで `save()` を呼ぶ。
        return AnswerOutcome(wasMemorized: wasMemorized, isMemorized: isMemorized)
    }

    /// 当日の「習得済み」問題数を数え直して焼き直す。
    ///
    /// 全問を走査するので、解答中には呼ばないこと。想定している呼び出し元は
    /// セッションの開始時、問題詳細で「習得済みにする」「やり直す」を押したとき、学習の記録を開いたとき。
    /// 日付をまたいで復習期限が来た問題や、解答を経ない状態変更はここで拾う。
    func refreshMasterySnapshot(at date: Date = .now) {
        let snapshot = masteredSnapshot(at: date)
        let log = studyLog(for: date)
        log.masteredQuestionCount = snapshot.total
        log.masteredBreakdown = snapshot.breakdown
    }

    /// 区切りでの保存。解答ごとには呼ばない
    func save() {
        try? context.save()
    }

    /// 指定時点で「習得済み」段階にある問題数と、その内訳。
    ///
    /// 問題マスターに実在する問題だけを数える。マスターを入れ替えても `UserProgress` は
    /// 残す設計（`QuestionMasterSeeder` 参照）なので、進捗の行を全部数えると、
    /// 取り下げた問題まで「習得済み」に含まれ、一覧やホームの習熟度と数が合わなくなる。
    func masteredSnapshot(at date: Date = .now) -> MasterySnapshot {
        let questions = (try? context.fetch(FetchDescriptor<QuestionMaster>())) ?? []
        let progressById = allProgress()

        var total = 0
        var breakdown: [String: Int] = [:]
        for question in questions {
            guard let progress = progressById[question.questionId],
                  progress.status(at: date) == .memorized else { continue }
            total += 1
            breakdown[MasteryBreakdown.key(for: question), default: 0] += 1
        }
        return MasterySnapshot(total: total, breakdown: breakdown)
    }

    private func studyLog(for date: Date) -> StudyLog {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<StudyLog>(predicate: #Predicate { $0.date == day })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = StudyLog(date: day)
        context.insert(created)
        return created
    }

    /// 直近 `days` 日分の日次ログを取得する。
    /// 全期間を読むと記録が増えるほど重くなるため、グラフに映る範囲だけを日付で絞る。
    func recentLogs(days: Int, endingOn today: Date = .now, calendar: Calendar = .current) -> [StudyLog] {
        let endDay = calendar.startOfDay(for: today)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else { return [] }

        let descriptor = FetchDescriptor<StudyLog>(
            predicate: #Predicate { $0.date >= startDay },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 連続学習日数の判定用。途切れを跨いで数えないよう、直近1年分あれば足りる。
    func logsForStreak(today: Date = .now, calendar: Calendar = .current) -> [StudyLog] {
        recentLogs(days: 366, endingOn: today, calendar: calendar)
    }

    /// 当日分の StudyLog を取得する（未学習日は nil。record時のように新規作成はしない）
    func todayLog(date: Date = .now) -> StudyLog? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<StudyLog>(predicate: #Predicate { $0.date == day })
        return try? context.fetch(descriptor).first
    }

    /// 指定した問題だけを対象に、ステータス内訳と累計正答率をまとめて返す。
    ///
    /// 進捗の行は「一度でも解いた問題」にしか無いので、行の側からではなく問題の側から引く
    /// （絞り込んだ問題に対する未学習数は、呼び出し側が問題数との差で求める）。
    func summarize(questions: [QuestionMaster]) -> ProgressSummary {
        let byId = allProgress()
        let rows = questions.compactMap { byId[$0.questionId] }
        return Self.summarize(progressRows: rows)
    }

    private static func summarize(progressRows: [UserProgress]) -> ProgressSummary {
        var statusCounts: [LearningStatus: Int] = Dictionary(
            uniqueKeysWithValues: LearningStatus.allCases.map { ($0, 0) }
        )
        var totalCorrect = 0
        var totalAttempts = 0

        for progress in progressRows {
            statusCounts[progress.status, default: 0] += 1
            totalCorrect += progress.correctCount
            totalAttempts += progress.attemptCount
        }

        return ProgressSummary(
            statusCounts: statusCounts,
            totalCorrect: totalCorrect,
            totalAttempts: totalAttempts
        )
    }
}

/// `UserProgress` 全体を1回走査して得られる集計値
struct ProgressSummary {
    var statusCounts: [LearningStatus: Int]
    var totalCorrect: Int
    var totalAttempts: Int

    static let empty = ProgressSummary(statusCounts: [:], totalCorrect: 0, totalAttempts: 0)

    func count(of status: LearningStatus) -> Int {
        statusCounts[status] ?? 0
    }

    /// 出題されたことのある問題に対する累計正答率
    var accuracy: Double {
        totalAttempts == 0 ? 0 : Double(totalCorrect) / Double(totalAttempts)
    }
}
