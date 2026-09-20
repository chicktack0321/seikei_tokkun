#!/usr/bin/env python3
"""アプリアイコンとホーム画面用のロゴを生成して Assets.xcassets へ書き出す。

App Store のアイコンには決まりがある。守らないと審査ではなくアップロードの検証で弾かれ、
ビルドを上げ直すことになる。

  - 1024x1024 の正方形
  - アルファチャンネルを持たない（透過があると弾かれる）
  - 角丸を焼き込まない（Apple 側がマスクをかけるので、素材に角丸があると角に縁が残る）

元画像があればそれを変換し、無ければその場で描く。素材の差し替えに備えて両方の経路を残している。

使い方:
    python scripts/make_app_icon.py                   # 既定の元画像から生成
    python scripts/make_app_icon.py --source art.png  # 別の画像から作る
    python scripts/make_app_icon.py --check           # 既存アイコンの検証のみ

必要なもの: Pillow
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "SeijiKeizaiApp/Resources/Assets.xcassets"
ICONSET = ASSETS / "AppIcon.appiconset"
LOGOSET = ASSETS / "AppLogo.imageset"
OUT = ICONSET / "AppIcon-1024.png"

# 置いてあればこれを使い、無ければその場で描く
DEFAULT_SOURCE = ROOT / "docs/assets/app-icon-source.png"

SIZE = 1024

# 配色。政治・経済の題材に合わせた深い藍から紫みの藍へのグラデーション。
# 姉妹アプリ（英単語＝青、古文＝紺紫、ITパスポート）と並べたときに区別が付く色味にしている。
TOP_COLOR = (20, 52, 96)      # 濃い藍
BOTTOM_COLOR = (18, 96, 104)  # 青緑
GLYPH_COLOR = (247, 246, 240)  # 生成り
GLYPH = "政"

# ゴシック体を使う。制度・時事を扱う科目なので、明朝より硬すぎない字面にする。
FONT_CANDIDATES = [
    "C:/Windows/Fonts/YuGothB.ttc",   # 游ゴシック Bold
    "C:/Windows/Fonts/meiryob.ttc",   # メイリオ Bold
    "C:/Windows/Fonts/YuGothM.ttc",
    "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    raise SystemExit(
        "日本語フォントが見つかりません。FONT_CANDIDATES に環境のフォントを足してください。"
    )


def draw_icon() -> Image.Image:
    im = Image.new("RGB", (SIZE, SIZE), TOP_COLOR)
    draw = ImageDraw.Draw(im)

    # 縦のグラデーション。1行ずつ塗る（1024行なので十分速い）
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(round(TOP_COLOR[i] + (BOTTOM_COLOR[i] - TOP_COLOR[i]) * t) for i in range(3))
        draw.line([(0, y), (SIZE, y)], fill=color)

    # 字は角丸マスクの内側に収める。マスクで削られる四隅に字が寄ると欠けて見える。
    font = load_font(int(SIZE * 0.60))
    bbox = draw.textbbox((0, 0), GLYPH, font=font)
    x = (SIZE - (bbox[2] - bbox[0])) / 2 - bbox[0]
    y = (SIZE - (bbox[3] - bbox[1])) / 2 - bbox[1]
    draw.text((x, y), GLYPH, font=font, fill=GLYPH_COLOR)

    return im


def from_source(path: Path) -> Image.Image:
    im = Image.open(path)
    # 透過があると弾かれる。背景に合成してからアルファを落とす
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        background = Image.new("RGBA", im.size, TOP_COLOR + (255,))
        im = Image.alpha_composite(background, im)
    im = im.convert("RGB")
    if im.size != (SIZE, SIZE):
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    return im


def check(path: Path) -> int:
    """アップロードの検証で弾かれる条件を先に見つける"""
    if not path.exists():
        print(f"エラー: {path.relative_to(ROOT)} がありません", file=sys.stderr)
        return 1

    im = Image.open(path)
    problems = []
    if im.size != (SIZE, SIZE):
        problems.append(f"サイズが {im.size}（{SIZE}x{SIZE} でなければならない）")
    if im.mode != "RGB":
        problems.append(f"カラーモードが {im.mode}（アルファチャンネルがあると弾かれる）")

    # 角が明るいと、角丸と余白が焼き込まれている疑いがある。
    # Apple のマスクをかけたあとに角へ縁が残る。
    px = im.convert("RGB").load()
    w, h = im.size
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    if any(min(c) > 150 for c in corners):
        problems.append(f"角が明るい {corners}（角丸の余白が焼き込まれている可能性）")

    if problems:
        for p in problems:
            print(f"エラー: {p}", file=sys.stderr)
        return 1

    print(f"OK: {path.relative_to(ROOT)} {im.size} {im.mode}")
    return 0


def write_logo(icon: Image.Image) -> None:
    """ホーム画面のヘッダとこのアプリについてに出す小さなロゴ。

    アイコンと同じ絵柄を縮小して使う。別々の素材にすると、片方だけ差し替えたときに
    アプリの見た目が食い違う。
    """
    LOGOSET.mkdir(parents=True, exist_ok=True)
    base = 44  # 表示サイズ（pt）
    for scale in (1, 2, 3):
        name = "AppLogo.png" if scale == 1 else f"AppLogo@{scale}x.png"
        icon.resize((base * scale, base * scale), Image.LANCZOS).save(LOGOSET / name, "PNG")

    contents = {
        "images": [
            {
                "filename": "AppLogo.png" if scale == 1 else f"AppLogo@{scale}x.png",
                "idiom": "universal",
                "scale": f"{scale}x",
            }
            for scale in (1, 2, 3)
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (LOGOSET / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8"
    )


def write_contents_json() -> None:
    """Xcode がアイコンを認識するための索引。これが無いとビルドに含まれない"""
    contents = {
        "images": [
            {"filename": OUT.name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (ICONSET / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8"
    )

    # アセットカタログ自体の索引も要る
    catalog = ASSETS / "Contents.json"
    if not catalog.exists():
        catalog.write_text(
            json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
            encoding="utf-8",
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, help="別の画像から作る（省略時は docs/assets/app-icon-source.png）")
    parser.add_argument("--check", action="store_true", help="既存アイコンの検証のみ")
    args = parser.parse_args()

    if args.check:
        return check(OUT)

    ICONSET.mkdir(parents=True, exist_ok=True)
    source = args.source or (DEFAULT_SOURCE if DEFAULT_SOURCE.exists() else None)
    if source:
        print(f"元画像: {Path(source).relative_to(ROOT)}")
        im = from_source(Path(source))
    else:
        print("元画像が無いため描画して作ります")
        im = draw_icon()
    # アルファを持たせないよう RGB のまま保存する
    im.save(OUT, "PNG")
    write_contents_json()
    write_logo(im)
    print(f"{OUT.relative_to(ROOT)} と {LOGOSET.relative_to(ROOT)} を書き出しました")

    return check(OUT)


if __name__ == "__main__":
    sys.exit(main())
