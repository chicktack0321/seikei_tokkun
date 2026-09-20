import SwiftUI
import SwiftData
import Charts

/// 学習の推移を見せる画面。「続けられている実感」を返す場所。
struct StudyHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StudyHistoryViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    rangePicker
                    streakCard
                    chartCard
                    summaryCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("学習の記録")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.configure(context: modelContext) }
            // 演習から戻ったときに最新の解答を反映する
            .onAppear { viewModel.reload() }
        }
    }

    private var rangePicker: some View {
        Picker("期間", selection: $viewModel.selectedPeriod) {
            ForEach(StudyHistoryViewModel.Period.allCases) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var streakCard: some View {
        DashboardCard(title: "継続日数") {
            HStack(spacing: 12) {
                StatTile(
                    value: "\(viewModel.streak)日",
                    label: "連続学習",
                    tint: .orange,
                    infoMessage: MetricExplanations.streak
                )
                StatTile(
                    value: "\(viewModel.studiedDayCount)日",
                    label: "この期間に学習した日数",
                    tint: .blue
                )
            }
        }
    }

    /// 解答数（棒）と習熟度（折れ線）を1枚に重ねる。
    /// 「たくさん解いた」ことと「習得済みが増えた」ことは別なので、
    /// 同じ時間軸に並べて対応を見られるようにしている。
    private var chartCard: some View {
        @Bindable var viewModel = viewModel
        return DashboardCard(
            title: viewModel.scope.isDefault
                ? "学習量と習熟度"
                : "学習量と習熟度（\(viewModel.scope.summary)）"
        ) {
            if viewModel.hasAnyRecord {
                VStack(alignment: .leading, spacing: 8) {
                    // 全問をまとめて見ると折れ線がほとんど動かない
                    MasteryScopeMenu(scope: $viewModel.scope)

                    Chart {
                        ForEach(viewModel.series) { entry in
                            BarMark(
                                x: .value("日", entry.date, unit: chartUnit),
                                y: .value("解答数", entry.studiedQuestionCount)
                            )
                            .foregroundStyle(Color.blue.opacity(0.55))
                            .cornerRadius(2)
                        }
                        ForEach(viewModel.masteryPoints) { point in
                            LineMark(
                                x: .value("日", point.date, unit: chartUnit),
                                y: .value("習得済み", point.count)
                            )
                            .foregroundStyle(LearningStatus.memorized.tint)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: viewModel.selectedPeriod.axisStrideDays)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 220)

                    HStack(spacing: 16) {
                        legendItem(color: Color.blue.opacity(0.55), label: "解答数")
                        legendItem(color: LearningStatus.memorized.tint, label: "習得済み")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if viewModel.selectedPeriod.aggregatesByWeek {
                        Text("3か月以上は週ごとにまとめて表示しています")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // 折れ線が途中から始まる理由を書いておかないと、記録が消えたように見える
                    if viewModel.hasDaysWithoutBreakdown {
                        Text("範囲ごとの内訳は記録を始めた日からの分だけ表示できます")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                emptyState
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 12, height: 4)
            Text(label)
        }
    }

    private var chartUnit: Calendar.Component {
        viewModel.selectedPeriod.aggregatesByWeek ? .weekOfYear : .day
    }

    private var summaryCard: some View {
        DashboardCard(title: "この期間の合計") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(value: "\(viewModel.totalAttempts)問", label: "解答数", tint: .indigo)
                StatTile(
                    value: "\(Int((viewModel.overallAccuracy * 100).rounded()))%",
                    label: "正答率",
                    tint: .green,
                    infoMessage: MetricExplanations.overallAccuracy
                )
                StatTile(
                    value: "\(viewModel.masteredQuestionCount)問",
                    label: "習得済み",
                    tint: LearningStatus.memorized.tint,
                    infoMessage: MetricExplanations.mastery
                )
                StatTile(
                    value: "+\(viewModel.masteredGain)問",
                    label: "この期間の増加",
                    tint: .orange,
                    infoMessage: "期間の開始時点と終了時点で、「習得済み」段階の問題数がどれだけ増えたかです。"
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("まだ学習の記録がありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("演習を解くとここに推移が表示されます")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
}

#Preview {
    StudyHistoryView()
        .modelContainer(for: [QuestionMaster.self, UserProgress.self, StudyLog.self], inMemory: true)
}
