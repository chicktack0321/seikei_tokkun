import Foundation
import SwiftData
import os

/// SwiftDataの ModelContainer を一元管理する。
/// スキーマ変更（カラム追加等）は SwiftData の軽量マイグレーションで多くは自動対応できるが、
/// カラムのリネームや型変更のような破壊的変更が必要になった時点で
/// `SchemaMigrationPlan` を実装したVersionedSchemaに切り替える前提の置き場所として分離している。
@MainActor
enum AppContainer {
    private static let logger = Logger(subsystem: "com.eitango.seikei", category: "AppContainer")

    static let shared: ModelContainer = {
        let schema = Schema([
            QuestionMaster.self,
            UserProgress.self,
            StudyLog.self
        ])

        let container = makeContainer(schema: schema)

        // シードの失敗（同梱JSONの破損など）は致命的ではない。
        // ここでクラッシュさせるとアプリが二度と起動しなくなるため、記録だけして起動を続ける。
        // 問題が0件でも各画面は空状態を表示できる。
        do {
            try QuestionMasterSeeder.seedIfNeeded(context: container.mainContext)
        } catch {
            logger.error("問題マスターの初期化に失敗しました: \(error.localizedDescription, privacy: .public)")
        }

        return container
    }()

    /// 永続ストアの生成を試み、失敗した場合はインメモリにフォールバックする。
    /// ストアが壊れている・ディスクが逼迫している等で永続化できない状況でも、
    /// 「起動すらしない」よりは「今回の学習履歴は保存されないが使える」方が損害が小さいと判断している。
    private static func makeContainer(schema: Schema) -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )
        } catch {
            logger.error("永続ストアの初期化に失敗したためインメモリで起動します: \(error.localizedDescription, privacy: .public)")
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                // インメモリすら生成できないのはスキーマ定義自体の不整合であり、実行時に回復する手段がない
                fatalError("ModelContainerの初期化に失敗しました: \(error)")
            }
        }
    }
}
