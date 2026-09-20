import Observation

enum AppTab: Hashable {
    case home, quiz, questionList, history
}

/// 演習の出題対象。
///
/// `onChange(of:)` で監視するため Equatable にしている。
enum QuizScope: Equatable {
    /// 復習期限が来た問題を優先しつつ、足りなければ未学習の問題で埋める（通常の学習）
    case mixed
    /// 復習期限が来た問題だけを出題する。ホームの「復習する問題がN問あります」から入るときに使う。
    case reviewOnly
    /// 直前のセットで間違えた問題だけを解き直す
    case retryMissed(questionIds: [String])

    var title: String {
        switch self {
        case .mixed: return "演習"
        case .reviewOnly: return "復習"
        case .retryMissed: return "間違えた問題"
        }
    }

    /// 出題対象が0問だったときの案内。
    /// 「復習を解き終えて期限切れの問題が無くなった」は正常な結果なので、
    /// エラーではなく状況の説明として見せる。
    var emptyNotice: String {
        switch self {
        case .mixed: return "この出題範囲に問題がありません。絞り込みを緩めてください。"
        case .reviewOnly: return "復習の期限が来ている問題はありません。おつかれさまでした。"
        case .retryMissed: return "解き直す問題がありません。"
        }
    }
}

/// ホーム画面のクイックアクションから、TabViewの選択タブをコード側から切り替えるための共有ルーター。
@Observable
@MainActor
final class TabRouter {
    var selectedTab: AppTab = .home

    /// 次に演習画面が開かれたときに、この条件で自動的に開始する。
    /// ホームの復習ボタンが「復習する」と言いながら通常出題を始めてしまうのを避けるため、
    /// 遷移とあわせて出題対象を渡している。
    var pendingQuizScope: QuizScope?

    func startQuiz(scope: QuizScope) {
        pendingQuizScope = scope
        selectedTab = .quiz
    }

    /// 演習画面が受け取ったら消費する（戻ってくるたびに再開始しないように）
    func consumePendingQuizScope() -> QuizScope? {
        defer { pendingQuizScope = nil }
        return pendingQuizScope
    }
}
