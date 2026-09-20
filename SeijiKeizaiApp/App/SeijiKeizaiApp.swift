import SwiftUI
import SwiftData

@main
struct SeijiKeizaiApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(AppContainer.shared)
    }
}

/// ソーシャル機能も課金も持たないため、タブは「学習」に直結する最小構成にする
struct RootTabView: View {
    @State private var router = TabRouter()

    var body: some View {
        TabView(selection: Bindable(router).selectedTab) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house") }
                .tag(AppTab.home)

            QuizView()
                .tabItem { Label("演習", systemImage: "checkmark.circle") }
                .tag(AppTab.quiz)

            QuestionListView()
                .tabItem { Label("問題一覧", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.questionList)

            StudyHistoryView()
                .tabItem { Label("履歴", systemImage: "chart.bar") }
                .tag(AppTab.history)
        }
        .environment(router)
    }
}
