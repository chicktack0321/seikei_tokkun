import SwiftUI
import SwiftData
import Charts

/// ホームから push する画面。増えても `navigationDestination` を1か所にまとめられるよう列挙にしている。
enum HomeDestination: Hashable {
    case about
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TabRouter.self) private var router
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    titleHeader
                    todayCard
                    fieldCard
                    historyCard
                    masteryCard
                    quickActionsCard
                    aboutLink
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ホーム")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .about: AboutView()
                }
            }
            .task { viewModel.configure(context: modelContext) }
            // 履歴タブから戻ったとき、向こうで変えた集計範囲を反映する
            .onAppear { viewModel.syncScopeFromSettings() }
            .onChange(of: router.selectedTab) { _, newValue in
                // 日付をまたぐと復習期限の来た問題が変わるため、ホームに戻るたびに数え直す
                if newValue == .home {
                    viewModel.reload()
                }
            }
        }
    }

    /// ナビゲーションバーの「ホーム」に代えて、アプリ名とロゴを出す
    private var titleHeader: some View {
        HStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(AppConfig.appDisplayName)
                    .font(.title2).bold()
                Text(AppConfig.examDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var todayCard: some View {
        DashboardCard(title: "今日の学習") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatTile(
                        value: "\(viewModel.todayStudiedCount)問",
                        label: "解答した問題数",
                        tint: .blue,
                        infoMessage: MetricExplanations.todayStudied
                    )
                    StatTile(
                        value: percentString(viewModel.todayAccuracy),
                        label: "今日の正答率",
                        tint: .green,
                        infoMessage: MetricExplanations.todayAccuracy
                    )
                }

                // 復習期限が来た問題がある日は、まずそこから手を付けてもらう。
                // 出題対象を渡して、押した通りに復習だけが始まるようにしている。
                if viewModel.dueCount > 0 {
                    Button {
                        router.startQuiz(scope: .reviewOnly)
                    } label: {
                        HStack {
                            Label("復習する問題が\(viewModel.dueCount)問あります", systemImage: "arrow.clockwise")
                                .font(.subheadline)
                            InfoButton(title: "復習する問題", message: MetricExplanations.dueForReview)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .foregroundStyle(.orange)
                        .padding(12)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 分野別の習熟度。
    ///
    /// 分野で配点の比重が違ううえ、経済分野は用語どうしの因果がつながっていて
    /// 穴が複数の問題に響く。全体の習熟度より「いちばん低い分野がどこか」のほうが
    /// 行動を決められるので、ホームの主表示にしている。
    private var fieldCard: some View {
        DashboardCard(title: "分野別の習熟度", infoMessage: MetricExplanations.fieldMastery) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.fieldProgress) { progress in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(progress.field.displayName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(progress.memorizedCount) / \(progress.totalCount)問（\(progress.percent)%）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress.fraction)
                            .tint(LearningStatus.memorized.tint)
                    }
                }

                // 「次に何をやるか」まで示す。数字だけでは行動に繋がらない。
                if let weakest = viewModel.weakestField, weakest.totalCount > 0 {
                    Divider()
                    Button {
                        var scope = StudySettings.studyScope
                        scope.setField(weakest.field)
                        StudySettings.studyScope = scope
                        router.startQuiz(scope: .mixed)
                    } label: {
                        HStack {
                            Label(
                                "いちばん遅れているのは\(weakest.field.displayName)です",
                                systemImage: "target"
                            )
                            .font(.caption)
                            Spacer()
                            Text("この分野を解く")
                                .font(.caption).bold()
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 直近1週間の推移をミニグラフで見せ、詳しい記録は履歴タブへ送る
    private var historyCard: some View {
        Button {
            router.selectedTab = .history
        } label: {
            DashboardCard(title: "学習の記録") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("\(viewModel.streak)日連続", systemImage: "flame.fill")
                            .font(.subheadline).bold()
                            .foregroundStyle(.orange)
                        InfoButton(title: "連続日数", message: MetricExplanations.streak)
                        Spacer()
                        Text("詳しく見る")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.weeklySeries.contains(where: \.didStudy) {
                        Chart(viewModel.weeklySeries) { day in
                            BarMark(
                                x: .value("日", day.date, unit: .day),
                                y: .value("解答数", day.studiedQuestionCount)
                            )
                            .foregroundStyle(Color.blue.gradient)
                            .cornerRadius(2)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 60)
                    } else {
                        Text("今週はまだ記録がありません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        // カード内の文字列が連結されてラベルになるため、UIテストからは識別子で引く
        .accessibilityIdentifier("historyCardLink")
    }

    private var masteryCard: some View {
        @Bindable var viewModel = viewModel
        return DashboardCard(
            title: viewModel.masteryScope.isDefault
                ? "習熟度（\(viewModel.totalQuestionCount)問）"
                : "習熟度（\(viewModel.masteryScope.summary) \(viewModel.totalQuestionCount)問）",
            infoMessage: MetricExplanations.mastery
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // 全問をまとめて見るとバーはほとんど動かない。
                // 範囲を狭められること自体が「進んでいる実感」に効く。
                MasteryScopeMenu(scope: $viewModel.masteryScope)

                MasteryBar(counts: viewModel.statusCounts)

                // 段階が4つあるので凡例は2列に折り返す
                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(LearningStatus.allCases) { status in
                        LegendDot(
                            color: status.barColor,
                            label: "\(status.displayName) \(viewModel.statusCounts[status] ?? 0)"
                        )
                    }
                }
                .font(.caption)

                Divider()

                HStack(spacing: 4) {
                    Text("累計正答率")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    InfoButton(title: "累計正答率", message: MetricExplanations.overallAccuracy)
                    Spacer()
                    Text(percentString(viewModel.overallAccuracy))
                        .font(.subheadline).bold()
                }
            }
        }
    }

    private var quickActionsCard: some View {
        DashboardCard(title: "クイックアクション") {
            VStack(spacing: 10) {
                Button {
                    router.startQuiz(scope: .mixed)
                } label: {
                    Label("演習を始める", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    router.selectedTab = .questionList
                } label: {
                    Label("問題一覧を見る", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// 権利表記・収録数・プライバシーポリシーへの入口
    private var aboutLink: some View {
        NavigationLink(value: HomeDestination.about) {
            HStack {
                Text("このアプリについて")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        // リンクの中身が文字列の連結でラベルになるため、UIテストからは識別子で引く
        .accessibilityIdentifier("aboutLink")
    }

    private func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - 共通パーツ

/// 習熟段階の内訳を表す横積み上げバー。
/// 習得済み側から並べ、学習が進むほど左から緑が伸びていくように見せる。
private struct MasteryBar: View {
    let counts: [LearningStatus: Int]

    /// 表示順。習得済みを左端に置く
    private static let order: [LearningStatus] = [.memorized, .learning, .needsReview, .notStudied]

    private var total: Int { counts.values.reduce(0, +) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Self.order, id: \.self) { status in
                    segment(count: counts[status] ?? 0, color: status.barColor, width: proxy.size.width)
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    private func segment(count: Int, color: Color, width: CGFloat) -> some View {
        let fraction = total == 0 ? 0 : CGFloat(count) / CGFloat(total)
        return color.frame(width: width * fraction)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
        .foregroundStyle(.secondary)
    }
}

#Preview {
    HomeView()
        .environment(TabRouter())
        .modelContainer(for: [QuestionMaster.self, UserProgress.self, StudyLog.self], inMemory: true)
}
