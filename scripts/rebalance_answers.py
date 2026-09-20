#!/usr/bin/env python3
"""正解の選択肢の位置を、A〜Dへ均等にならす。

アプリは出題のたびに選択肢を並べ替える（`QuizViewModel.buildQuestion`）ので、
正解の位置は学習には影響しない。それでもならしておくのは、正本のJSONが
作問・レビューの現物だからで、「いつもAが正解」の状態だと、人が読んで見直すときに
正誤の判断が目に引きずられる。問題一覧の詳細画面もシード上の並び順で表示する。

正解と入れ替え先の選択肢を、本文と解説ごと交換する（回転ではなく交換にしているのは、
誤答どうしの並びを不必要に動かさないため）。`correctChoice` も書き換える。

使い方:
    python scripts/rebalance_answers.py           # data/questions/*.json を書き換える
    python scripts/rebalance_answers.py --check   # 偏りの確認のみ
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data" / "questions"
LABELS = ["A", "B", "C", "D"]


def rebalance(entries: list[dict], start: int) -> int:
    """ファイル内の各問題の正解位置を、通しの並び順で A→B→C→D と割り当てる。

    - Parameter start: 直前のファイルから続く通し番号。ファイルごとにAから始めると、
      収録数の少ない中分類ばかりがAに寄る。
    - Returns: 次のファイルへ渡す通し番号。
    """
    for offset, entry in enumerate(entries):
        target = LABELS[(start + offset) % len(LABELS)]
        correct = entry.get("correctChoice")
        if correct not in LABELS or correct == target:
            continue

        choices = entry["choices"]
        explanations = entry["choiceExplanations"]
        choices[correct], choices[target] = choices[target], choices[correct]
        explanations[correct], explanations[target] = explanations[target], explanations[correct]
        entry["correctChoice"] = target

    return start + len(entries)


def distribution(files: list[Path]) -> Counter:
    counter: Counter = Counter()
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        counter.update(q.get("correctChoice") for q in data.get("questions", []))
    return counter


def report(counter: Counter) -> None:
    total = sum(counter.values())
    if not total:
        print("問題が見つかりません")
        return
    print("正解の位置:")
    for label in LABELS:
        count = counter.get(label, 0)
        print(f"  {label}: {count:>4}問 ({count / total * 100:5.1f}%)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="偏りの確認のみ（書き換えない）")
    args = parser.parse_args()

    files = sorted(DATA_DIR.glob("*.json"))
    if not files:
        print(f"{DATA_DIR} に問題ファイルがありません", file=sys.stderr)
        return 1

    if args.check:
        report(distribution(files))
        return 0

    cursor = 0
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        cursor = rebalance(data.get("questions", []), cursor)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"{len(files)}ファイルを書き換えました。")
    report(distribution(files))
    print("\n`python scripts/build_seed.py` でシードを作り直してください。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
