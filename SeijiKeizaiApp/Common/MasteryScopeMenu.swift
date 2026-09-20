import SwiftUI

/// 習得済みの問題数を数える範囲（分野・中分類・難易度）を選ぶ1行のメニュー。
///
/// ホームの習熟度と学習の記録のグラフで同じ範囲を扱うため、共通の部品にしている。
/// 出題範囲の `StudyScopeCard` ほど場所を取れない画面向けに、カードではなく横並びのチップにしている。
struct MasteryScopeMenu: View {
    @Binding var scope: StudyScope

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("すべての分野") { scope.setField(nil) }
                ForEach(ExamField.allCases) { field in
                    Button(field.displayName) { scope.setField(field) }
                }
            } label: {
                label("分野", scope.field?.displayName ?? "すべて")
            }

            Menu {
                Button("すべての中分類") { scope.midCategory = nil }
                ForEach(availableMidCategories) { category in
                    Button(category.displayName) { scope.midCategory = category }
                }
            } label: {
                label("中分類", scope.midCategory?.displayName ?? "すべて")
            }

            Menu {
                Button("すべての難易度") { scope.difficulty = nil }
                ForEach(QuestionDifficulty.allCases) { difficulty in
                    Button(difficulty.displayName) { scope.difficulty = difficulty }
                }
                if !scope.isDefault {
                    Divider()
                    Button("リセット") { scope = .default }
                }
            } label: {
                label("難易度", scope.difficulty?.displayName ?? "すべて")
            }

            Spacer(minLength: 0)
        }
    }

    private var availableMidCategories: [MidCategory] {
        guard let field = scope.field else { return MidCategory.allCases }
        return MidCategory.all(in: field)
    }

    private func label(_ title: String, _ value: String) -> some View {
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
}
