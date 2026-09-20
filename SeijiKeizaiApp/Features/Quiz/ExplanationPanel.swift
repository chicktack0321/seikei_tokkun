import SwiftUI

/// 解答直後に出す解説パネル。
///
/// このアプリで解説は「おまけ」ではなく学習の本体なので、正誤の表示より面積を取る。
/// 並び順は読む順序に合わせてある:
///
/// 1. 正誤と正解の選択肢（まず結果を知りたい）
/// 2. **自分が選んだ選択肢の解説**（不正解のとき、いちばん知りたいのは「なぜ違うのか」）
/// 3. 正解の理由
/// 4. 残りの選択肢の解説（折りたたみ。全部開いていると長すぎて要点が埋もれる）
/// 5. 分野・中分類・キーワード
struct ExplanationPanel: View {
    let question: QuizQuestion
    /// 利用者が選んだ表示位置
    let selectedIndex: Int

    @State private var isShowingAllChoices = false

    private var isCorrect: Bool { selectedIndex == question.correctIndex }
    private var selectedChoice: QuizQuestion.DisplayChoice? {
        guard selectedIndex >= 0, selectedIndex < question.choices.count else { return nil }
        return question.choices[selectedIndex]
    }
    private var correctChoice: QuizQuestion.DisplayChoice? {
        guard question.correctIndex < question.choices.count else { return nil }
        return question.choices[question.correctIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            verdict

            // 不正解のときだけ、選んだ選択肢の解説を先頭に出す。
            // 正解のときは「正解の解説」と同じ内容になるので重複させない。
            if !isCorrect, let selected = selectedChoice {
                choiceExplanationBlock(
                    heading: "選んだ選択肢（\(QuizQuestion.displayLabel(at: selectedIndex))）",
                    text: question.question.choiceExplanation(for: selected.label),
                    tint: .red
                )
            }

            correctExplanationBlock

            otherChoicesSection

            Divider()

            metadata
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var verdict: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(isCorrect ? .green : .red)
            VStack(alignment: .leading, spacing: 3) {
                Text(isCorrect ? "正解" : "不正解")
                    .font(.headline)
                    .foregroundStyle(isCorrect ? .green : .red)
                if let correctChoice {
                    Text("正解: \(QuizQuestion.displayLabel(at: question.correctIndex)). \(correctChoice.text)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var correctExplanationBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("解説")
                .font(.caption).bold()
                .foregroundStyle(.secondary)
            Text(question.question.explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func choiceExplanationBlock(heading: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading)
                .font(.caption).bold()
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 全選択肢の解説。
    ///
    /// 誤答選択肢の意味を知ることが4択問題の学習価値の半分を占めるため必ず用意するが、
    /// 既定では畳んでおく。4本すべてを開いた状態にすると、いちばん重要な
    /// 「正解の理由」と「自分が選んだ選択肢の誤り」が長文に埋もれる。
    private var otherChoicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isShowingAllChoices.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isShowingAllChoices ? "各選択肢の解説を閉じる" : "各選択肢の解説を見る")
                        .font(.caption).bold()
                    Image(systemName: isShowingAllChoices ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            if isShowingAllChoices {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(question.choices.enumerated()), id: \.element.id) { index, choice in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(QuizQuestion.displayLabel(at: index))
                                    .font(.caption).bold()
                                    .foregroundStyle(index == question.correctIndex ? .green : .secondary)
                                Text(choice.text)
                                    .font(.caption).bold()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(question.question.choiceExplanation(for: choice.label))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                tag(question.question.field.displayName, tint: .blue)
                tag(question.question.midCategory.displayName, tint: .indigo)
                tag(question.question.difficulty.displayName, tint: .gray)
                Spacer(minLength: 0)
            }
            if !question.question.keywords.isEmpty {
                Text("キーワード: \(question.question.keywords.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
