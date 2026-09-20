#!/usr/bin/env python3
"""data/questions/ の正本JSONを検証して、アプリ同梱の question_master_seed.json を生成する。

正本を中分類ごとのファイルに分けているのは編集のしやすさのため（単元単位で追記・差し替えでき、
差分レビューも単元ごとに閉じる）。アプリ側は起動時に1ファイルだけ読めばよいので、ここで結合する。

検証をこのスクリプトに集めているのは、データの不備が「実行時に静かに出題されない」形で
現れるため。ビルド前に落として気づけるようにしている。

使い方:
    python scripts/build_seed.py            # 生成
    python scripts/build_seed.py --check    # 検証のみ（CI用。ファイルを書かない）
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data" / "questions"
OUT_PATH = ROOT / "SeijiKeizaiApp" / "Resources" / "question_master_seed.json"

ID_PREFIX = "SEI"

# 準拠する課程。制度改正で一部だけ差し替えるときは、問題ごとの curriculumVersion で上書きする
CURRICULUM_VERSION = "2022年度実施 学習指導要領（新課程）"

# 中分類コード → 分野。Swift側の MidCategory.field と一致していること。
# ここがずれると Swift 側でシードが黙って捨てられ、エラーにならず気づけない。
MID_CATEGORIES = {
    # 公共
    "SEINEN": "civics",
    "SHISO": "civics",
    "RINRI": "civics",
    "SANKA": "civics",
    # 政治
    "MINSHU": "politics",
    "KENPO": "politics",
    "JINKEN": "politics",
    "TOCHI": "politics",
    "CHIHO": "politics",
    "SENKYO": "politics",
    # 経済
    "TAISEI": "economics",
    "SHIJO": "economics",
    "SHOTOKU": "economics",
    "KINYU": "economics",
    "ZAISEI": "economics",
    "NIHON": "economics",
    "ROUDOU": "economics",
    "SHAKAI": "economics",
    "SHOHI": "economics",
    # 国際
    "ISEIJI": "international",
    "KOKUREN": "international",
    "IKEIZAI": "international",
    "NANBOKU": "international",
}

FIELD_LABELS = {
    "civics": "公共",
    "politics": "政治",
    "economics": "経済",
    "international": "国際",
}

# 分野ごとの配点の目安（100点中）。収録の偏りを見るための基準で、エラーにはしない
FIELD_WEIGHTS = {"civics": 25, "politics": 25, "economics": 30, "international": 20}

CHOICE_LABELS = ["A", "B", "C", "D"]
DIFFICULTIES = (1, 2, 3)

# 本文の長さ上限。iPhoneの画面でレイアウトが崩れない範囲として決めた値
MAX_QUESTION_LENGTH = 300
MAX_CHOICE_LENGTH = 120


class ValidationError(Exception):
    pass


def load_sources() -> list[tuple[str, dict]]:
    """中分類コードと中身の組を、ファイル名順で返す"""
    if not DATA_DIR.exists():
        raise ValidationError(f"{DATA_DIR} がありません")

    files = sorted(DATA_DIR.glob("*.json"))
    if not files:
        raise ValidationError(f"{DATA_DIR} に問題ファイルがありません")

    sources = []
    for path in files:
        code = path.stem
        if code not in MID_CATEGORIES:
            raise ValidationError(f"{path.name}: 未知の中分類コード '{code}'")
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            raise ValidationError(f"{path.name}: JSONが壊れています: {e}") from e
        sources.append((code, data))
    return sources


def build(sources: list[tuple[str, dict]]) -> list[dict]:
    questions: list[dict] = []
    errors: list[str] = []
    seen_ids: set[str] = set()
    seen_texts: dict[str, str] = {}

    for code, data in sources:
        field = MID_CATEGORIES[code]
        entries = data.get("questions")
        if not isinstance(entries, list) or not entries:
            errors.append(f"{code}.json: 'questions' が空、または配列ではありません")
            continue

        seen_numbers: set[int] = set()
        for index, entry in enumerate(entries):
            number = entry.get("no")
            # 連番は自動採番しない。並べ替えや削除でIDが動くと、その問題の学習履歴が
            # 全ユーザーで失われる（questionId は履歴のキーそのもの）。
            if not isinstance(number, int) or not (1 <= number <= 9999):
                errors.append(f"{code}.json[{index}]: 'no' が 1〜9999 の整数ではありません")
                continue
            if number in seen_numbers:
                errors.append(f"{code}.json: 'no' {number} が重複しています")
                continue
            seen_numbers.add(number)

            qid = f"{ID_PREFIX}_{code}_{number:04d}"
            where = qid
            if qid in seen_ids:
                errors.append(f"{where}: questionId が重複しています")
            seen_ids.add(qid)

            text = (entry.get("questionText") or "").strip()
            if not text:
                errors.append(f"{where}: questionText が空です")
            elif len(text) > MAX_QUESTION_LENGTH:
                errors.append(f"{where}: questionText が{MAX_QUESTION_LENGTH}字を超えています（{len(text)}字）")
            # 同じ論点を二度出題しないための最低限の検出。表記まで同一のものだけを拾う
            if text in seen_texts:
                errors.append(f"{where}: questionText が {seen_texts[text]} と重複しています")
            elif text:
                seen_texts[text] = qid

            choices = entry.get("choices") or {}
            if sorted(choices.keys()) != CHOICE_LABELS:
                errors.append(f"{where}: choices のキーが A/B/C/D の4つではありません")
            else:
                for label in CHOICE_LABELS:
                    choice = (choices[label] or "").strip()
                    if not choice:
                        errors.append(f"{where}: 選択肢 {label} が空です")
                    elif len(choice) > MAX_CHOICE_LENGTH:
                        errors.append(
                            f"{where}: 選択肢 {label} が{MAX_CHOICE_LENGTH}字を超えています（{len(choice)}字）"
                        )
                # 同じ文言の選択肢があると、正解を選んでも不正解になりうる
                texts = [(c or "").strip() for c in choices.values()]
                if len(set(texts)) != len(texts):
                    errors.append(f"{where}: 選択肢に同じ文言のものがあります")

            correct = entry.get("correctChoice")
            if correct not in CHOICE_LABELS:
                errors.append(f"{where}: correctChoice '{correct}' が A/B/C/D ではありません")

            if not (entry.get("explanation") or "").strip():
                errors.append(f"{where}: explanation が空です")

            explanations = entry.get("choiceExplanations") or {}
            if sorted(explanations.keys()) != CHOICE_LABELS:
                errors.append(f"{where}: choiceExplanations のキーが A/B/C/D の4つではありません")
            else:
                for label in CHOICE_LABELS:
                    body = (explanations[label] or "").strip()
                    if not body:
                        errors.append(f"{where}: 選択肢 {label} の解説が空です")
                        continue
                    # 誤答の解説が「なぜ違うか」から書き出されているかを機械的に担保する。
                    # ここが崩れると、解説パネルで正誤の区別がつかなくなる。
                    expected = "正解" if label == correct else "不正解"
                    if not body.startswith(expected):
                        errors.append(f"{where}: 選択肢 {label} の解説が '{expected}' で始まっていません")

            difficulty = entry.get("difficulty", 2)
            if difficulty not in DIFFICULTIES:
                errors.append(f"{where}: difficulty '{difficulty}' が 1/2/3 ではありません")

            keywords = entry.get("keywords") or []
            if not isinstance(keywords, list):
                errors.append(f"{where}: keywords が配列ではありません")
                keywords = []

            question = {
                "questionId": qid,
                "questionText": text,
                "choices": {label: (choices.get(label) or "").strip() for label in CHOICE_LABELS},
                "correctChoice": correct,
                "explanation": (entry.get("explanation") or "").strip(),
                "choiceExplanations": {
                    label: (explanations.get(label) or "").strip() for label in CHOICE_LABELS
                },
                "field": field,
                "midCategory": code,
                "keywords": keywords,
                "difficulty": difficulty,
            }
            # 版は既定を使い、個別に指定があるときだけ載せる（差分を小さく保つ）
            if entry.get("curriculumVersion"):
                question["curriculumVersion"] = entry["curriculumVersion"]
            questions.append(question)

    if errors:
        raise ValidationError("\n".join(f"  - {e}" for e in errors))

    covered = {q["midCategory"] for q in questions}
    missing = [code for code in MID_CATEGORIES if code not in covered]
    if missing:
        raise ValidationError("  - 問題が1問も無い中分類があります: " + ", ".join(sorted(missing)))

    questions.sort(key=lambda q: q["questionId"])
    return questions


def report(questions: list[dict]) -> None:
    """出題の偏りを目視で確認するための集計。エラーではないので参考情報として出す。"""
    total = len(questions)
    by_field = Counter(q["field"] for q in questions)
    by_difficulty = Counter(q["difficulty"] for q in questions)
    by_category = Counter(q["midCategory"] for q in questions)
    by_answer = Counter(q["correctChoice"] for q in questions)

    print(f"収録問題数: {total}問")

    print("\n分野別（括弧内は本試験の配点の目安）:")
    for field, label in FIELD_LABELS.items():
        count = by_field.get(field, 0)
        print(f"  {label:<4} {count:>4}問 ({count / total * 100:5.1f}%) (目安 {FIELD_WEIGHTS[field]}%)")

    print("\n難易度別（目安は 30 : 50 : 20）:")
    for level, label in ((1, "基礎"), (2, "標準"), (3, "応用")):
        count = by_difficulty.get(level, 0)
        print(f"  {label:<4} {count:>4}問 ({count / total * 100:5.1f}%)")

    # 正解の位置の偏り。アプリは出題時にシャッフルするため学習には影響しないが、
    # 偏りが大きいと作問時に正解を先に書く癖が出ている合図になる。
    print("\n正解の位置（均等が目安。偏りは作問の癖の合図）:")
    print("  " + "  ".join(f"{label}:{by_answer.get(label, 0):>3}" for label in CHOICE_LABELS))
    most = max(by_answer.values()) if by_answer else 0
    if total and most / total > 0.40:
        print(f"  警告: 特定の位置に{most / total * 100:.0f}%が集中しています。")

    # 正解だけが長いと、内容を知らなくても「いちばん長い選択肢」を選んで当てられてしまう。
    # 文字数そのものより、画面で何行に折り返されるかが利用者に見える差になるので行数で測る。
    per_line = 22  # iPhoneの選択肢ボタンで日本語がおおよそ折り返す字数

    def line_count(text: str) -> int:
        return -(-len(text) // per_line)

    longest = 0
    for q in questions:
        correct = q["correctChoice"]
        others = [line_count(v) for k, v in q["choices"].items() if k != correct]
        if others and line_count(q["choices"][correct]) > max(others):
            longest += 1
    print("\n選択肢の長さ（正解だけが長いと、読まずに当てられてしまう）:")
    print(f"  正解が行数で最も長い問題: {longest}問 ({longest / total * 100:.0f}%)")
    if total and longest / total > 0.35:
        print("  警告: 正解が最も長い問題が多すぎます。誤答を書き足して差をなくしてください。")

    print("\n中分類別:")
    for code in MID_CATEGORIES:
        print(f"  {code:<8} {by_category.get(code, 0):>4}問")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="検証のみ（ファイルを書かない）")
    args = parser.parse_args()

    try:
        questions = build(load_sources())
    except ValidationError as e:
        print("問題データの検証に失敗しました:\n", file=sys.stderr)
        print(e, file=sys.stderr)
        return 1

    if args.check:
        print("問題データの検証に合格しました\n")
        report(questions)
        return 0

    # version は「シードを作り直すたびに1つ上げる」。アプリ側はこの値が既適用より
    # 大きいときだけUpsertするので、据え置くと端末に変更が届かない。
    previous = 0
    if OUT_PATH.exists():
        try:
            previous = json.loads(OUT_PATH.read_text(encoding="utf-8")).get("version", 0)
        except json.JSONDecodeError:
            previous = 0

    seed = {
        "version": previous + 1,
        "curriculumVersion": CURRICULUM_VERSION,
        "questions": questions,
    }
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(seed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{OUT_PATH.relative_to(ROOT)} を書き出しました（version {seed['version']}）\n")
    report(questions)
    return 0


if __name__ == "__main__":
    sys.exit(main())
