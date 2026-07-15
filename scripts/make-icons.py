# -*- coding: utf-8 -*-
"""大帅拼音图标生成：圆角方底 + 单字，输出多尺寸 .ico 与预览图。

用法: python make-icons.py <输出目录>
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "icons-out"
os.makedirs(OUT, exist_ok=True)

SIZES = [16, 20, 24, 32, 48, 64, 128, 256]
YAHEI_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
SEGOE_SYM = r"C:\Windows\Fonts\seguisym.ttf"

# 图标定义: 文件名 -> (字符, 背景色, 文字色, 字体)
BLUE = (43, 91, 215, 255)      # 主品牌蓝
SLATE = (90, 103, 122, 255)    # 英文/次要态灰蓝
ORANGE = (222, 120, 20, 255)   # 部署中
ICONS = {
    "weasel.ico": ("帅", BLUE, (255, 255, 255, 255), YAHEI_BOLD),
    # zh.ico 是任务栏"中文模式"指示图标，必须与本体图标（帅）区分，用"中"字
    "zh.ico":     ("中", BLUE, (255, 255, 255, 255), YAHEI_BOLD),
    "en.ico":     ("A",  SLATE, (255, 255, 255, 255), YAHEI_BOLD),
    "full.ico":   ("全", BLUE, (255, 255, 255, 255), YAHEI_BOLD),
    "half.ico":   ("半", SLATE, (255, 255, 255, 255), YAHEI_BOLD),
    "reload.ico": ("↻", ORANGE, (255, 255, 255, 255), SEGOE_SYM),
}

def render(size, ch, bg, fg, font_path):
    """渲染单个尺寸：4x 超采样抗锯齿后缩回。"""
    ss = 4
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    radius = int(s * 0.22)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=bg)
    # 字号：单字占画布 ~72%
    font_size = int(s * 0.72)
    font = ImageFont.truetype(font_path, font_size)
    cx, cy = s / 2, s / 2 - s * 0.02  # 视觉重心略上移
    d.text((cx, cy), ch, font=font, fill=fg, anchor="mm")
    return img.resize((size, size), Image.LANCZOS)

for name, (ch, bg, fg, font_path) in ICONS.items():
    frames = [render(sz, ch, bg, fg, font_path) for sz in SIZES]
    ico_path = os.path.join(OUT, name)
    frames[-1].save(
        ico_path, format="ICO",
        append_images=frames[:-1],
        sizes=[(sz, sz) for sz in SIZES],
    )
    print(f"wrote {ico_path}")

# Linux（ibus/fcitx5）品牌图标：单档 PNG，随 Ubuntu 数据包分发
png = render(128, "帅", BLUE, (255, 255, 255, 255), YAHEI_BOLD)
png_path = os.path.join(OUT, "dashuai-pinyin.png")
png.save(png_path)
print(f"wrote {png_path}")

# 生成预览拼图：每个图标的 16/32/256 三档
pad = 12
cell = 256 + pad * 2
sheet = Image.new("RGBA", (cell * len(ICONS), cell + 80), (245, 246, 248, 255))
d = ImageDraw.Draw(sheet)
label_font = ImageFont.truetype(YAHEI_BOLD, 22)
for i, (name, (ch, bg, fg, fp)) in enumerate(ICONS.items()):
    x0 = i * cell + pad
    big = render(256, ch, bg, fg, fp)
    sheet.paste(big, (x0, pad), big)
    small16 = render(16, ch, bg, fg, fp).resize((64, 64), Image.NEAREST)
    small32 = render(32, ch, bg, fg, fp).resize((64, 64), Image.NEAREST)
    sheet.paste(small16, (x0, pad + 256 - 64), small16)
    sheet.paste(small32, (x0 + 72, pad + 256 - 64), small32)
    d.text((x0 + 128, cell + 30), name, font=label_font, fill=(40, 40, 40, 255), anchor="mm")
preview = os.path.join(OUT, "preview.png")
sheet.convert("RGB").save(preview)
print(f"wrote {preview}")
