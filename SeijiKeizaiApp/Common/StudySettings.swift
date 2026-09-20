import Foundation

/// 出題範囲と集計範囲の設定。
///
/// 画面（View）だけでなく ViewModel やリポジトリからも読むため、
/// @AppStorage ではなく UserDefaults を直接扱うこの型に集約している。
enum StudySettings {
    private enum Key {
        static let studyScope = "studyScope"
        static let masteryScope = "masteryScope"
    }

    /// 演習の出題範囲
    static var studyScope: StudyScope {
        get { load(Key.studyScope) }
        set { save(newValue, to: Key.studyScope) }
    }

    /// ホームの習熟度で集計する範囲
    static var masteryScope: StudyScope {
        get { load(Key.masteryScope) }
        set { save(newValue, to: Key.masteryScope) }
    }

    // MARK: - 保存

    // 項目が増えるたびにキーを足していくと取りこぼすため、まとめてJSONで持つ
    private static func load(_ key: String) -> StudyScope {
        guard let data = UserDefaults.standard.data(forKey: key),
              let scope = try? JSONDecoder().decode(StudyScope.self, from: data)
        else { return .default }
        return scope
    }

    private static func save(_ scope: StudyScope, to key: String) {
        guard let data = try? JSONEncoder().encode(scope) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
