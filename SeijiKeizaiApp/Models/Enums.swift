import Foundation

/// 出題分野。大学入学共通テスト「公共，政治・経済」の構成に合わせた4分野。
///
/// 試験は「公共」と「政治・経済」の2部構成で、後者がおよそ4分の3を占める。
/// ただし「政治・経済」を1つの塊で扱うと、利用者にとっていちばん大きい経済分野の
/// 出来不出来が政治分野に紛れてしまう。習熟度の主軸として使うため、
/// 政治・経済・国際の3つに割って持つ。
enum ExamField: String, Codable, CaseIterable, Identifiable {
    case civics
    case politics
    case economics
    case international

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .civics: return "公共"
        case .politics: return "政治"
        case .economics: return "経済"
        case .international: return "国際"
        }
    }

    /// 本試験での配点の目安（100点中）。出題プールの構成比の目標に使う。
    ///
    /// 大問構成は年度ごとに動くため、点数そのものではなく「どの分野に厚みが要るか」の
    /// 目安として扱う（2025年度以降の「公共，政治・経済」は『公共』からおよそ4分の1）。
    var scoreWeight: Int {
        switch self {
        case .civics: return 25
        case .politics: return 25
        case .economics: return 30
        case .international: return 20
        }
    }

    var summary: String {
        switch self {
        case .civics: return "青年期・先哲の思想・公共的な空間・社会参画"
        case .politics: return "民主政治の原理・日本国憲法・人権・統治機構・選挙"
        case .economics: return "市場・国民所得・金融・財政・労働・社会保障"
        case .international: return "国際政治・国際機構・貿易と為替・地域統合と南北問題"
        }
    }
}

/// 中分類（単元）。
///
/// rawValue は `questionId` にも埋め込むため（`SEI_KINYU_0042`）、**公開後の改名は禁止**。
/// 改名は「削除+新規」になり、その問題の学習履歴が全ユーザーで失われる。
/// 学習指導要領の改訂で単元が増えたときは、既存を変えずにケースを追加する。
enum MidCategory: String, Codable, CaseIterable, Identifiable {
    // 公共
    case adolescence = "SEINEN"
    case thinkers = "SHISO"
    case ethics = "RINRI"
    case participation = "SANKA"
    // 政治
    case democracy = "MINSHU"
    case constitution = "KENPO"
    case humanRights = "JINKEN"
    case government = "TOCHI"
    case localGovernment = "CHIHO"
    case elections = "SENKYO"
    // 経済
    case economicSystem = "TAISEI"
    case market = "SHIJO"
    case nationalIncome = "SHOTOKU"
    case finance = "KINYU"
    case publicFinance = "ZAISEI"
    case japaneseEconomy = "NIHON"
    case labor = "ROUDOU"
    case socialSecurity = "SHAKAI"
    case consumerAndEnvironment = "SHOHI"
    // 国際
    case internationalPolitics = "ISEIJI"
    case unitedNations = "KOKUREN"
    case internationalEconomy = "IKEIZAI"
    case globalIssues = "NANBOKU"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adolescence: return "青年期と自己形成"
        case .thinkers: return "先哲の思想"
        case .ethics: return "公共的な空間と倫理"
        case .participation: return "社会参画と合意形成"
        case .democracy: return "民主政治の基本原理"
        case .constitution: return "日本国憲法と平和主義"
        case .humanRights: return "基本的人権"
        case .government: return "国会・内閣・裁判所"
        case .localGovernment: return "地方自治"
        case .elections: return "選挙・政党・世論"
        case .economicSystem: return "経済体制と資本主義"
        case .market: return "市場機構と企業"
        case .nationalIncome: return "国民所得と景気変動"
        case .finance: return "金融"
        case .publicFinance: return "財政と租税"
        case .japaneseEconomy: return "日本経済の歩み"
        case .labor: return "労働問題"
        case .socialSecurity: return "社会保障"
        case .consumerAndEnvironment: return "消費者問題と環境"
        case .internationalPolitics: return "国際政治と安全保障"
        case .unitedNations: return "国際機構と人権保障"
        case .internationalEconomy: return "貿易と国際収支"
        case .globalIssues: return "地域統合と南北問題"
        }
    }

    /// 属する分野。中分類を選んだら分野は自動的に決まる（両方をユーザーに選ばせない）
    var field: ExamField {
        switch self {
        case .adolescence, .thinkers, .ethics, .participation:
            return .civics
        case .democracy, .constitution, .humanRights, .government, .localGovernment, .elections:
            return .politics
        case .economicSystem, .market, .nationalIncome, .finance, .publicFinance,
             .japaneseEconomy, .labor, .socialSecurity, .consumerAndEnvironment:
            return .economics
        case .internationalPolitics, .unitedNations, .internationalEconomy, .globalIssues:
            return .international
        }
    }

    static func all(in field: ExamField) -> [MidCategory] {
        allCases.filter { $0.field == field }
    }
}

/// 問題の難易度。出題範囲を絞る軸であり、**課金の境界には使わない**（本アプリは完全無料）。
enum QuestionDifficulty: Int, Codable, CaseIterable, Identifiable {
    /// 用語の定義レベル。教科書の太字をそのまま問う
    case basic = 1
    /// 共通テストの中心レベル。制度の違い・原則と例外の使い分け
    case standard = 2
    /// 資料読解・計算・複数単元をまたぐ判断
    case advanced = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .basic: return "基礎"
        case .standard: return "標準"
        case .advanced: return "応用"
        }
    }

    var summary: String {
        switch self {
        case .basic: return "用語の意味を問う入門レベル"
        case .standard: return "共通テストの中心となるレベル"
        case .advanced: return "資料読解・計算・複合知識"
        }
    }
}

/// 選択肢のラベル。シードJSONのキーであり、表示順のシャッフル前の識別子でもある。
enum ChoiceLabel: String, Codable, CaseIterable, Identifiable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var id: String { rawValue }
}

/// 問題ごとの習熟段階。
///
/// 直近の正誤で反転させるのではなく、間隔反復の習得段階（`UserProgress.reviewBox`）から導く。
/// 1回正解しただけで「習得済み」にすると、実際には翌週忘れている問題まで習得扱いになり、
/// 習熟度の表示が学習の実態と乖離して意味を失う。
enum LearningStatus: String, Codable, CaseIterable, Identifiable {
    /// 一度も出題していない
    case notStudied
    /// 直近で間違えた、または復習期限が過ぎている
    case needsReview
    /// 正解を重ねている途中（復習間隔は1〜3日）
    case learning
    /// 1週間以上の間隔を空けても正解できた
    case memorized

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStudied: return "未学習"
        case .needsReview: return "要復習"
        case .learning: return "学習中"
        case .memorized: return "習得済み"
        }
    }

    /// この段階に到達する条件。画面上の「iマーク」でそのまま見せる。
    var criteria: String {
        switch self {
        case .notStudied: return "まだ一度も出題されていない問題です。"
        case .needsReview: return "直近で間違えたか、復習の期限が来ている問題です。優先して出題されます。"
        case .learning: return "正解を重ねている途中の問題です。1〜3日の間隔で再出題されます。"
        case .memorized: return "1週間以上あけても正解できた問題です。以後は間隔を広げて確認します。"
        }
    }

    /// 問題一覧・習熟度バー・凡例で同じ見た目にするため、記号と色は段階自身に持たせる
    var symbolName: String {
        switch self {
        case .notStudied: return "circle"
        case .needsReview: return "exclamationmark.circle.fill"
        case .learning: return "arrow.triangle.2.circlepath.circle.fill"
        case .memorized: return "checkmark.circle.fill"
        }
    }
}
