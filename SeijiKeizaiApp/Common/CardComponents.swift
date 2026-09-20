import SwiftUI

/// アプリ全体で使う「白いカード」の共通コンテナ。Home/Typing等、複数画面で見た目を揃えるために共有する。
struct DashboardCard<Content: View>: View {
    let title: String
    /// 指標の定義を説明する文。指定するとタイトルの右に「i」が出る。
    var infoMessage: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                if let infoMessage {
                    InfoButton(title: title, message: infoMessage)
                }
                Spacer()
            }
            content
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 数値+ラベルを淡い色付き背景で見せる共通タイル（今日の学習、スコアなど）。
struct StatTile: View {
    let value: String
    let label: String
    let tint: Color
    /// 指定するとラベルの右に「i」が出る。何を数えた値なのかが自明でない指標に付ける。
    var infoMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2).bold()
                .foregroundStyle(tint)
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let infoMessage {
                    InfoButton(title: label, message: infoMessage)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
