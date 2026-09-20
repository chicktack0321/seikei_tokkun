# 公共・政治経済特訓（完全オフライン・完全無料）

大学入学共通テスト「公共，政治・経済」のための4択演習アプリ。
iOS 17+ / SwiftUI / SwiftData / XcodeGen / 通信ゼロ。

**完全無料**。App内課金・広告・サブスクリプションは実装しない。StoreKit にも依存しない。

姉妹アプリ `C:\System_Dev\ITpassport`（ITパスポート特訓）の問題演習の仕組みと、
`C:\System_Dev\kobun_app_01`（古文特訓）の「完全無料・データは正本から生成」という運用を組み合わせている。

- 設計の意図と参考元からの移植方針は `docs/design.md`
- 作問のルールは `docs/question-authoring-prompt.md`
- 公開ページ（プライバシーポリシー・サポート）の文面は `docs/site-content.md`

## 現在の状態

- 収録問題数: **264問**（4分野 / 23単元）
- 画面: ホーム・演習・問題一覧・履歴の4タブ
- 学習の記録は端末内（SwiftData）にのみ保存され、外部への送信は行わない

| 分野 | 問題数 | 本試験の配点の目安 |
| --- | ---: | ---: |
| 公共 | 48問 | 25% |
| 政治 | 72問 | 25% |
| 経済 | 96問 | 30% |
| 国際 | 48問 | 20% |

配点の目安に対して公共がやや薄く、経済がやや厚い。次の増補は公共（とくに先哲の思想・社会参画）から行う。

## ディレクトリ構成

```
SeijiKeizaiApp/
  App/          アプリ本体のエントリ、SwiftDataコンテナ、Info.plist
  Common/       画面共通の部品・設定・出題範囲の型
  Models/       SwiftDataのモデルと列挙（分野・単元・難易度・習熟段階）
  Repositories/ 問題マスターと学習履歴への読み書き
  Services/     出題順・習熟度集計・効果音・シード投入
  Features/     画面（Home / Quiz / QuestionList / History / Settings）
  Resources/    同梱シード・アイコン・プライバシーマニフェスト
data/questions/ 問題データの正本（中分類ごとに1ファイル）
scripts/        シード生成・検証・正解位置の平準化・アイコン生成
```

## 問題データを編集したら

`data/questions/*.json` が正本。編集後は必ず生成して、出力もコミットする。

```bash
python scripts/build_seed.py
```

CIは正本と `SeijiKeizaiApp/Resources/question_master_seed.json` の一致を検証するので、生成し忘れはビルドが落ちる。

検証だけしたいとき、生成物そのものを確かめたいとき:

```bash
python scripts/build_seed.py --check     # 正本の検証と収録状況の集計
python scripts/validate_seed.py          # 同梱シードの検証
python scripts/rebalance_answers.py      # 正解の位置（A〜D）を平準化する
```

### 問題を追加する手順

1. `data/questions/<中分類コード>.json` の `questions` に追記する。`no` は**そのファイル内で未使用の整数**を手で決める
   （連番を自動採番にすると、並べ替えや削除で `questionId` が動き、その問題の学習履歴が全ユーザーで失われる）
2. `docs/question-authoring-prompt.md` のチェックリストで内容を見直す
3. `python scripts/build_seed.py` を実行し、出力ごとコミットする

## ビルド方法（Mac実機なし・GitHub ActionsのmacOSランナーを使用）

手元にMacが無いため、コンパイルの検証はGitHub Actionsで行う。ローカルでSwiftをビルドすることはできない。

- `.github/workflows/ios-build.yml` … 問題データの検証 → XcodeGen → ビルド → テスト → スクリーンショット
- `.github/workflows/testflight.yml` … 手動トリガーでTestFlightへ配信

UIテストは主要画面を一通り遷移してスクリーンショットを撮り、`.xcresult` から取り出して
ワークフローのアーティファクトとしてアップロードする。実機がなくても画面の崩れに気付けるようにするため。

### Macが用意できた場合のローカル手順

```bash
brew install xcodegen
xcodegen generate
open SeijiKeizaiApp.xcodeproj
```

## アイコンとロゴ

```bash
python scripts/make_app_icon.py          # 生成（元画像があれば docs/assets/app-icon-source.png を使う）
python scripts/make_app_icon.py --check  # アップロードの検証で弾かれる条件を先に確認する
```

アイコンは1024x1024・アルファなし・角丸を焼き込まないこと。条件を外すと審査ではなく
App Store Connect の検証で弾かれ、ビルド番号を消費して上げ直しになる。

## 設計の要点

### questionId は改名禁止

`SEI_<中分類コード>_<4桁連番>`（例: `SEI_KINYU_0007`）。これが学習履歴のキーそのものなので、
公開後の改名は「削除＋新規」になり、その問題の履歴が全ユーザーで失われる。
中分類コード（`MidCategory` の rawValue）も同じ理由で改名禁止。

### マスターと進捗は疎結合

`QuestionMaster`（同梱シードで丸ごとUpsertされる）と `UserProgress`（絶対に保持する学習履歴）は
String の `questionId` でのみ結びつけ、SwiftData の `@Relationship` は張らない。
リレーションを張ると、マスターの入れ替え時に履歴へカスケードが波及しうる。

### 間隔反復（SRS）

Leitnerボックス方式。正解で 1日 → 3日 → 7日 → 14日 → 30日 と間隔が伸び、不正解で最短に戻る。
7日以上の間隔に到達した問題を「習得済み」とする（直前に1回正解しただけでは「学習中」）。

### 出題順

1. 復習期限が来ている問題 → 2. 未学習の問題 → 3. 期限前の問題（期限が近い順）。
ランダム出題では忘れかけた問題に当たらないため、優先度を付けている。

### 選択肢は毎回シャッフルする

シード上の並び（A→D）で固定すると「答えは3番目」という位置記憶で解けてしまい、
間隔反復が測るものが知識ではなく並び順の記憶になる。正解の位置は並べ替えた配列から求めて保持する
（表示テキストの検索で探すと、同じ文言の選択肢があったときに誤った位置を正解と見なす）。

### 分野別の習熟度を主表示にする

全体の習熟度より「いちばん低い分野がどこか」のほうが次の行動を決められる。
とくに経済分野は用語どうしの因果（金利・物価・為替・景気）がつながっており、1つの穴が複数の問題に響く。

## 実装しないもの

- App内課金・広告・サブスクリプション（完全無料のため）
- 通信を伴う機能（同期・ランキング・アカウント）
- 聞き流し（音声読み上げ）。`UIBackgroundModes` も宣言しない

## 残っている作業

- 収録数の増補（公共分野を厚くして、配点の目安に近づける）
- 問題内容の人手レビュー（制度改正・統計の更新で古くなる問題の洗い出し）
- 公開ページのURLを `AppConfig` の TODO から実際のURLへ差し替える
