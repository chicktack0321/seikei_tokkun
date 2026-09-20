import SwiftUI
import SwiftData

/// このアプリについて。
///
/// 試験の名称を使うため、大学入試センターと提携していないことの明示がApp Reviewで問われうる。
/// あわせて、プライバシーポリシーと問い合わせ先という「審査で所在を確認される導線」を
/// ここ1か所にまとめている。課金が無いので「購入の復元」は置かない。
struct AboutView: View {
    @Environment(\.modelContext) private var modelContext
    /// 収録数は実データから出す。案内に数字を直書きすると、問題を足すたびに嘘になる。
    @State private var questionCount = 0
    @State private var fieldCounts: [ExamField: Int] = [:]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppConfig.appDisplayName).font(.headline)
                            Text(AppConfig.examDisplayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(AppConfig.freeNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("収録している問題") {
                LabeledContent("合計", value: "\(questionCount)問")
                ForEach(ExamField.allCases) { field in
                    LabeledContent(field.displayName, value: "\(fieldCounts[field] ?? 0)問")
                }
            }

            Section("試験の概要") {
                LabeledContent("試験時間", value: "\(AppConfig.examDurationMinutes)分")
                LabeledContent("満点", value: "\(AppConfig.examFullScore)点")
                VStack(alignment: .leading, spacing: 4) {
                    Text("出題の構成").font(.subheadline)
                    Text(AppConfig.examStructure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("学習の進め方").font(.subheadline)
                    Text(AppConfig.studyAdvice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("リンク") {
                Link("プライバシーポリシー", destination: AppConfig.privacyPolicyURL)
                Link("使い方・お問い合わせ", destination: AppConfig.supportURL)
            }

            Section {
                Text(AppConfig.trademarkNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                // 制度改正や統計の更新で古くなる問題があるため、報告の受け口を明示する
                Text("内容の誤りに気づいたときは、上のお問い合わせからご連絡ください。")
            }
        }
        .navigationTitle("このアプリについて")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let repository = QuestionRepository(context: modelContext)
            questionCount = repository.fetchCount()
            fieldCounts = repository.countsByField()
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .modelContainer(for: [QuestionMaster.self, UserProgress.self, StudyLog.self], inMemory: true)
}
