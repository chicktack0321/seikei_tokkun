import SwiftUI

/// 1セット分の結果。Viewが `@Model` を直接触らずに済むよう値型に詰め替えている。
struct QuizResultSummary {
    struct MissedQuestion: Identifiable {
        let id: String
        let questionText: String
        let midCategory: MidCategory
        let correctChoiceText: String
        let explanation: String
    }

    /// 分野ごとの正誤。全体の正答率より、どの分野を立て直すかの判断に効く。
    struct FieldResult: Identifiable {
        let field: ExamField
        let correctCount: Int
        let totalCount: Int

        var id: String { field.rawValue }

        var accuracy: Double {
            totalCount == 0 ? 0 : Double(correctCount) / Double(totalCount)
        }

        var accuracyPercent: Int { Int((accuracy * 100).rounded()) }
    }

    let scope: QuizScope
    let correctCount: Int
    let totalCount: Int
    let newlyMemorizedCount: Int
    let elapsedSeconds: Int
    let missedQuestions: [MissedQuestion]
    let fieldResults: [FieldResult]

    var accuracy: Double {
        totalCount == 0 ? 0 : Double(correctCount) / Double(totalCount)
    }

    var accuracyPercent: Int { Int((accuracy * 100).rounded()) }

    var averageSecondsPerQuestion: Double {
        totalCount == 0 ? 0 : Double(elapsedSeconds) / Double(totalCount)
    }
}

struct QuizResultView: View {
    let summary: QuizResultSummary
    let onRetry: () -> Void
    /// 間違えた問題だけを解き直す。結果を見た直後が最も定着しやすいので導線を用意する。
    let onRetryMissed: ([String]) -> Void
    /// 結果を見たあとスタート画面へ戻る導線。これが無いと、復習を解き終えて
    /// 出題対象が無くなったときに演習タブから抜けられなくなる。
    let onBackToStart: () -> Void

