import SwiftUI
import SwiftData

struct QuizView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TabRouter.self) private var router
    @State private var viewModel = QuizViewModel()
    /// 正解のたびに増やして紙吹雪を発生させる
    @State private var celebrationTrigger = 0
    /// 出題範囲。保存先は StudySettings（ViewModel からも読むため UserDefaults に置いている）
    @State private var scope = StudySettings.studyScope

    /// 解答後に解説の先頭へ送るためのアンカー
    private enum ScrollAnchor: Hashable {
        case explanation
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .notStarted:
                    startScreen
                case .inProgress:
                    if let question = viewModel.currentQuestion {
                        quizScreen(question: question)
                    }
                case .finished:
                    QuizResultView(
                        summary: viewModel.resultSummary,
                        onRetry: { viewModel.startNewQuiz(scope: .mixed) },
                        onRetryMissed: { ids in
                            viewModel.startNewQuiz(scope: .retryMissed(questionIds: ids))
                        },
                        onBackToStart: { viewModel.returnToStart() }
                    )
                }
            }
            .navigationTitle(viewModel.phase == .notStarted ? "演習" : viewModel.scope.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.phase == .inProgress {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("やめる") { viewModel.abortSession() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SoundToggleButton(isSessionActive: viewModel.phase == .inProgress)
                }
            }
            .task {
                viewModel.configure(context: modelContext)
                // 効果音とBGMの合成を裏で先に済ませておく。スタートを押してからだと待たされる
                GameAudio.shared.warmUp()
            }
            // ホームの「復習する問題がN問あります」から来たときは、押した通りに復習だけを始める
            .onChange(of: router.pendingQuizScope) { _, pending in
                guard pending != nil, let requested = router.consumePendingQuizScope() else { return }
                viewModel.startNewQuiz(scope: requested)
            }
            .onDisappear { viewModel.suspendSession() }
            .onAppear {
                // 出題範囲はホームの「この分野を解く」からも書き換えられる。
                // 読み直さないと、範囲カードの表示だけが古いまま残る。
                scope = StudySettings.studyScope
                viewModel.refreshScopeCount()

                // タブを一度も開いていない場合 onChange は発火しないため、初回表示でも拾う
                if let requested = router.consumePendingQuizScope() {
                    viewModel.startNewQuiz(scope: requested)
                } else {
                    viewModel.resumeSession()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.resumeSession()
                } else {
                    viewModel.suspendSession()
                }
            }
        }
    }

    // MARK: - スタート画面

    private var startScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("4択演習")
                        .font(.title2).bold()
                    Text("\(QuizViewModel.questionCount)問 / 制限時間なし")
                        .foregroundStyle(.secondary)
                    // 制限時間を設けていないことは、初見だと不安になる部分なので明示する
                    Text("1問ごとに全選択肢の解説を読めます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // 復習を解き終えて出題対象が無くなったときなど、なぜ始まらなかったのかを伝える
                if let notice = viewModel.notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                Button("スタート") { viewModel.startNewQuiz() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.scopePoolCount == 0)
                    .accessibilityIdentifier("quizStartButton")

                StudyScopeCard(
                    title: "出題範囲",
                    scope: $scope,
                    matchingCount: viewModel.scopePoolCount
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        // 範囲を変えたら問題数の表示をすぐ合わせる
        .onChange(of: scope) { _, newValue in
            StudySettings.studyScope = newValue
            viewModel.refreshScopeCount()
        }
    }

    // MARK: - 出題画面

    /// 問題文・選択肢・解説はいずれも長文になりうるため、画面全体をスクロールさせる。
    ///
    /// スワイプで次の問題へ送る固定レイアウトは採用しない。
    /// 縦のドラッグをスクロールと取り合うことになり、解説を読むための操作が
    /// 「次へ送る」操作と衝突する。
    private func quizScreen(question: QuizQuestion) -> some View {
        VStack(spacing: 0) {
            QuizProgressCard(
                currentIndex: viewModel.currentQuestionIndex,
                total: viewModel.questions.count,
                fraction: viewModel.progressFraction,
                midCategory: question.question.midCategory
            )
            .padding(.horizontal)
            .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        questionCard(question: question)

                        if let selected = viewModel.selectedChoiceIndex {
                            ExplanationPanel(question: question, selectedIndex: selected)
                                .id(ScrollAnchor.explanation)
                                .transition(.opacity)

                            // 「次の問題へ」は解説の下に置く。解答ボタンと同じ位置に出すと、
                            // 選択肢を押した勢いで解説を読まずに飛ばしてしまう。
                            Button(viewModel.isLastQuestion ? "結果を見る" : "次の問題へ") {
                                viewModel.goToNextQuestion()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("quizNextButton")
                            .padding(.bottom, 8)
                        }
                    }
                    .padding()
                }
                // 解答したら解説の先頭へ送る。長い問題文だと解説が画面外に生まれ、
                // 何が起きたのか分からないまま止まって見える。
                .onChange(of: viewModel.selectedChoiceIndex) { _, selected in
                    guard selected != nil else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(ScrollAnchor.explanation, anchor: .top)
                    }
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.15), value: viewModel.selectedChoiceIndex)
        // 正解した選択肢の位置から弾けさせる。画面全体に降らせると、どこで何が起きたのか伝わらない
        .overlayPreferenceValue(ChoiceAnchorKey.self) { anchors in
            GeometryReader { proxy in
                ConfettiView(
                    trigger: celebrationTrigger,
                    origin: confettiOrigin(anchors, in: proxy),
                    duration: 0.3
                )
            }
            .allowsHitTesting(false)
        }
        .onChange(of: viewModel.currentQuestionIndex, initial: true) { _, _ in
            // 次の解答で震わせるので、手が空いているこのタイミングで温めておく
            Haptics.prepare()
        }
        // 解答が確定した瞬間に手応えを返す。正解は1回、不正解は3回。
        .onChange(of: viewModel.selectedChoiceIndex) { _, selected in
            guard let selected, let current = viewModel.currentQuestion else { return }
            if selected == current.correctIndex {
                Haptics.success()
                celebrationTrigger += 1
            } else {
                Haptics.failure()
            }
        }
    }

    private func questionCard(question: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.question.questionText)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                ForEach(Array(question.choices.enumerated()), id: \.element.id) { index, choice in
                    ChoiceButton(
                        label: QuizQuestion.displayLabel(at: index),
                        text: choice.text,
                        state: choiceState(index: index, question: question),
                        isCorrectAnswer: index == question.correctIndex,
                        action: { viewModel.selectAnswer(index) }
                    )
                    // 紙吹雪を正解の位置から出すために、各選択肢の位置を親へ伝える
                    .anchorPreference(key: ChoiceAnchorKey.self, value: .bounds) { [index: $0] }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func choiceState(index: Int, question: QuizQuestion) -> ChoiceButton.State {
        guard let selected = viewModel.selectedChoiceIndex else { return .idle }
        if index == question.correctIndex { return .correct }
        if index == selected { return .incorrect }
        return .disabled
    }

    /// 正解の選択肢の中心を、紙吹雪の発生源に変換する
    private func confettiOrigin(
        _ anchors: [Int: Anchor<CGRect>],
        in proxy: GeometryProxy
    ) -> UnitPoint {
        guard let question = viewModel.currentQuestion,
              let anchor = anchors[question.correctIndex],
              proxy.size.width > 0, proxy.size.height > 0
        else { return UnitPoint(x: 0.5, y: 0.35) }

        let rect = proxy[anchor]
        return UnitPoint(
            x: rect.midX / proxy.size.width,
            y: rect.midY / proxy.size.height
        )
    }
}

