import XCTest

/// 実機やMacが手元になくても各画面の見た目を確認できるよう、主要画面を一通り遷移しながら
/// スクリーンショットを撮る。CIでは `xcparse` を使って `.xcresult` からPNGとして取り出し、
/// ワークフローのアーティファクトとしてアップロードする（`.github/workflows/ios-build.yml`）。
///
/// - Important: 遷移に失敗したら**必ずテストを失敗させる**こと。
///   各ステップを黙って飛ばす作りにすると、撮れていないのにテストは成功し、
///   「撮れたつもり」で壊れた画面に気付けなくなる。
final class SeijiKeizaiAppUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // 1画面の遷移に失敗しても、それまでに撮れたスクリーンショットは失わずに済むよう続行する。
        // 失敗は記録されるので、素通りとは区別される。
        continueAfterFailure = true

        app = XCUIApplication()
        // 正解の選択肢を識別できるようにする。出題は収録データと習熟度によって変わるため、
        // これが無いと「正解したときの解説画面」を安定して撮れない（`UITestSupport` を参照）。
        app.launchArguments.append(UITestSupport.revealCorrectChoiceArgument)
        app.launch()
    }

    func testCaptureAllScreens() throws {
        capture("01_Home")
        captureMetricInfo()
        captureFieldMastery()
        captureQuiz()
        captureQuestionList()
        captureHistory()
        captureAbout()
    }

    // MARK: - 画面ごと

    /// iマークの説明。最も長い「習熟度」の説明が見切れずに読めることを毎回撮って確かめる。
    private func captureMetricInfo() {
        let masteryInfo = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH '習熟度' AND label ENDSWITH 'の説明'"))
            .firstMatch
        XCTAssertTrue(masteryInfo.waitForExistence(timeout: 10), "習熟度カードのiマークが見つからない")

        if !masteryInfo.isHittable {
            app.swipeUp()
            settle()
        }
        guard masteryInfo.isHittable else {
            XCTFail("習熟度カードのiマークを押せない")
            return
        }
        masteryInfo.tap()
        settle()
        capture("01a_MetricInfo")

        let closeButton = app.buttons["閉じる"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "説明シートを閉じるボタンが見つからない")
        closeButton.tap()
        settle()
    }

    /// 分野別習熟度カード。どの分野が遅れているかを示す、このアプリの中心的な表示。
    private func captureFieldMastery() {
        app.swipeUp()
        settle()
        capture("01b_Home_FieldMastery")
        app.swipeDown()
        settle()
    }

    /// 演習: スタート → 出題 → 解答 → 解説（正解・不正解の両方）
    private func captureQuiz() {
        selectTab("演習")
        capture("02_Quiz_Start")

        let startButton = app.buttons["quizStartButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "スタートボタンが見つからない")
        XCTAssertTrue(startButton.isHittable, "スタートボタンを押せない（出題対象が0問の可能性）")
        startButton.tap()
        settle()
        capture("03_Quiz_Question")

        // 1問目は正解した状態。App Store用のスクリーンショットにはこちらを使う。
        XCTAssertTrue(tapChoice(identifier: "QuizChoiceCorrect"), "正解の選択肢を押せない")
        settle()

        let nextButton = app.buttons["quizNextButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "解答しても解説パネルが出ていない")
        capture("04_Quiz_Explanation")

        // 「各選択肢の解説」は既定で畳まれている。誤答選択肢の意味を示す部分なので開いた状態も撮る。
        let expandButton = app.buttons["各選択肢の解説を見る"]
        if expandButton.exists, expandButton.isHittable {
            expandButton.tap()
            settle()
            capture("04b_Quiz_AllChoices")
        }

        // 2問目はわざと間違える。不正解のときだけ出る「選んだ選択肢の解説」はこのアプリの要。
        XCTAssertTrue(nextButton.isHittable, "「次の問題へ」を押せない")
        nextButton.tap()
        settle()
        XCTAssertTrue(tapChoice(identifier: "QuizChoice"), "誤答の選択肢を押せない")
        settle()
        capture("04c_Quiz_Explanation_Incorrect")
    }

    /// 問題一覧 → 問題詳細
    private func captureQuestionList() {
        selectTab("問題一覧")
        capture("05_QuestionList")

        // 問題文は収録データによって変わり、絞り込みで並びも変わるため識別子で掴む。
        // SwiftUIのListでは識別子がセルとボタンのどちらに載るかが決まらないので、種類を限定せずに探す。
        let firstRow = app.descendants(matching: .any)
            .matching(identifier: "questionRow")
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "問題一覧に行が出ていない")
        XCTAssertTrue(firstRow.isHittable, "問題一覧の行を押せない")
        firstRow.tap()
        settle()

        XCTAssertTrue(
            app.staticTexts["正解と解説"].waitForExistence(timeout: 5),
            "問題詳細へ遷移できていない（一覧のまま撮影される）"
        )
        capture("06_QuestionDetail")
        goBack()
    }

    private func captureHistory() {
        selectTab("履歴")
        XCTAssertTrue(
            app.staticTexts["継続日数"].waitForExistence(timeout: 5),
            "学習の記録画面に遷移できていない"
        )
        capture("07_StudyHistory")
    }

    /// 権利表記とプライバシーポリシーへの導線。審査で所在を確認される画面。
    private func captureAbout() {
        selectTab("ホーム")
        let aboutLink = app.descendants(matching: .any).matching(identifier: "aboutLink").firstMatch
        XCTAssertTrue(aboutLink.waitForExistence(timeout: 5), "「このアプリについて」への導線が見つからない")
        if !aboutLink.isHittable {
            app.swipeUp()
            settle()
        }
        aboutLink.tap()
        settle()
        XCTAssertTrue(
            app.staticTexts["収録している問題"].waitForExistence(timeout: 5),
            "このアプリについて画面へ遷移できていない"
        )
        capture("08_About")
        goBack()
    }

    // MARK: - 補助

    private func selectTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "タブ「\(title)」が見つからない")
        tab.tap()
        settle()
    }

    /// 指定した識別子の選択肢を押す。選択肢の文言は出題ごとに変わるため、識別子で掴む。
    /// `QuizChoiceCorrect` は正解の選択肢、`QuizChoice` はそれ以外（＝不正解）に付く。
    @discardableResult
    private func tapChoice(identifier: String) -> Bool {
        let choice = app.buttons.matching(identifier: identifier).firstMatch
        guard choice.waitForExistence(timeout: 5), choice.isHittable else { return false }
        choice.tap()
        return true
    }

    private func goBack() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.exists, "戻るボタンが見つからない")
        backButton.tap()
        settle()
    }

    /// 画面遷移アニメーションが落ち着くのを待つ（厳密な待機条件がない箇所向けの簡易対応）
    private func settle() {
        Thread.sleep(forTimeInterval: 1)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
