import Foundation

/// 出題順を決めるロジック。
///
/// 学習アプリの価値は「忘れかけた問題を適切なタイミングで再提示すること」にあるため、
/// 毎回ランダムに出すのではなく次の優先度で並べる:
///
/// 1. 復習期限が来ている問題（間違えた問題・間隔が満了した問題）
/// 2. まだ一度も解いていない問題
/// 3. まだ期限前の問題（期限が近い順）
///
/// SwiftDataに触れない純粋関数にしてあるため、そのままユニットテストできる。
enum StudyQueue {
    static func prioritize(
        questions: [QuestionMaster],
        progress: [String: UserProgress],
        now: Date = .now
    ) -> [QuestionMaster] {
        var due: [QuestionMaster] = []
        var unstudied: [QuestionMaster] = []
        var scheduled: [(question: QuestionMaster, dueDate: Date)] = []

        for question in questions {
            guard let record = progress[question.questionId], record.attemptCount > 0 else {
                unstudied.append(question)
                continue
            }
            if let nextReviewAt = record.nextReviewAt {
                if nextReviewAt <= now {
                    due.append(question)
                } else {
                    scheduled.append((question, nextReviewAt))
                }
            } else {
                // 解いた記録はあるが日程が入っていない（旧バージョンからの移行データ）は復習対象として扱う
                due.append(question)
            }
        }

        // 同じ優先度の中では順番を固定したくないのでシャッフルする。
        // 期限前の問題だけは「期限が近い順」に意味があるため並びを保つ。
        due.shuffle()
        unstudied.shuffle()

        return due + unstudied + scheduled.sorted { $0.dueDate < $1.dueDate }.map(\.question)
    }

    /// 復習期限が来ている問題だけを返す。未学習の問題は「復習」ではないので含めない。
    /// ホームの「復習する問題がN問あります」から始める演習は、ここで返る問題だけを出題する。
    static func dueQuestions(
        questions: [QuestionMaster],
        progress: [String: UserProgress],
        now: Date = .now
    ) -> [QuestionMaster] {
        questions.filter { question in
            guard let record = progress[question.questionId], record.attemptCount > 0 else { return false }
            return record.isDue(at: now)
        }.shuffled()
    }

    /// 復習期限が来ている問題の件数（ホーム画面の「今日の復習」表示用）
    static func dueCount(
        questions: [QuestionMaster],
        progress: [String: UserProgress],
        now: Date = .now
    ) -> Int {
        questions.reduce(into: 0) { count, question in
            guard let record = progress[question.questionId], record.attemptCount > 0 else { return }
            if record.isDue(at: now) { count += 1 }
        }
    }

    /// 指定したIDの問題だけを、渡された順で取り出す。
    /// 「間違えた問題だけ解き直す」導線で使う（元のセットの出題順を保つ）。
    static func select(
        questionIds: [String],
        from questions: [QuestionMaster]
    ) -> [QuestionMaster] {
        let byId = Dictionary(questions.map { ($0.questionId, $0) }, uniquingKeysWith: { first, _ in first })
        return questionIds.compactMap { byId[$0] }
    }
}
