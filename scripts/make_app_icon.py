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

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "SeijiKeizaiApp/Resources/Assets.xcassets"
ICONSET = ASSETS / "AppIcon.appiconset"
LOGOSET = ASSETS / "AppLogo.imageset"
OUT = ICONSET / "AppIcon-1024.png"

# 置いてあればこれを使い、無ければその場で描く
DEFAULT_SOURCE = ROOT / "docs/assets/app-icon-source.png"

SIZE = 1024

# 配色。緑のグラデーションに白と山吹の字を重ねる（参考画像に合わせた配色）。
# 姉妹アプリ（英単語＝橙、古文＝紺紫、ITパスポート＝青）と並べたときに区別が付く色味にしている。
TOP_COLOR = (18, 62, 20)       # 深い緑
BOTTOM_COLOR = (16, 168, 104)  # 明るい緑
WHITE = (250, 250, 248)
YELLOW = (250, 209, 112)
# 影は背景より暗い緑。黒を敷くと緑が濁って見える
SHADOW_COLOR = (12, 46, 16)

SIZE = 1024

# 3行の内容。(文字列, 色, 中心のy, 占める高さ, 占める幅) はいずれも辺の長さに対する比。
# 1024px で作って端末側が縮小するため、比で持たせておけば解像度を変えても崩れない。
LINES = [
    ("政経", WHITE, 0.185, 0.29, 0.66),
    ("特訓", YELLOW, 0.565, 0.40, 0.80),
    ("大学受験", WHITE, 0.875, 0.145, 0.68),
]

# 影の落とし方（辺の長さに対する比）
SHADOW_OFFSET = 0.014
SHADOW_BLUR = 0.006

# 太いゴシック体を使う。細い書体だと縮小したときに字が潰れて読めなくなる。
FONT_CANDIDATES = [
    "C:/Windows/Fonts/HGRSGU.TTC",       # HG創英角ゴシックUB
    "C:/Windows/Fonts/BIZ-UDGothicB.ttc",
    "C:/Windows/Fonts/YuGothB.ttc",
    "C:/Windows/Fonts/meiryob.ttc",
    "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    raise SystemExit(
        "日本語フォントが見つかりません。FONT_CANDIDATES に環境のフォントを足してください。"
    )


def fit_font(draw: ImageDraw.ImageDraw, text: str, max_width: float, max_height: float) -> ImageFont.FreeTypeFont:
    """指定した枠に収まる最大の字サイズを求める。

    字数が行ごとに違う（「政経」2字と「大学受験」4字）ので、同じ字サイズを使うと
    行の見た目の大きさが揃わない。行ごとに枠を決めて、そこへ入る大きさを探す。
    """
    size = int(max_height)
    while size > 8:
        font = load_font(size)
        box = draw.textbbox((0, 0), text, font=font)
        if (box[2] - box[0]) <= max_width and (box[3] - box[1]) <= max_height:
            return font
        size -= 2
    return load_font(8)


def draw_icon() -> Image.Image:
    im = Image.new("RGB", (SIZE, SIZE), TOP_COLOR)
    draw = ImageDraw.Draw(im)

    # 縦のグラデーション。1行ずつ塗る（1024行なので十分速い）
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(round(TOP_COLOR[i] + (BOTTOM_COLOR[i] - TOP_COLOR[i]) * t) for i in range(3))
        draw.line([(0, y), (SIZE, y)], fill=color)

    # 影は別レイヤーに描いてぼかしてから重ねる。本体と同じレイヤーに描くと、
    # ぼかしが字そのものにかかって輪郭が甘くなる。
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    offset = SIZE * SHADOW_OFFSET

    placements = []
    for text, color, center_y, height_ratio, width_ratio in LINES:
        font = fit_font(draw, text, SIZE * width_ratio, SIZE * height_ratio)
        box = draw.textbbox((0, 0), text, font=font)
        x = (SIZE - (box[2] - box[0])) / 2 - box[0]
        y = SIZE * center_y - (box[3] - box[1]) / 2 - box[1]
        placements.append((text, font, x, y, color))
        shadow_draw.text((x + offset, y + offset), text, font=font, fill=SHADOW_COLOR + (200,))

    shadow = shadow.filter(ImageFilter.GaussianBlur(SIZE * SHADOW_BLUR))
    im = Image.alpha_composite(im.convert("RGBA"), shadow).convert("RGB")

    draw = ImageDraw.Draw(im)
    for text, font, x, y, color in placements:
        draw.text((x, y), text, font=font, fill=color)

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
