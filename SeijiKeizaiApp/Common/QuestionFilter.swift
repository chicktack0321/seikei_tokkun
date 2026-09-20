import Foundation

/// 問題一覧の絞り込み条件。
///
/// 分野・中分類・難易度は `QuestionMaster`、学習ステータスは `UserProgress` と
/// 参照先が分かれるため、DB側の述語だけでは完結せず、ここでまとめて適用する。
struct QuestionFilter: Equatable {
    var field: ExamField?
    var midCategory: MidCategory?
    var difficulty: QuestionDifficulty?
    var status: LearningStatus?
    var keyword: String = ""

    var isEmpty: Bool {
        field == nil && midCategory == nil && difficulty == nil && status == nil
            && keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 分野を変えたら、その分野に属さない中分類の選択は捨てる（`StudyScope.setField` と同じ理由）
    mutating func setField(_ newField: ExamField?) {
        field = newField
        if let midCategory, midCategory.field != newField {
            self.midCategory = nil
        }
    }

    /// 選べる中分類。分野を選んでいればその分野のものだけに絞る
    var availableMidCategories: [MidCategory] {
        guard let field else { return MidCategory.allCases }
        return MidCategory.all(in: field)
    }

    /// 取得済みの配列に、ステータスと検索語を適用する
    func apply(
        to questions: [QuestionMaster],
        progress: [String: UserProgress],
        now: Date = .now
    ) -> [QuestionMaster] {
        var result = questions

        if let midCategory {
            result = result.filter { $0.midCategory == midCategory }
        } else if let field {
            result = result.filter { $0.field == field }
        }
        if let difficulty {
            result = result.filter { $0.difficulty == difficulty }
        }
        if let status {
            result = result.filter { question in
                let current = progress[question.questionId]?.status(at: now) ?? .notStudied
                return current == status
            }
        }

        // 検索は問題文とキーワードの両方に当てる。
        // 「ゼロトラスト」のように問題文へ直接現れない主題は、キーワード側でしか拾えない。
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { question in
                question.questionText.localizedCaseInsensitiveContains(trimmed)
                    || question.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }

        return result
    }
}
