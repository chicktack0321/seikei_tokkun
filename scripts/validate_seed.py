#!/usr/bin/env python3
"""同梱シード（question_master_seed.json）そのものを検証する。

`build_seed.py` は正本（data/questions/）を検証して同梱ファイルを作る。こちらは
出来上がったファイルの側を見る。生成を経ずに同梱ファイルだけが手で触られたり、
生成の途中で壊れたりしたときに、アプリへ届く直前で落とすための最後の関所。

Swift側の `SeedValidationTests` と同じ検査をここでも行う。CIでスクリプトだけを回すと
ローカルでの編集に気づけず、テストだけに置くとmacOSランナーを待つことになるため、
軽い方（このスクリプト）を先に回す。

使い方:
    python scripts/validate_seed.py [シードJSONのパス]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from build_seed import (
    CHOICE_LABELS,
    DIFFICULTIES,
    ID_PREFIX,
    MAX_CHOICE_LENGTH,
    MAX_QUESTION_LENGTH,
    MID_CATEGORIES,
    OUT_PATH,
    report,
)


def validate(path: Path) -> list[str]:
    """検出したエラーの一覧を返す。空リストなら合格。"""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [f"JSONとして読めません: {e}"]

    errors: list[str] = []
    for key in ("version", "curriculumVersion", "questions"):
        if key not in data:
            errors.append(f"トップレベルに '{key}' がありません")
    if errors:
        return errors

    if not isinstance(data["version"], int) or data["version"] < 1:
        errors.append("version が1以上の整数ではありません")

    questions = data["questions"]
    if not isinstance(questions, list) or not questions:
        return ["'questions' が空、または配列ではありません"]

    seen_ids: set[str] = set()
    seen_texts: dict[str, str] = {}

    for i, q in enumerate(questions):
        qid = q.get("questionId", "")
        where = f"[{i}] {qid or '(IDなし)'}"

        parts = qid.split("_")
        if len(parts) != 3 or parts[0] != ID_PREFIX or len(parts[2]) != 4 or not parts[2].isdigit():
            errors.append(f"{where}: questionId の形式が {ID_PREFIX}_<中分類>_<4桁> ではありません")
        elif parts[1] != q.get("midCategory"):
            # IDと属性がずれていると、一覧の絞り込みと採番体系が食い違う
            errors.append(
                f"{where}: questionId の中分類 '{parts[1]}' が "
                f"midCategory '{q.get('midCategory')}' と一致しません"
            )

        if qid in seen_ids:
            errors.append(f"{where}: questionId が重複しています")
        seen_ids.add(qid)

        text = (q.get("questionText") or "").strip()
        if not text:
            errors.append(f"{where}: questionText が空です")
        elif len(text) > MAX_QUESTION_LENGTH:
            errors.append(f"{where}: questionText が{MAX_QUESTION_LENGTH}字を超えています（{len(text)}字）")
        if text in seen_texts:
            errors.append(f"{where}: questionText が {seen_texts[text]} と重複しています")
        elif text:
            seen_texts[text] = qid

        mid = q.get("midCategory")
        if mid not in MID_CATEGORIES:
            errors.append(f"{where}: midCategory '{mid}' は未知のコードです")
        elif MID_CATEGORIES[mid] != q.get("field"):
            errors.append(
                f"{where}: field '{q.get('field')}' は midCategory '{mid}' の分野 "
                f"'{MID_CATEGORIES[mid]}' と一致しません"
            )

        choices = q.get("choices") or {}
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
            texts = [(c or "").strip() for c in choices.values()]
            if len(set(texts)) != len(texts):
                errors.append(f"{where}: 選択肢に同じ文言のものがあります")

        correct = q.get("correctChoice")
        if correct not in CHOICE_LABELS:
            errors.append(f"{where}: correctChoice '{correct}' が A/B/C/D ではありません")

        if not (q.get("explanation") or "").strip():
            errors.append(f"{where}: explanation が空です")

        explanations = q.get("choiceExplanations") or {}
        if sorted(explanations.keys()) != CHOICE_LABELS:
            errors.append(f"{where}: choiceExplanations のキーが A/B/C/D の4つではありません")
        else:
            for label in CHOICE_LABELS:
                body = (explanations[label] or "").strip()
                if not body:
                    errors.append(f"{where}: 選択肢 {label} の解説が空です")
                    continue
                expected = "正解" if label == correct else "不正解"
                if not body.startswith(expected):
                    errors.append(f"{where}: 選択肢 {label} の解説が '{expected}' で始まっていません")

        if q.get("difficulty", 2) not in DIFFICULTIES:
            errors.append(f"{where}: difficulty '{q.get('difficulty')}' が 1/2/3 ではありません")

        if q.get("keywords") is not None and not isinstance(q.get("keywords"), list):
            errors.append(f"{where}: keywords が配列ではありません")

    covered = {q.get("midCategory") for q in questions}
    missing = [code for code in MID_CATEGORIES if code not in covered]
    if missing:
        errors.append("問題が1問も無い中分類があります: " + ", ".join(sorted(missing)))

    return errors


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else OUT_PATH
    if not path.exists():
        print(f"シードファイルが見つかりません: {path}", file=sys.stderr)
        return 1

    errors = validate(path)
    if errors:
        print(f"検証に失敗しました（{len(errors)}件）:\n", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    data = json.loads(path.read_text(encoding="utf-8"))
    print(f"検証に合格しました: {path}（version {data['version']} / {data['curriculumVersion']}）\n")
    report(data["questions"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
