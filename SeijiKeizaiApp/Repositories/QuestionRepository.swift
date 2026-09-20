import Foundation
import SwiftData

/// QuestionMaster への問い合わせを集約する。
/// ViewModelがSwiftDataのクエリ構文に直接依存しないようにする層。
@MainActor
struct QuestionRepository {
    let context: ModelContext

    func fetchAll() -> [QuestionMaster] {
        (try? context.fetch(FetchDescriptor<QuestionMaster>(sortBy: [SortDescriptor(\.questionId)]))) ?? []
    }

    func fetchCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<QuestionMaster>())) ?? 0
    }

    /// 演習の出題母集団。完全無料なので、絞るのは利用者が選んだ範囲（`StudyScope`）だけ。
    func fetchStudyPool(scope: StudyScope = StudySettings.studyScope) -> [QuestionMaster] {
        fetchAll().filter { scope.contains($0) }
    }

    /// 習熟度の集計など、出題ではない用途で範囲を適用する
    func fetchQuestions(matching scope: StudyScope) -> [QuestionMaster] {
        fetchAll().filter { scope.contains($0) }
    }

    /// 指定した範囲に入る問題数。出題を始める前に「この条件で何問あるか」を見せるために使う
    func countStudyPool(scope: StudyScope) -> Int {
        fetchStudyPool(scope: scope).count
    }

    /// 難易度ごとの問題数
    func count(difficulty: QuestionDifficulty) -> Int {
        let raw = difficulty.rawValue
        let descriptor = FetchDescriptor<QuestionMaster>(predicate: #Predicate { $0.difficultyRaw == raw })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// 分野ごとの問題数。ホームの分野別習熟度で分母に使う
    func countsByField() -> [ExamField: Int] {
        fetchAll().reduce(into: [:]) { counts, question in
            counts[question.field, default: 0] += 1
        }
    }
}
