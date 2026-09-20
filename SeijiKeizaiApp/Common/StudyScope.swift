import Foundation

/// 出題・集計の対象範囲。
///
/// 演習の出題範囲と、ホームの習熟度の内訳で共有する。
/// 全問をひとまとめに扱うと習熟度のバーはほとんど動かず、出題も単元が散らばって
/// 「いま何を潰しているのか」が分からなくなる。範囲を狭められること自体が機能。
///
/// 参考元（ITパスポート版）は「購入・試用で使える難易度」との積を取っていたが、
/// 本アプリは完全無料で全問が常に出題対象のため、その軸は持たない。
struct StudyScope: Equatable, Codable {
    /// nil は「全分野」。中分類を選んだ場合は、そちらが分野を含意する
    var field: ExamField?
    /// nil は「その分野のすべて」
    var midCategory: MidCategory?
    /// nil は「すべての難易度」
    var difficulty: QuestionDifficulty?

    static let `default` = StudyScope()

    var isDefault: Bool { self == .default }

    /// 実際に対象とする分野。中分類を選んでいればそれが優先される
    var effectiveField: ExamField? {
        midCategory?.field ?? field
    }

    /// 画面に出す1行の説明。指定した条件だけを並べる
    var summary: String {
        var parts: [String] = []
        if let midCategory {
            parts.append(midCategory.displayName)
        } else if let field {
            parts.append(field.displayName)
        }
        if let difficulty { parts.append(difficulty.displayName) }
        return parts.isEmpty ? "すべて" : parts.joined(separator: " / ")
    }

    /// この問題が範囲に入るか
    func contains(_ question: QuestionMaster) -> Bool {
        if let difficulty, question.difficulty != difficulty { return false }
        if let midCategory {
            return question.midCategory == midCategory
        }
        if let field, question.field != field { return false }
        return true
    }

    /// 分野を変えたら、その分野に属さない中分類の選択は捨てる。
    /// 残すと「政治 / 金融」のような0問確定の組み合わせが作れてしまう。
    mutating func setField(_ newField: ExamField?) {
        field = newField
        if let midCategory, midCategory.field != newField {
            self.midCategory = nil
        }
    }
}
