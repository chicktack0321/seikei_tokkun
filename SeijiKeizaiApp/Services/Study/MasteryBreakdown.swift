import Foundation

/// 「習得済み」の問題数を集計範囲で絞れるようにするための内訳。
///
/// 習熟の推移は日ごとのスナップショットでしか残せない（`UserProgress` は現在の状態しか持たず、
/// 過去に遡って再計算できない）。合計値だけを焼いていると後から分野や難易度で分けられないため、
/// 「中分類×難易度」のセルごとに数えて保存する。
/// 単一軸の合計を持つ方式では「セキュリティかつ応用」のような組み合わせを復元できない。
///
/// 分野ではなく中分類をキーにしているのは、分野は中分類から一意に決まるため。
/// 分野で焼くと中分類での絞り込みが後から作れない。
enum MasteryBreakdown {
    static func key(for question: QuestionMaster) -> String {
        "\(question.midCategoryRaw)|\(question.difficultyRaw)"
    }

    /// 内訳から、指定した範囲に入る問題数を合計する
    static func count(in breakdown: [String: Int], scope: StudyScope) -> Int {
        breakdown.reduce(into: 0) { total, entry in
            if matches(key: entry.key, scope: scope) { total += entry.value }
        }
    }

    private static func matches(key: String, scope: StudyScope) -> Bool {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let midCategory = MidCategory(rawValue: String(parts[0])),
              let difficultyRaw = Int(parts[1]),
              let difficulty = QuestionDifficulty(rawValue: difficultyRaw)
        else { return false }

        if let selected = scope.midCategory, selected != midCategory { return false }
        if let field = scope.field, midCategory.field != field { return false }
        if let selected = scope.difficulty, selected != difficulty { return false }
        return true
    }
}

/// ある時点で「習得済み」段階にある問題の数と、その内訳
struct MasterySnapshot: Equatable {
    var total: Int
    var breakdown: [String: Int]

    static let empty = MasterySnapshot(total: 0, breakdown: [:])

    func count(scope: StudyScope) -> Int {
        scope.isDefault ? total : MasteryBreakdown.count(in: breakdown, scope: scope)
    }

    /// 分野ごとの習得済み数。分野で配点の比重が違うため、ホームの主表示に使う
    func countsByField() -> [ExamField: Int] {
        var result: [ExamField: Int] = [:]
        for (key, value) in breakdown {
            guard let midCategoryRaw = key.split(separator: "|").first,
                  let midCategory = MidCategory(rawValue: String(midCategoryRaw))
            else { continue }
            result[midCategory.field, default: 0] += value
        }
        return result
    }
}