/// 問題番号と進捗。
///
/// 出題画面の本体から切り出してある。同じ本体に置くと、進捗の更新だけで
/// 選択肢の位置の再計算から紙吹雪のオーバーレイの組み直しまで走ってしまう。
private struct QuizProgressCard: View {
    let currentIndex: Int
    let total: Int
    let fraction: Double
    /// いまどの分野を解いているかは、解答の手掛かりではなく現在地の把握に効く
    let midCategory: MidCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("第\(currentIndex + 1)問 / \(total)問")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(midCategory.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ProgressView(value: fraction)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 選択肢の位置を親へ伝えるためのキー。紙吹雪を正解した場所から出すために使う
private struct ChoiceAnchorKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ChoiceButton: View {
    static let accessibilityIdentifier = "QuizChoice"
    /// UIテストで正解の選択肢を掴むための識別子（`UITestSupport` の起動引数があるときだけ使う）
    static let correctAccessibilityIdentifier = "QuizChoiceCorrect"

    enum State { case idle, correct, incorrect, disabled }

    let label: String
    let text: String
    let state: State
    let isCorrectAnswer: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.subheadline).bold()
                    .foregroundStyle(labelColor)
                    .frame(width: 18, alignment: .leading)
                // 選択肢は最大120字を想定しており、1行に収まらない。折り返して全文を出す
                Text(text)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(state == .disabled ? .secondary : .primary)
        }
        .disabled(state != .idle)
        // 選択肢の文言は出題ごとに変わるため、UIテストから掴む手掛かりを別に持たせる
        .accessibilityIdentifier(
            UITestSupport.revealsCorrectChoice && isCorrectAnswer
                ? Self.correctAccessibilityIdentifier
                : Self.accessibilityIdentifier
        )
    }

    private var labelColor: Color {
        switch state {
        case .idle: return .blue
        case .correct: return .green
        case .incorrect: return .red
        case .disabled: return .secondary
        }
    }

    private var background: Color {
        switch state {
        case .idle: return Color(.secondarySystemBackground)
        case .correct: return .green.opacity(0.25)
        case .incorrect: return .red.opacity(0.25)
        case .disabled: return Color(.secondarySystemBackground)
        }
    }
}

#Preview {
    QuizView()
        .environment(TabRouter())
        .modelContainer(for: [QuestionMaster.self, UserProgress.self, StudyLog.self], inMemory: true)
}
