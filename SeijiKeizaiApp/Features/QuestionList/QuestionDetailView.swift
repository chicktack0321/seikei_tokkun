import SwiftUI

/// 1問の詳細。問題文・全選択肢・全解説を、演習の外でいつでも読み返せるようにする。
///
/// 演習の解説パネル（`ExplanationPanel`）と違い、こちらは「答えを知った上で読む」場面なので
/// 最初からすべて開いた状態で出す。畳んでおく理由が無い。
struct QuestionDetailView: View {
    let question: QuestionMaster
    let status: LearningStatus
    let onMarkForReview: () -> Void
    let onMarkAsMemorized: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// 操作の結果を伝えるための表示。押しても何も起きないように見えるのを防ぐ
    @State private var actionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusHeader
                questionCard
                explanationCard
                choicesCard
                actionsCard
                metadata
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(question.midCategory.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("学習状態を変更しました", isPresented: .constant(actionMessage != nil)) {
            Button("OK") { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
            Text(status.displayName)
                .font(.subheadline).bold()
                .foregroundStyle(status.tint)
            InfoButton(title: status.displayName, message: status.criteria)
            Spacer()
        }
    }

    private var questionCard: some View {
        DashboardCard(title: "問題") {
            Text(question.questionText)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var explanationCard: some View {
        DashboardCard(title: "正解と解説") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(question.correctChoice.rawValue)
                        .font(.subheadline).bold()
                        .foregroundStyle(.green)
                    Text(question.correctChoiceText)
                        .font(.subheadline).bold()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(question.explanation)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 全選択肢とその解説。
    /// 誤答選択肢が指す用語の意味を知ることが4択問題の学習価値の半分を占めるため、
    /// 正解だけでなく4本すべてを並べる。
    private var choicesCard: some View {
        DashboardCard(title: "各選択肢の解説") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(question.orderedChoices) { choice in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(choice.label.rawValue)
                                .font(.caption).bold()
                                .foregroundStyle(choice.isCorrect ? .green : .secondary)
                            Text(choice.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(choice.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        choice.isCorrect ? Color.green.opacity(0.08) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
            }
        }
    }

    private var actionsCard: some View {
        DashboardCard(title: "この問題の扱い") {
            VStack(spacing: 10) {
                Button {
                    onMarkForReview()
                    actionMessage = "「要復習」に戻しました。次の演習で優先的に出題されます。"
                } label: {
                    Label("もう一度やり直す", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onMarkAsMemorized()
                    actionMessage = "「習得済み」にしました。しばらく出題されなくなります。"
                } label: {
                    Label("習得済みにする", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("「習得済みにする」は、すでに確実な問題を出題から外すための操作です。解答の記録には影響しません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                tag(question.field.displayName, tint: .blue)
                tag(question.difficulty.displayName, tint: .gray)
                Spacer(minLength: 0)
            }
            if !question.keywords.isEmpty {
                Text("キーワード: \(question.keywords.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 選挙制度・税率・社会保障の数値は改正で古くなる。どの版に基づく問題かを出しておく
            Text("\(question.curriculumVersion) 準拠 / \(question.questionId)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}
