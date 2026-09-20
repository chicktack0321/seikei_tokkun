import Foundation
import SwiftData

/// ユーザーの学習履歴。マスターデータの更新（Upsert/総入れ替え）を跨いで必ず保持される Read-Write テーブル。
@Model
final class UserProgress {
    /// `QuestionMaster.questionId` と対応する外部キー相当
    /// （正式なリレーションは張らない。理由は QuestionMaster 側コメント参照）
    @Attribute(.unique) var questionId: String

    var lastReviewedAt: Date?

    /// 正解した累計回数
    var correctCount: Int
    /// 出題された累計回数（正答率 = correctCount / attemptCount）
    var attemptCount: Int

    /// Leitnerボックス方式の段階（0が最短間隔）。正解でひとつ上へ、不正解で0に戻る。
    /// 既存データにこの列が無い状態からのアップデートでも軽量マイグレーションで既定値が入るよう、
    /// 省略可能な初期値を持たせている。
    var reviewBox: Int = 0

    /// 次に出題すべき日時。nil は「まだ一度も解いていない＝いつでも出題してよい」を表す
    var nextReviewAt: Date?

    init(
        questionId: String,
        lastReviewedAt: Date? = nil,
        correctCount: Int = 0,
        attemptCount: Int = 0,
        reviewBox: Int = 0,
        nextReviewAt: Date? = nil
    ) {
        self.questionId = questionId
        self.lastReviewedAt = lastReviewedAt
        self.correctCount = correctCount
        self.attemptCount = attemptCount
        self.reviewBox = reviewBox
        self.nextReviewAt = nextReviewAt
    }

    /// 習熟段階は保存せず、間隔反復の進み具合から常に導出する。
    /// 別々に保存すると「箱は進んでいるのにステータスは要復習のまま」といった食い違いが起きうるため、
    /// 判断の根拠を `reviewBox` ひとつに集約している。
    func status(at date: Date = .now) -> LearningStatus {
        guard attemptCount > 0 else { return .notStudied }
        if isDue(at: date) { return .needsReview }
        return reviewBox >= Self.masteredBox ? .memorized : .learning
    }

    /// 画面表示用。判定時刻を指定しない場合は現在時刻で評価する。
    var status: LearningStatus { status() }

    var accuracy: Double {
        attemptCount == 0 ? 0 : Double(correctCount) / Double(attemptCount)
    }

    /// 解答の正誤を記録し、習得段階と次回の復習日を更新する
    func record(isCorrect: Bool, reviewedAt: Date = .now, calendar: Calendar = .current) {
        attemptCount += 1
        lastReviewedAt = reviewedAt
        if isCorrect {
            correctCount += 1
            reviewBox = min(reviewBox + 1, Self.maxReviewBox)
        } else {
            // 間違えた問題は最短間隔に戻し、その日のうちにまた出題されるようにする
            reviewBox = 0
        }
        nextReviewAt = Self.nextReviewDate(box: reviewBox, from: reviewedAt, calendar: calendar)
    }

    /// 「この問題をもう一度やり直す」操作。最短間隔に戻してすぐ出題対象にする。
    func markForReview(at date: Date = .now, calendar: Calendar = .current) {
        reviewBox = 0
        if attemptCount == 0 { attemptCount = 1 }
        nextReviewAt = Self.nextReviewDate(box: 0, from: date, calendar: calendar)
    }

    /// 「この問題は分かっている」操作。既に確実な問題を毎回出題されないようにするための逃げ道。
    func markAsMemorized(at date: Date = .now, calendar: Calendar = .current) {
        reviewBox = max(reviewBox, Self.masteredBox)
        if attemptCount == 0 { attemptCount = 1 }
        nextReviewAt = Self.nextReviewDate(box: reviewBox, from: date, calendar: calendar)
    }

    /// 指定時点で復習期限が来ているか。未出題（nextReviewAtがnil）の問題も対象に含める。
    func isDue(at date: Date = .now) -> Bool {
        guard let nextReviewAt else { return true }
        return nextReviewAt <= date
    }
}

// MARK: - 間隔反復（Leitnerボックス）

extension UserProgress {
    /// 段階ごとの復習間隔（日数）。正解を重ねるほど間隔が伸び、忘れかけたタイミングで再出題される。
    /// SM-2のような可変難易度は持たせず、動作が予測しやすい固定テーブルにしている。
    static let reviewIntervalDays = [0, 1, 3, 7, 14, 30]

    static var maxReviewBox: Int { reviewIntervalDays.count - 1 }

    /// ここに到達したら「習得済み」とみなす段階。
    /// 間隔7日にあたり、「1週間あけても解けた」ことが条件になる。
    /// 直前に正解しただけで習得扱いにすると、本番では解けない問題まで含まれてしまう。
    static let masteredBox = 3

    static func intervalDays(forBox box: Int) -> Int {
        let index = min(max(box, 0), maxReviewBox)
        return reviewIntervalDays[index]
    }

    /// 次回復習日を求める。時刻ではなく「日」単位で揃えることで、
    /// 朝に解いても夜に解いても同じ日に復習期限が来るようにしている。
    static func nextReviewDate(box: Int, from date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let days = intervalDays(forBox: box)
        return calendar.date(byAdding: .day, value: days, to: startOfDay) ?? date
    }
}
