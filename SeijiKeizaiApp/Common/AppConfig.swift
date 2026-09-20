import Foundation

/// アプリ全体で使う固定値と、外部に公開しているURLの置き場所。
///
/// 試験名・公開URL・権利表記がコードのあちこちに散っていると、変更のたびに取りこぼす。
/// ここ1か所にまとめる。
enum AppConfig {

    // MARK: - 試験

    /// 画面に出す試験・科目名
    static let examDisplayName = "共通テスト 公共，政治・経済"

    /// アプリ名（ホーム画面のアイコン下は Info.plist の CFBundleDisplayName が担う）
    static let appDisplayName = "公共・政治経済特訓"

    /// 同梱する問題データ（拡張子を除いたファイル名）
    static let seedResourceName = "question_master_seed"

    // MARK: - 試験制度

    /// 試験時間（分）と満点。公民科の各科目は60分・100点。
    static let examDurationMinutes = 60
    static let examFullScore = 100

    /// 出題の構成。年度ごとに大問構成は動くため、点数そのものではなく目安として見せる。
    static let examStructure = """
    「公共」と「政治・経済」の2部構成で、『公共』からおよそ4分の1が出題されます。\
    資料・会話文を読み取らせる問題が多く、用語を覚えるだけでは解き切れません。
    """

    /// 学習の指針。数字を画面に散らすと改定時に取りこぼすためここに置く。
    static let studyAdvice = """
    用語の暗記に加えて、制度の「原則と例外」「日本と諸外国の違い」を説明できるかが分かれ目になります。\
    このアプリでは、正解の理由だけでなく誤答の選択肢がそれぞれ何を指しているかまで解説します。
    """

    // MARK: - 権利表記

    /// 大学入試センターが実施する試験。提携していると誤解させないため、アプリ内に常設する。
    static let trademarkNotice = """
    大学入学共通テストは独立行政法人 大学入試センターが実施する試験です。\
    本アプリは同センターが承認・許諾したものではありません。\
    出題内容は公表されている出題範囲と高等学校学習指導要領に基づく独自作成の問題です。
    """

    /// 完全無料であることの明示。App内課金・広告・サブスクリプションは実装しない。
    static let freeNotice = """
    このアプリは完全無料です。App内課金・広告・サブスクリプションはありません。\
    通信も行わないため、学習の記録は端末内にのみ保存されます。
    """

    // MARK: - 公開ページ

    /// App Store Connect にも同じURLを登録する（プライバシーポリシーは全アプリで必須）
    /// TODO: 公開前に実際のURLへ差し替える
    static let privacyPolicyURL = URL(string: "https://sites.google.com/view/seikei-tokkun/privacy-policy")!
    static let supportURL = URL(string: "https://sites.google.com/view/seikei-tokkun/support")!
}
