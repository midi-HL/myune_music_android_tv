#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""StarNote 品牌资产生成器。

设计依据：参考同屏其它应用图标（纯色/渐变圆角底 + 一个简洁几何符号），
避免旧版「圆圈 + 音符 + 星 + 中文 + 英文 + 下划线 + 描边框」的拼贴感。

要点：
  * 4 倍超采样绘制 + LANCZOS 缩小，消除锯齿；所有图形走光栅抗锯齿；
  * 背景为深靛蓝→蓝的对角渐变，叠两处低强度青/紫光晕（多彩但克制）；
  * 主体是一个连贯的「音符 + 星」几何符号：倾斜符头 + 圆角符干 +
    一枚暖金四角星，青绿→青蓝渐变；不堆叠多个独立小图标；
  * launcher 不使用任何文字；TV banner 仅保留极简品牌名。

运行：python ci/branding/generate_branding.py
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

S = 4  # 超采样倍率
OUT = os.path.dirname(os.path.abspath(__file__))

# ---- 配色（RGB） ----
BG_TOP = (15, 29, 56)
BG_BOTTOM = (39, 78, 140)
GLOW_CYAN = (72, 198, 228)
GLOW_VIOLET = (126, 98, 202)
SYM_TOP = (128, 238, 206)
SYM_BOTTOM = (64, 172, 246)
STAR = (255, 198, 106)
TEXT_MAIN = (242, 249, 255)
TEXT_SUB = (128, 212, 236)

FONT_CN = "C:/Windows/Fonts/msyhbd.ttc"
FONT_EN = "C:/Windows/Fonts/segoeuib.ttf"
FONT_EN_FALLBACK = "C:/Windows/Fonts/arialbd.ttf"


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vertical_gradient(w, h, top, bottom):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=lerp(top, bottom, t) + (255,))
    return img


def glow(w, h, box, color, alpha, blur):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def background(w, h, radius, round_shape=False):
    """渐变 + 光晕 + 圆角/圆形裁剪。"""
    img = vertical_gradient(w, h, BG_TOP, BG_BOTTOM)
    # 顶部偏左的青色光晕、右下角的紫色光晕，强度都压得很低。
    img = Image.alpha_composite(
        img,
        glow(
            w, h,
            (int(w * 0.02), int(-h * 0.42), int(w * 1.02), int(h * 0.62)),
            GLOW_CYAN, 66, w * 0.15,
        ),
    )
    img = Image.alpha_composite(
        img,
        glow(
            w, h,
            (int(w * 0.48), int(h * 0.52), int(w * 1.28), int(h * 1.32)),
            GLOW_VIOLET, 48, w * 0.18,
        ),
    )
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    if round_shape:
        md.ellipse((0, 0, w - 1, h - 1), fill=255)
    else:
        md.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    img.putalpha(mask)
    return img


def star_polygon(cx, cy, r_outer, r_inner, rotation_deg=-16):
    pts = []
    for i in range(8):
        ang = math.radians(rotation_deg + i * 45 - 90)
        r = r_outer if i % 2 == 0 else r_inner
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return pts