    private var grade: (label: String, color: Color) {
        switch summary.accuracyPercent {
        case 90...: return ("S", .yellow)
        case 75..<90: return ("A", .blue)
        case 60..<75: return ("B", .green)
        case 40..<60: return ("C", .primary)
        default: return ("D", .secondary)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headline
                if !summary.fieldResults.isEmpty {
                    fieldCard
                }
                statsCard
                if summary.newlyMemorizedCount > 0 {
                    memorizedCard
                }
                if !summary.missedQuestions.isEmpty {
                    missedCard
                }
                actions
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text(headlineTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(grade.label)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(grade.color)
            Text("\(summary.correctCount) / \(summary.totalCount) 問正解（\(summary.accuracyPercent)%）")
                .font(.title3).bold()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var headlineTitle: String {
        switch summary.scope {
        case .mixed: return "結果"
        case .reviewOnly: return "復習おつかれさまでした"
        case .retryMissed: return "解き直しの結果"
        }
    }

    /// 分野別の内訳。
    ///
    /// 「全体で7割取れた」よりも「どの分野が落ちているか」のほうが、
    /// 次にやることを決められる。
    private var fieldCard: some View {
        DashboardCard(title: "分野別", infoMessage: MetricExplanations.fieldMastery) {
            VStack(spacing: 10) {
                ForEach(summary.fieldResults) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(result.field.displayName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(result.correctCount) / \(result.totalCount) 問（\(result.accuracyPercent)%）")
                                .font(.subheadline).bold()
                                .foregroundStyle(tint(for: result.accuracyPercent))
                        }
                        ProgressView(value: result.accuracy)
                            .tint(tint(for: result.accuracyPercent))
                    }
                }
            }
        }
    }

    /// 6割を「本番で戦える」、3割未満を「手を付け直す」の目安に色を分ける。
    /// 1セット10問なので、分野別の値は数問で大きく動く。あくまで傾向として扱う。
    private func tint(for percent: Int) -> Color {
        switch percent {
        case 60...: return .green
        case 30..<60: return .orange
        default: return .red
        }
    }

    private var statsCard: some View {
        DashboardCard(title: "内訳") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(value: "\(summary.correctCount) 問", label: "正解", tint: .green)
                StatTile(value: "\(summary.totalCount - summary.correctCount) 問", label: "不正解", tint: .red)
                StatTile(
                    value: String(format: "%.0f 秒", summary.averageSecondsPerQuestion),
                    label: "1問あたり",
                    tint: .blue,
                    infoMessage: "解説を読んだ時間も含みます。本試験は60分で、資料の読み取りを含めて1問あたり2分弱が目安です。"
                )
                StatTile(
                    value: "\(summary.newlyMemorizedCount) 問",
                    label: "習得済みに到達",
                    tint: LearningStatus.memorized.tint,
                    infoMessage: MetricExplanations.mastery
                )
            }
        }
    }

    private var memorizedCard: some View {
        DashboardCard(title: "習熟度が上がりました") {
            HStack(spacing: 8) {
                Image(systemName: LearningStatus.memorized.symbolName)
                    .foregroundStyle(LearningStatus.memorized.tint)
                Text("\(summary.newlyMemorizedCount)問が「習得済み」に到達しました")
                    .font(.subheadline)
                Spacer()
            }
        }
    }

    /// 間違えた問題をその場で見返せるようにする。結果が数字だけだと、
    /// 何を復習すればよいかを別画面で探し直すことになるため。
    private var missedCard: some View {
        DashboardCard(title: "間違えた問題（\(summary.missedQuestions.count)問）") {
            VStack(spacing: 0) {
                ForEach(Array(summary.missedQuestions.enumerated()), id: \.element.id) { index, question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.midCategory.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(question.questionText)
                            .font(.subheadline)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("正解: \(question.correctChoiceText)")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(question.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    if index < summary.missedQuestions.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    /// 次にとってほしい行動を1つだけ目立たせる。
    ///
    /// 間違えた問題があるなら解き直しが最優先（結果を見た直後がいちばん定着する）、
    /// 全問正解なら次のセットへ進むのが最優先になる。
    /// ボタンの種類ごとに `.borderedProminent` と `.bordered` は別の型なので、
    /// 三項演算子で切り替えることはできない。分岐そのものを分ける。
    private var actions: some View {
        VStack(spacing: 10) {
            if summary.missedQuestions.isEmpty {
                Button("次のセットに進む", action: onRetry)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("間違えた問題だけ解き直す（\(summary.missedQuestions.count)問）") {
                    onRetryMissed(summary.missedQuestions.map(\.id))
                }
                .buttonStyle(.borderedProminent)

                Button("次のセットに進む", action: onRetry)
                    .buttonStyle(.bordered)
            }

            Button("出題範囲を変える", action: onBackToStart)
                .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }
}

#Preview {
    QuizResultView(
        summary: QuizResultSummary(
            scope: .mixed,
            correctCount: 7,
            totalCount: 10,
            newlyMemorizedCount: 2,
            elapsedSeconds: 420,
            missedQuestions: [
                .init(
                    id: "SEI_KINYU_0007",
                    questionText: "日本銀行が行う公開市場操作のうち、買いオペレーションの説明として最も適切なものはどれか。",
                    midCategory: .finance,
                    correctChoiceText: "金融市場で国債などを買い入れ、市中に資金を供給する。",
                    explanation: "買いオペは日銀が債券を買って代金を払う操作で、市中の資金量が増え金利は低下しやすくなる。"
                )
            ],
            fieldResults: [
                .init(field: .civics, correctCount: 2, totalCount: 2),
                .init(field: .politics, correctCount: 2, totalCount: 3),
                .init(field: .economics, correctCount: 3, totalCount: 5)
            ]
        ),
        onRetry: {},
        onRetryMissed: { _ in },
        onBackToStart: {}
    )
}
