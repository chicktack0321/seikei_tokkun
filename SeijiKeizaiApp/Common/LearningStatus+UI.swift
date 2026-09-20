import SwiftUI

// 色は SwiftUI に依存するため、モデル側の enum ではなくUI層で持たせる。
extension LearningStatus {
    var tint: Color {
        switch self {
        case .notStudied: return .secondary
        case .needsReview: return .orange
        case .learning: return .blue
        case .memorized: return .green
        }
    }

    /// 習熟度バーで使う色。未学習だけは背景に馴染む灰色にする。
    var barColor: Color {
        self == .notStudied ? Color(.systemGray4) : tint
    }
}

/// 数値の意味をその場で説明するための「i」ボタン。
/// 正答率や習熟度は定義が分からないと解釈できず、誤解したまま一喜一憂させてしまうため、
/// 説明を画面の外（ヘルプやREADME）に置かず、指標のすぐ隣から開けるようにしている。
///
/// 表示にはポップオーバーではなくシートを使う。
/// iPhone（コンパクト幅）のポップオーバーは吹き出しの矢印を指標の隣に合わせようとするため、
/// 画面端に近いiマークだと本文の幅・高さが詰められて説明が見切れていた。
/// シートなら幅は常に画面いっぱいで、収まらない長さでもスクロールで最後まで読める。
struct InfoButton: View {
    let title: String
    let message: String

    @State private var isPresented = false
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        Button {
            // 開く前に高さを決めておく。提示後にディテントを差し替えると開いた直後に
            // シートが伸び縮みして落ち着かないため。
            detent = Self.preferredDetent(for: message)
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                // 文字サイズのままだと的が小さく押しづらい。見た目の大きさは変えたくないので、
                // frameではなく当たり判定だけを外側に広げる。
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)の説明")
        .sheet(isPresented: $isPresented) {
            InfoSheet(title: title, message: message)
                .presentationDetents([.medium, .large], selection: $detent)
                .presentationDragIndicator(.visible)
        }
    }

    /// 習熟度の説明のように段階の一覧を含む長文は、開いた時点で全文が見えるよう全画面から始める。
    /// 短い説明まで全画面にすると、1行読むために画面を覆われて煩わしい。
    private static func preferredDetent(for message: String) -> PresentationDetent {
        message.count > 160 ? .large : .medium
    }
}

/// iマークから開く説明シート。本文は必ずスクロールできる状態で置き、
/// 文字サイズを大きくしている利用者でも末尾まで読めるようにする。
private struct InfoSheet: View {
    let title: String
    let message: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(message)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