def symbol_layer(w, h, box):
    """在 box 内画「音符 + 星」，返回 RGBA 透明层。

    box = (left, top, right, bottom)；内部用 0..1 归一化坐标，
    因此同一个函数可直接用于正方形 launcher 与横版 banner。
    """
    bx, by, bw, bh = box[0], box[1], box[2] - box[0], box[3] - box[1]

    def X(u):
        return bx + u * bw

    def Y(v):
        return by + v * bh

    # --- 主体 mask（符头 + 符干） ---
    sm = Image.new("L", (w, h), 0)

    # 倾斜符头：单独图层旋转后再合并，避免椭圆只能正放的呆板感。
    head = Image.new("L", (w, h), 0)
    cx, cy = X(0.365), Y(0.660)
    rx, ry = bw * 0.190, bh * 0.155
    ImageDraw.Draw(head).ellipse(
        (cx - rx, cy - ry, cx + rx, cy + ry), fill=255
    )
    head = head.rotate(-20, resample=Image.BICUBIC, center=(cx, cy))
    sm = ImageChops.lighter(sm, head)

    # 符干：略向右上倾斜的粗圆角线，两端补圆，得到柔和端点。
    sd = ImageDraw.Draw(sm)
    stem_w = int(bw * 0.098)
    start = (X(0.520), Y(0.635))
    end = (X(0.560), Y(0.190))
    sd.line([start, end], fill=255, width=stem_w, joint="curve")
    for px, py in (start, end):
        r = stem_w / 2
        sd.ellipse((px - r, py - r, px + r, py + r), fill=255)

    # 主体渐变：青绿 → 青蓝。
    sym = vertical_gradient(w, h, SYM_TOP, SYM_BOTTOM)
    sym.putalpha(sm)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    layer = Image.alpha_composite(layer, sym)

    # --- 暖金四角星（点缀色，不与主体渐变混合） ---
    star_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(star_mask).polygon(
        star_polygon(X(0.745), Y(0.245), bw * 0.150, bw * 0.062),
        fill=255,
    )
    star_img = Image.new("RGBA", (w, h), STAR + (255,))
    star_img.putalpha(star_mask)
    layer = Image.alpha_composite(layer, star_img)

    # --- 底部一条极淡的音波弧线，增加一点灵动但不喧宾夺主 ---
    wave = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wave)
    pts = []
    for i in range(25):
        u = i / 24
        xx = X(0.10 + 0.80 * u)
        yy = Y(0.865 - 0.055 * math.sin(math.pi * u))
        pts.append((xx, yy))
    wd.line(pts, fill=(168, 226, 244, 82), width=max(2, int(bh * 0.016)),
            joint="curve")
    layer = Image.alpha_composite(layer, wave)
    return layer


def make_launcher(size, round_shape=False):
    w = h = size * S
    img = background(w, h, int(w * 0.225), round_shape=round_shape)
    sym = symbol_layer(w, h, (w * 0.10, h * 0.10, w * 0.90, h * 0.90))
    img = Image.alpha_composite(img, sym)
    return img.resize((size, size), Image.LANCZOS)


def make_banner(width=320, height=180):
    w, h = width * S, height * S
    img = background(w, h, int(h * 0.135))
    # 左侧：符号；右侧：极简品牌名。
    sym = symbol_layer(w, h, (w * 0.055, h * 0.10, w * 0.375, h * 0.90))
    img = Image.alpha_composite(img, sym)

    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    try:
        cn = ImageFont.truetype(FONT_CN, int(h * 0.225))
    except OSError:
        cn = ImageFont.load_default()
    try:
        en = ImageFont.truetype(FONT_EN, int(h * 0.075))
    except OSError:
        en = ImageFont.truetype(FONT_EN_FALLBACK, int(h * 0.075))

    left = w * 0.425
    d.text((left, h * 0.270), "星音", font=cn, fill=TEXT_MAIN + (255,))

    # 英文逐字拉开字距，比整串文字更克制。
    label = "STARNOTE"
    spacing = h * 0.014
    x = left + h * 0.012
    for ch in label:
        d.text((x, h * 0.565), ch, font=en, fill=TEXT_SUB + (255,))
        x += d.textlength(ch, font=en) + spacing
    img = Image.alpha_composite(img, overlay)
    return img.resize((width, height), Image.LANCZOS)


def main():
    densities = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in densities.items():
        make_launcher(size).save(
            os.path.join(OUT, f"ic_launcher-{density}.png"), "PNG"
        )
        make_launcher(size, round_shape=True).save(
            os.path.join(OUT, f"ic_launcher_round-{density}.png"), "PNG"
        )
        print(f"generated ic_launcher[-_round]-{density}.png ({size}px)")
    make_banner().save(os.path.join(OUT, "tv_banner.png"), "PNG")
    print("generated tv_banner.png (320x180)")


if __name__ == "__main__":
    main()
