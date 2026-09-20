import SwiftUI
import SwiftData

/// 問題一覧。演習で出会った問題を探し直し、解説を読み返すための画面。
///
/// 演習の出題範囲（`StudyScope`）とは独立した絞り込みを持つ。
/// 「解いた問題を探す」操作と「次に何を出題するか」の設定は目的が違うため、共有しない。
struct QuestionListView: View {
    /// 一覧の行をUIテストから掴むための識別子
    static let rowIdentifier = "questionRow"

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = QuestionListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.questions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("問題一覧")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.filter.keyword,
                prompt: "問題文・キーワードで検索"
            )
            .safeAreaInset(edge: .top) { filterBar }
            .task { viewModel.configure(context: modelContext) }
            // 演習から戻ったときに習熟度の表示を合わせる
            .onAppear { viewModel.reload() }
            .onChange(of: viewModel.filter) { _, _ in viewModel.reload() }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.questions, id: \.questionId) { question in
                    NavigationLink {
                        QuestionDetailView(
                            question: question,
                            status: viewModel.status(for: question),
                            onMarkForReview: { viewModel.markForReview(question) },
                            onMarkAsMemorized: { viewModel.markAsMemorized(question) }
                        )
                    } label: {
                        QuestionRow(question: question, status: viewModel.status(for: question))
                    }
                    // 問題文は収録データによって変わるうえ絞り込みで並びも変わるため、
                    // UIテストからは文言でも位置でもなく識別子で掴む
                    .accessibilityIdentifier(Self.rowIdentifier)
                }
            } header: {
                Text("\(viewModel.questions.count)問")
            }
        }
        .listStyle(.plain)
    }

    /// 絞り込みは常に見えている必要がある（一覧をスクロールした先で条件を思い出せなくなる）ため、
    /// リストの中ではなく上部に固定する。
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("すべての分野") { viewModel.filter.setField(nil) }
                    ForEach(ExamField.allCases) { field in
                        Button(field.displayName) { viewModel.filter.setField(field) }
                    }
                } label: {
                    chip("分野", viewModel.filter.field?.displayName ?? "すべて")
                }

                Menu {
                    Button("すべての中分類") { viewModel.filter.midCategory = nil }
                    ForEach(viewModel.filter.availableMidCategories) { category in
                        Button(category.displayName) { viewModel.filter.midCategory = category }
                    }
                } label: {
                    chip("中分類", viewModel.filter.midCategory?.displayName ?? "すべて")
                }

                Menu {
                    Button("すべての状態") { viewModel.filter.status = nil }
                    ForEach(LearningStatus.allCases) { status in
                        Button(status.displayName) { viewModel.filter.status = status }
                    }
                } label: {
                    chip("状態", viewModel.filter.status?.displayName ?? "すべて")
                }

                Menu {
                    Button("すべての難易度") { viewModel.filter.difficulty = nil }
                    ForEach(QuestionDifficulty.allCases) { difficulty in
                        Button(difficulty.displayName) { viewModel.filter.difficulty = difficulty }
                    }
                } label: {
                    chip("難易度", viewModel.filter.difficulty?.displayName ?? "すべて")
                }

                if !viewModel.filter.isEmpty {
                    Button("リセット") { viewModel.filter = QuestionFilter() }
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(_ title: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(title).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
            Image(systemName: "chevron.down").font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    /// 0件の理由は「絞り込みすぎ」と「問題データが入っていない」の2つある。
    /// 混ぜると利用者が対処を判断できない。
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if viewModel.totalCount == 0 {
                Text("問題データが読み込まれていません")
                    .font(.subheadline)
                Text("アプリを再起動しても表示されない場合はお問い合わせください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("条件に合う問題がありません")
                    .font(.subheadline)
                Text("絞り込みを緩めるか、検索語を変えてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("条件をリセット") { viewModel.filter = QuestionFilter() }
                    .font(.caption)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

private struct QuestionRow: View {
    let question: QuestionMaster
    let status: LearningStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
                .font(.subheadline)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(question.questionText)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(question.midCategory.displayName)
                    Text("・")
                    Text(question.difficulty.displayName)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    QuestionListView()
        .modelContainer(for: [QuestionMaster.self, UserProgress.self, StudyLog.self], inMemory: true)
}
