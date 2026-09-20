# 公共・政治経済特訓

大学入学共通テスト「公共，政治・経済」の4択演習アプリ。iOS 17+ / SwiftUI / SwiftData / XcodeGen / 完全オフライン。
`C:\System_Dev\ITpassport`（問題演習の仕組み）と `C:\System_Dev\kobun_app_01`（無料運用・データ生成）を土台にした姉妹アプリ。

**完全無料のアプリ**。App内課金・広告・サブスクリプションは実装しない。
StoreKit にも依存しないので、課金・試用・購入復元の仕組みを足さないこと。

- 使い方・運用手順は `README.md`
- 設計の意図と参考元からの移植方針は `docs/design.md`
- 作問のルールとレビュー観点は `docs/question-authoring-prompt.md`
- 公開ページの文面は `docs/site-content.md`

## 絶対に守ること

- **`questionId`（`SEI_<中分類>_<4桁>`）と `MidCategory` の rawValue は公開後の改名禁止。** 学習履歴のキーなので、
  改名は「削除＋新規」になり、その問題の履歴が全ユーザーで失われる
- **正本の `no` は自動採番しない。** 並べ替えや削除で `questionId` が動くのを防ぐため、手で決めて固定する
- **マスター（`QuestionMaster`）と進捗（`UserProgress`）に `@Relationship` を張らない。** String ID での疎結合を保つ
  （マスター総入れ替え時に履歴を守るため）
- **`MidCategory.field` と `scripts/build_seed.py` の `MID_CATEGORIES` を一致させる。** ずれるとシード投入時に
  その問題が黙って捨てられ、エラーにならず気づけない
- **誤答の解説は「不正解。」、正解の解説は「正解。」で書き出す。** 解説パネルはこの書き出しで正誤を読み取らせている
  （スクリプトとテストの両方で検査している）
- **`project.yml` の `INFOPLIST_FILE` 直接指定と `PRODUCT_NAME: SeijiKeizaiApp`（ASCII）を維持する。**
  XcodeGen の `info:` 生成に切り替えると手書き Info.plist が上書きされ、`CFBundleDisplayName` や
  `ITSAppUsesNonExemptEncryption` が抜ける（姉妹アプリで実際に起きた）
- **シードのバージョン記録は `context.save()` 成功後に行う。** 逆順にすると「バージョンだけ進んで問題が空」が
  永続化され、以降シードがスキップされて復旧しなくなる

## データを編集したら

`data/questions/*.json` が正本。編集後は必ず生成して出力もコミットする。

```bash
python scripts/build_seed.py
```

CIは `data/questions/` と `SeijiKeizaiApp/Resources/question_master_seed.json` の一致を検証するので、
生成し忘れはビルドが落ちる。正解の位置が偏ったら `python scripts/rebalance_answers.py` でならせる。

## ビルド確認

手元にMacが無いため、コンパイルの検証はGitHub Actions（`.github/workflows/ios-build.yml`）で行う。
ローカルでSwiftをビルドすることはできない。
