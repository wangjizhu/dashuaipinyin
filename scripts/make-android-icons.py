# -*- coding: utf-8 -*-
"""大帅拼音 Android 图标生成：mipmap 方/圆启动图标 + 自适应前景 PNG。

用法: python make-android-icons.py <输出目录>
输出目录结构与 Trime res/ 对应，可直接覆盖拷贝。
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "android-icons-out"
YAHEI_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
BLUE = (43, 91, 215, 255)
WHITE = (255, 255, 255, 255)

# 密度 -> (mipmap 尺寸, drawable 前景画布尺寸=108dp)
DENSITIES = {
    "mdpi": (48, 108), "hdpi": (72, 162), "xhdpi": (96, 216),
    "xxhdpi": (144, 324), "xxxhdpi": (192, 432),
}

def glyph(canvas, ch, ratio, fg):
    """透明画布上居中渲染单字（4x 超采样）。"""
    ss = 4
    s = canvas * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(YAHEI_BOLD, int(s * ratio))
    d.text((s / 2, s / 2 - s * 0.02), ch, font=font, fill=fg, anchor="mm")
    return img.resize((canvas, canvas), Image.LANCZOS)

def launcher(size, rounded):
    """蓝底帅字启动图标：rounded=False 圆角方形，True 正圆。"""
    ss = 4
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.ellipse([0, 0, s - 1, s - 1], fill=BLUE)
    else:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=BLUE)
    font = ImageFont.truetype(YAHEI_BOLD, int(s * 0.62))
    d.text((s / 2, s / 2 - s * 0.02), "帅", font=font, fill=WHITE, anchor="mm")
    return img.resize((size, size), Image.LANCZOS)

for dens, (mip, fgcanvas) in DENSITIES.items():
    mdir = os.path.join(OUT, f"mipmap-{dens}")
    ddir = os.path.join(OUT, f"drawable-{dens}")
    os.makedirs(mdir, exist_ok=True)
    os.makedirs(ddir, exist_ok=True)
    launcher(mip, False).save(os.path.join(mdir, "ic_app_icon.png"))
    launcher(mip, True).save(os.path.join(mdir, "ic_app_icon_round.png"))
    # 自适应前景：白帅字，占画布 ~46%（安全区为中央 66/108）
    glyph(fgcanvas, "帅", 0.46, WHITE).save(os.path.join(ddir, "ic_app_icon_foreground.png"))
    print(f"{dens}: mipmap {mip}px, foreground {fgcanvas}px")
print("done")
