import Foundation
import SwiftData

/// JSONデコード用のDTO。SwiftDataの `@Model` と分離しておくことで、
/// マスターデータの配布フォーマットを自由に差し替えられるようにする。
private struct QuestionSeedFile: Decodable {
    let version: Int
    let curriculumVersion: String
    let questions: [QuestionSeedEntry]
}

private struct QuestionSeedEntry: Decodable {
    let questionId: String
    let questionText: String
    let choices: [String: String]
    let correctChoice: String
    let explanation: String
    let choiceExplanations: [String: String]
    let field: String
    let midCategory: String
    let keywords: [String]?
    let difficulty: Int?
    /// 問題ごとに版を上書きできる。制度改正で一部だけ差し替える運用のため
    let curriculumVersion: String?
}

enum QuestionMasterSeederError: Error {
    case seedFileNotFound
    case decodeFailed(Error)
}

/// アプリ起動時に「マスターデータ（QuestionMaster）」を最新へUpsertしつつ、
/// 「学習履歴（UserProgress）」は一切手を触れずに保持するための初期化処理。
@MainActor
enum QuestionMasterSeeder {
    /// UserDefaults に保存する、直近で適用した seed のバージョン番号
    private static let appliedVersionKey = "questionMasterSeedVersion"

    /// アプリ起動時に一度だけ呼び出す。バンドル同梱JSONのバージョンが
    /// 既適用バージョンより新しい場合のみ Upsert を実行する（毎起動フルスキャンを避ける）。
    static func seedIfNeeded(context: ModelContext, bundle: Bundle = .main) throws {
        let seedFile = try loadSeedFile(bundle: bundle)

        let appliedVersion = UserDefaults.standard.integer(forKey: appliedVersionKey)
        // 適用済みバージョンは UserDefaults、実データは SwiftData と保存先が分かれているため、
        // 両者が食い違うことがある（ストアの作り直し、バックアップからの復元など）。
        // 問題が1件も無ければバージョンに関わらず作り直して、空のまま復旧しない状態を防ぐ。
        let existingCount = (try? context.fetchCount(FetchDescriptor<QuestionMaster>())) ?? 0
        let storeIsEmpty = existingCount == 0
        guard seedFile.version > appliedVersion || storeIsEmpty else { return }

        do {
            try upsert(file: seedFile, context: context)
            try context.save()
        } catch {
            // 中途半端に適用された変更を残すと次回以降の判定が狂うため、破棄してから投げ直す
            context.rollback()
            throw error
        }

        // 保存が成功して初めてバージョンを記録する。
        // 逆順にすると save 失敗時に「バージョンだけ進んで問題が空」の状態が永続化され、
        // 以降シードがスキップされて二度と復旧しなくなる。
        UserDefaults.standard.set(seedFile.version, forKey: appliedVersionKey)
    }

    private static func loadSeedFile(bundle: Bundle) throws -> QuestionSeedFile {
        guard let url = bundle.url(forResource: AppConfig.seedResourceName, withExtension: "json") else {
            throw QuestionMasterSeederError.seedFileNotFound
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(QuestionSeedFile.self, from: data)
        } catch {
            throw QuestionMasterSeederError.decodeFailed(error)
        }
    }

    /// 既存の `questionId` は上書き更新、未知の `questionId` は新規追加する（= Upsert）。
    private static func upsert(file: QuestionSeedFile, context: ModelContext) throws {
        // 既存マスターを questionId でインデックス化し、更新のたびにフェッチしないようにする
        let existing = try context.fetch(FetchDescriptor<QuestionMaster>())
        var existingById = Dictionary(existing.map { ($0.questionId, $0) }, uniquingKeysWith: { first, _ in first })

        for entry in file.questions {
            // 壊れた1問でシード全体を失敗させない。分類やラベルが未知の値なら黙って飛ばす
            // （シードの妥当性はビルド時のスクリプトとテストで担保する）
            guard
                let field = ExamField(rawValue: entry.field),
                let midCategory = MidCategory(rawValue: entry.midCategory),
                let correctChoice = ChoiceLabel(rawValue: entry.correctChoice),
                let a = entry.choices[ChoiceLabel.a.rawValue],
                let b = entry.choices[ChoiceLabel.b.rawValue],
                let c = entry.choices[ChoiceLabel.c.rawValue],
                let d = entry.choices[ChoiceLabel.d.rawValue]
            else { continue }

            let difficulty = entry.difficulty.flatMap(QuestionDifficulty.init(rawValue:)) ?? .standard
            let curriculumVersion = entry.curriculumVersion ?? file.curriculumVersion
            let explanations = entry.choiceExplanations

            if let question = existingById[entry.questionId] {
                question.questionText = entry.questionText
                question.choiceA = a
                question.choiceB = b
                question.choiceC = c
                question.choiceD = d
                question.correctChoice = correctChoice
                question.explanation = entry.explanation
                question.explanationA = explanations[ChoiceLabel.a.rawValue] ?? ""
                question.explanationB = explanations[ChoiceLabel.b.rawValue] ?? ""
                question.explanationC = explanations[ChoiceLabel.c.rawValue] ?? ""
                question.explanationD = explanations[ChoiceLabel.d.rawValue] ?? ""
                question.field = field
                question.midCategory = midCategory
                question.keywords = entry.keywords ?? []
                question.curriculumVersion = curriculumVersion
                question.difficulty = difficulty
                question.updatedAt = .now
                existingById.removeValue(forKey: entry.questionId)
            } else {
                context.insert(
                    QuestionMaster(
                        questionId: entry.questionId,
                        questionText: entry.questionText,
                        choiceA: a,
                        choiceB: b,
                        choiceC: c,
                        choiceD: d,
                        correctChoice: correctChoice,
                        explanation: entry.explanation,
                        explanationA: explanations[ChoiceLabel.a.rawValue] ?? "",
                        explanationB: explanations[ChoiceLabel.b.rawValue] ?? "",
                        explanationC: explanations[ChoiceLabel.c.rawValue] ?? "",
                        explanationD: explanations[ChoiceLabel.d.rawValue] ?? "",
                        field: field,
                        midCategory: midCategory,
                        keywords: entry.keywords ?? [],
                        curriculumVersion: curriculumVersion,
                        difficulty: difficulty
                    )
                )
            }
        }

        // 新しいseedに含まれなくなった問題（誤りが見つかって取り下げた問題など）はマスターから除去する。
        // UserProgress側は意図的に触らない = 学習履歴は残り続けるが、参照先の問題が消えても実害はない
        // （UI側は QuestionMaster が存在する行だけを表示するため、孤立した進捗レコードは表示されなくなるだけ）。
        for orphan in existingById.values {
            context.delete(orphan)
        }
    }
}

// 進捗行（UserProgress）はここでは作らない。
// 問題が数百問規模になると、未学習のまま一度も使わない空の行を同じ数だけ作ることになり、
// 初回起動と各画面の集計がそのぶん重くなる。行は最初に解答した時点で
// `ProgressRepository.progress(for:)` が作る。
// 「未学習」の問題数は行の有無ではなく、全問数から学習済みの問題数を引いて求める。
