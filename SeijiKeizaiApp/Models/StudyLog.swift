import Foundation
import SwiftData

/// 日次の学習サマリー（解答数・正答率のローカル保存）。UserProgressとは別テーブルとし、
/// 「その日いくつ・何%正解したか」を集計コストなしで即座にグラフ表示できるようにする。
@Model
final class StudyLog {
    /// 日付キー（時刻を切り捨てた日単位、"yyyy-MM-dd" 相当をDateで保持）
    @Attribute(.unique) var date: Date

    /// 延べ解答数（同じ問題を複数回解いた場合もその都度カウント）
    var studiedQuestionCount: Int
    var correctCount: Int
    var attemptCount: Int

    /// その日の最後の解答時点で「習得済み」だった問題数。
    /// 習熟度の推移グラフは過去に遡って再計算できない（現在の状態しか残らない）ため、
    /// 解答のたびにその日のスナップショットを上書きして残しておく。
    var masteredQuestionCount: Int = 0

    /// 上の内訳（キーは `MasteryBreakdown` が決める）。
    /// 合計値だけでは分野や難易度で分けたグラフを描けないため、セルごとの数も残す。
    var masteredBreakdown: [String: Int] = [:]

    init(
        date: Date,
        studiedQuestionCount: Int = 0,
        correctCount: Int = 0,
        attemptCount: Int = 0,
        masteredQuestionCount: Int = 0,
        masteredBreakdown: [String: Int] = [:]
    ) {
        self.date = date
        self.studiedQuestionCount = studiedQuestionCount
        self.correctCount = correctCount
        self.attemptCount = attemptCount
        self.masteredQuestionCount = masteredQuestionCount
        self.masteredBreakdown = masteredBreakdown
    }

    var accuracy: Double {
        attemptCount == 0 ? 0 : Double(correctCount) / Double(attemptCount)
    }
}
