#!/usr/bin/env python3
"""คลิปการ์ตูน 'นักพากย์โลกสวย' — วาดทุกฉากเอง ไม่ใช้ฟุตเทจที่ติดลิขสิทธิ์
รัน: python3 cartoon_clip.py  → ได้ไฟล์ output_cartoon.mp4 (1080x1920, 30fps)"""
import math, os, subprocess, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H, FPS = 1080, 1920, 30
GROUND = 1150                    # เส้นพื้นของฉากด้านข้าง (y ของสะโพกตอนยืน)
U = 40                           # ขนาดตัวละคร
SKIN, OUT = (247, 205, 160), (30, 30, 30)
RED, BLUE, YEL, BLACK = (220, 50, 50), (40, 110, 230), (250, 200, 30), (40, 40, 40)
LAT = ImageFont.truetype("/usr/share/fonts/opentype/tlwg/Loma-Bold.otf", 70)
LAT_S = ImageFont.truetype("/usr/share/fonts/opentype/tlwg/Loma-Bold.otf", 44)

def lerp(a, b, k): return a + (b - a) * max(0.0, min(1.0, k))
def ease(k): k = max(0.0, min(1.0, k)); return k * k * (3 - 2 * k)
def seg(t, a, b): return max(0.0, min(1.0, (t - a) / (b - a)))

# ---------------------------------------------------------------- ฉากหลัง
def pitch(d, crowd=False):
    for i in range(0, H, 160):
        d.rectangle([0, i, W, i + 80], fill=(70, 160, 70))
        d.rectangle([0, i + 80, W, i + 160], fill=(80, 175, 80))
    d.rectangle([0, 0, W, 420], fill=(120, 190, 240))       # ท้องฟ้า
    d.rectangle([0, 330, W, 430], fill=(90, 90, 110))        # อัฒจันทร์
    cols = [(230, 80, 80), (80, 120, 230), (250, 220, 60), (240, 240, 240)]
    for i in range(36):
        x = 15 + i * 30; y = 355 + (i % 2) * 30
        d.ellipse([x, y, x + 22, y + 22], fill=cols[i % 4])
    d.line([0, 430, W, 430], fill="white", width=8)

def hearts(d, cx, cy, t, n=6, spread=160, col=(255, 90, 140)):
    for i in range(n):
        ph = (t * 0.8 + i / n) % 1
        x = cx + math.sin(i * 2.3 + t * 2) * spread * 0.6
        y = cy - ph * spread * 1.6
        s = 22 * (1 - ph * 0.5)
        heart(d, x, y, s, col)

def heart(d, x, y, s, col=(255, 90, 140)):
    d.ellipse([x - s, y - s, x, y], fill=col)
    d.ellipse([x, y - s, x + s, y], fill=col)
    d.polygon([(x - s, y - s * 0.4), (x + s, y - s * 0.4), (x, y + s)], fill=col)

def sparkle(d, x, y, s, col=(255, 250, 180)):
    d.polygon([(x, y - s), (x + s * .25, y - s * .25), (x + s, y), (x + s * .25, y + s * .25),
               (x, y + s), (x - s * .25, y + s * .25), (x - s, y), (x - s * .25, y - s * .25)], fill=col)

def ball(d, x, y, r=32):
    d.ellipse([x - r, y - r, x + r, y + r], fill="white", outline=OUT, width=4)
    d.regular_polygon((x, y, r * .45), 5, fill=OUT)

def zzz(d, x, y, t):
    for i in range(3):
        ph = (t * 0.6 + i / 3) % 1
        d.text((x + ph * 80 + i * 10, y - ph * 160), "z", font=LAT if i == 2 else LAT_S,
               fill=(255, 255, 255), stroke_width=4, stroke_fill=(60, 60, 120))

# ---------------------------------------------------------------- ตัวละคร
def player(d, x, y, col, face=1, theta=0.0, run=None, arms=None, legs=None, eyes="open", u=U, num=None):
    """x,y = สะโพก; theta = เอียงตัว (เรเดียน, + = หงายไปข้างหลัง); run = เฟสการวิ่ง"""
    a = math.sin(run) * 0.7 if run is not None else 0.0
    pts = {"hip": (0, 0), "neck": (0, -3.2 * u), "head": (0, -4.6 * u)}
    pts["f1"] = legs[0] if legs else (math.sin(a) * 2.8 * u, math.cos(a) * 2.8 * u)
    pts["f2"] = legs[1] if legs else (-math.sin(a) * 2.8 * u, math.cos(a) * 2.8 * u)
    pts["h1"] = arms[0] if arms else (-math.sin(a) * 1.9 * u, -3.2 * u + math.cos(a) * 1.9 * u)
    pts["h2"] = arms[1] if arms else (math.sin(a) * 1.9 * u, -3.2 * u + math.cos(a) * 1.9 * u)
    c, s = math.cos(theta), math.sin(theta)
    # หมุนในพิกัดของตัวเอง (หันขวา) แล้วค่อยกลับด้านถ้าหันซ้าย
    P = {k: (x + face * (px * c - py * s), y + (px * s + py * c)) for k, (px, py) in pts.items()}
    lw = int(0.75 * u)
    for f in ("f1", "f2"):
        d.line([P["hip"], P[f]], fill=SKIN, width=lw)
        d.ellipse([P[f][0] - lw * .8, P[f][1] - lw * .6, P[f][0] + lw * .8, P[f][1] + lw * .6], fill=OUT)
    for h in ("h1", "h2"):
        d.line([P["neck"], P[h]], fill=SKIN, width=int(lw * .8))
    d.line([P["hip"], P["neck"]], fill=col, width=int(1.9 * u))
    hx, hy = P["hip"]; d.ellipse([hx - u, hy - u * .8, hx + u, hy + u * .8], fill="white")
    if num:
        mx, my = (P["hip"][0] + P["neck"][0]) / 2, (P["hip"][1] + P["neck"][1]) / 2
        d.text((mx, my), num, font=LAT_S, fill="white", anchor="mm")
    cx, cy = P["head"]; r = 1.25 * u
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SKIN, outline=OUT, width=4)
    ex = face * r * .35
    for dx in (ex - r * .25, ex + r * .3):
        if eyes == "open":
            d.ellipse([cx + dx - 5, cy - 9, cx + dx + 5, cy + 3], fill=OUT)
        elif eyes == "closed":
            d.arc([cx + dx - 9, cy - 8, cx + dx + 9, cy + 6], 20, 160, fill=OUT, width=4)
        elif eyes == "happy":
            d.arc([cx + dx - 9, cy - 4, cx + dx + 9, cy + 12], 200, 340, fill=OUT, width=4)
        elif eyes == "x":
            d.line([cx + dx - 7, cy - 9, cx + dx + 7, cy + 5], fill=OUT, width=4)
            d.line([cx + dx - 7, cy + 5, cx + dx + 7, cy - 9], fill=OUT, width=4)
    if eyes in ("closed", "happy"):
        d.ellipse([cx + ex - r * .7, cy + 6, cx + ex - r * .35, cy + 20], fill=(250, 150, 150))
    return P

# ---------------------------------------------------------------- ฉาก (รับ t = วินาทีในฉาก)
def s_slide(d, t):
    pitch(d)
    bx = lerp(120, 560, seg(t, 0, 2.2))
    if t < 2.2:
        player(d, bx, GROUND, BLUE, 1, run=t * 12, num="10")
        ball(d, bx + 2.3 * U + math.sin(t * 12) * 10, GROUND + 2.6 * U)
    else:
        k = ease(seg(t, 2.2, 3.0))
        fx = lerp(560, 840, k); fy = GROUND - math.sin(k * math.pi) * 300 + k * 1.7 * U
        th = -k * (2 * math.pi + math.pi / 2)
        eyes = "x" if t < 3.0 else "closed"
        if t > 3.2:   # หมอนรองหัว
            d.rounded_rectangle([fx - 6.3 * U, GROUND + 2.2 * U, fx - 3.0 * U, GROUND + 3.3 * U], 25, fill=(245, 245, 255), outline=OUT, width=4)
        player(d, fx, fy, BLUE, 1, theta=th, eyes=eyes, num="10",
               legs=[(1.2 * U, 2.6 * U), (-.6 * U, 2.8 * U)], arms=[(-1.5 * U, -1.6 * U), (1.4 * U, -1.8 * U)])
        if t > 3.2: zzz(d, fx - 4.4 * U, GROUND - 1.5 * U, t)
        ball(d, lerp(650, 1040, seg(t, 2.2, 3.4)), GROUND + 2.6 * U - math.sin(seg(t, 2.2, 3.4) * math.pi) * 120)
    rx = lerp(1000, 520, ease(seg(t, 0.8, 2.25)))
    if t < 0.8:
        pass
    elif t < 2.6:
        player(d, rx, GROUND + 2.1 * U, RED, -1, theta=1.25, eyes="open", num="4",
               legs=[(2.9 * U, .3 * U), (2.2 * U, 1.3 * U)], arms=[(-1.8 * U, -2 * U), (1.5 * U, -4.6 * U)])
    else:
        player(d, 330, GROUND, RED, 1, eyes="happy", num="4", arms=[(-1.6 * U, -3.5 * U), (2.2 * U, -6.5 * U)])
        sparkle(d, 330 + 2.2 * U, GROUND - 6.8 * U, 30 + 8 * math.sin(t * 9))
        if t > 3.2: hearts(d, 330, GROUND - 300, t, 4, 140)

def s_shirt(d, t):
    pitch(d)
    rel = 3.4
    if t < rel:
        bx = 620 + math.sin(t * 3) * 10
        P = player(d, bx, GROUND, BLUE, 1, run=t * 16, num="9")
        st = 180 + math.sin(t * 6) * 80 + t * 50      # เสื้อยืด
        nx, ny = (P["hip"][0] + P["neck"][0]) / 2 - 20, (P["hip"][1] + P["neck"][1]) / 2
        hand = (nx - st, ny + 10)
        d.polygon([(nx, ny - 70), (nx, ny + 70), hand], fill=BLUE)
        rx = hand[0] - 2.5 * U
        player(d, rx, GROUND, RED, 1, theta=-0.35, num="5", eyes="happy",
               arms=[(2.1 * U, -2.2 * U), (2.3 * U, -2.0 * U)], legs=[(-1.5 * U, 2.5 * U), (1 * U, 2.7 * U)])
    else:
        k = ease(seg(t, rel, rel + 0.6))
        bx = lerp(620, 900, k)
        th = -k * 1.5
        player(d, bx, GROUND + k * 1.7 * U, BLUE, 1, theta=th, num="9", eyes="x" if k < 1 else "closed",
               arms=[(1.8 * U, -4.5 * U), (2.3 * U, -3.8 * U)])
        player(d, 260, GROUND, RED, 1, eyes="happy", num="5", arms=[(1.6 * U, -5 * U), (-1.6 * U, -5 * U)])
        for i in range(5):
            sparkle(d, 720 + i * 60, GROUND - 260 - (i % 2) * 50, 18 + 6 * math.sin(t * 8 + i))

def s_dive(d, t):
    pitch(d)
    player(d, 880, GROUND, RED, -1, eyes="open", num="3", arms=[(-1.5 * U, -1.2 * U), (1.5 * U, -1.2 * U)])
    if t > 1.0 and t < 1.8:
        d.text((800, GROUND - 400), "?", font=LAT, fill="white", stroke_width=5, stroke_fill=OUT)
    if t < 1.2:
        bx = lerp(120, 480, seg(t, 0, 1.2))
        player(d, bx, GROUND, BLUE, 1, run=t * 12, num="11")
    else:
        k = seg(t, 1.2, 3.2)
        bx = lerp(480, 660, k) + math.sin(k * 9) * 30
        th = -ease(k) * 6 * math.pi - (math.pi / 2 if k >= 1 else 0)
        y = GROUND - abs(math.sin(k * 3 * math.pi)) * 120 * (1 - k) + 1.7 * U * min(1, k * 3)
        player(d, bx, y, BLUE, 1, theta=th if k < 1 else -math.pi / 2, num="11",
               eyes="closed" if k >= 1 else "x",
               arms=[(2.8 * U, -1.5 * U), (2.6 * U, -.5 * U)] if k >= 1 else None)
        if k >= 1:
            hearts(d, bx - 2 * U, GROUND - 120, t, 7, 220)
            for i in range(6):   # หญ้าที่ถูกกอด
                gx = bx - 6 * U + i * 70
                d.polygon([(gx, GROUND + 3.4 * U), (gx + 16, GROUND + 2.2 * U), (gx + 32, GROUND + 3.4 * U)], fill=(40, 130, 40))

def s_keeper(d, t):
    d.rectangle([0, 0, W, H], fill=(80, 175, 80))
    for i in range(0, H, 160): d.rectangle([0, i, W, i + 80], fill=(70, 160, 70))
    d.rectangle([0, 0, W, 520], fill=(120, 190, 240))
    gx0, gx1, gy0, gy1 = 120, 960, 560, 1100
    bulge = 0
    if t > 2.0: bulge = 30 * math.exp(-(t - 2.0) * 2) * math.sin((t - 2.0) * 12)
    for i in range(0, 25):
        x = gx0 + i * (gx1 - gx0) / 24
        d.line([x, gy0, x + (bulge if 8 < i < 16 else 0), gy1], fill=(230, 230, 230), width=2)
    for j in range(0, 16):
        y = gy0 + j * (gy1 - gy0) / 15
        d.line([gx0, y, gx1, y], fill=(230, 230, 230), width=2)
    d.rectangle([gx0 - 14, gy0 - 14, gx1 + 14, gy0 + 4], fill="white")
    d.rectangle([gx0 - 14, gy0, gx0 + 4, gy1], fill="white")
    d.rectangle([gx1 - 4, gy0, gx1 + 14, gy1], fill="white")
    spread = lerp(1.2, 4.0, ease(seg(t, 0.8, 1.6)))
    look = t > 2.2
    player(d, 540, 950, YEL, -1 if look else 1, eyes="happy" if t > 1.6 else "open", u=46, num="1",
           legs=[(spread * 46, 2.4 * 46), (-spread * 46, 2.4 * 46)],
           arms=[(-1.2 * 46, -1.6 * 46), (1.2 * 46, -1.6 * 46)] if t < 1.6 else [(-2.4 * 46, -5 * 46), (2.4 * 46, -5 * 46)])
    k = seg(t, 0.3, 2.0)
    by = lerp(1750, 1030, ease(k)); r = lerp(90, 34, k)
    if t < 2.0: ball(d, 540 + math.sin(k * 6) * 40 * (1 - k), by, r)
    else: ball(d, 540 + bulge, 1060, 34)
    if t > 2.0:
        for i in range(5): sparkle(d, 330 + i * 110, 640 + (i % 2) * 60, 20 + 6 * math.sin(t * 7 + i))

def s_penalty(d, t):
    pitch(d)
    for i in range(0, 4):  # ประตูด้านข้าง
        pass
    d.rectangle([800, GROUND - 6.8 * U, 818, GROUND + 3 * U], fill="white")
    d.rectangle([800, GROUND - 6.8 * U, 1080, GROUND - 6.8 * U + 18], fill="white")
    player(d, 950, GROUND, YEL, -1, num="1", eyes="open" if t < 2.2 else "happy")
    run_t = min(t, 1.2)
    kx = lerp(120, 366, seg(t, 0, 1.2))
    if t < 1.2: player(d, kx, GROUND, RED, 1, run=t * 12, num="7")
    else: player(d, 366, GROUND, RED, 1, theta=-0.3, num="7", eyes="open",
                 legs=[(2.6 * U, -.8 * U), (-.6 * U, 2.8 * U)], arms=[(-2 * U, -4.6 * U), (2 * U, -2 * U)])
    if t < 1.2: ball(d, 470, GROUND + 2.6 * U)
    else:
        k = seg(t, 1.2, 2.6)
        x = lerp(470, 620, k); y = lerp(GROUND + 2.6 * U, 380, k) - math.sin(k * math.pi) * 500
        if t < 2.6: ball(d, x, y)
        else:   # แฟนบอลรับได้
            fx = 620
            d.ellipse([fx - 30, 330, fx + 30, 390], fill=SKIN, outline=OUT, width=4)
            d.arc([fx - 15, 345, fx + 15, 375], 200, 340, fill=OUT, width=4)
            d.line([fx - 30, 380, fx - 45, 310], fill=SKIN, width=12)
            d.line([fx + 30, 380, fx + 45, 310], fill=SKIN, width=12)
            ball(d, fx, 290)
            hearts(d, fx, 280, t, 6, 140)
            sparkle(d, fx - 90, 300, 24 + 6 * math.sin(t * 9)); sparkle(d, fx + 90, 300, 24 + 6 * math.cos(t * 9))

def s_redcard(d, t):
    pitch(d)
    d.rounded_rectangle([20, GROUND - 7 * U, 240, GROUND + 3 * U], 20, fill=(150, 110, 70), outline=OUT, width=5)
    d.rounded_rectangle([10, GROUND - 9.6 * U, 250, GROUND - 7.4 * U], 16, fill=(250, 220, 60), outline=OUT, width=5)
    d.text((130, GROUND - 8.5 * U), "VIP", font=LAT, fill=OUT, anchor="mm")
    up = ease(seg(t, 0.4, 0.9))
    P = player(d, 760, GROUND, BLACK, -1, eyes="open",
               arms=[(lerp(1.5, .8, up) * U, lerp(-1.5, -7, up) * U), (-1.4 * U, -1.6 * U)])
    if up > 0:
        hx, hy = P["h1"]
        d.rounded_rectangle([hx - 30, hy - 100, hx + 30, hy], 8, fill=(230, 30, 30), outline=OUT, width=4)
        if t < 1.6:
            for i in range(4): sparkle(d, hx + math.cos(i * 1.6 + t * 4) * 90, hy - 50 + math.sin(i * 1.6 + t * 4) * 90, 18)
    if t < 1.6:
        player(d, 470, GROUND, RED, 1, eyes="open", num="8", arms=[(.5 * U, -6 * U), (-.5 * U, -6 * U)])
    else:
        k = seg(t, 1.6, 4.4)
        px = lerp(470, 130, k)
        if k < 1: player(d, px, GROUND, RED, -1, run=t * 10, eyes="happy", num="8")
        else:
            d.text((125, GROUND - 230), "❄", font=LAT, fill="white", anchor="mm") if False else None
            for i in range(5): sparkle(d, 50 + i * 40, GROUND - 6 * U - (i % 2) * 40, 18, (200, 240, 255))

def s_chest(d, t):
    pitch(d)
    cyc = (t * 1.2) % 1
    gap = 2.3 * U + abs(math.cos(cyc * math.pi)) * 260
    hit = cyc < 0.08
    lx, rx = 540 - gap / 2, 540 + gap / 2
    player(d, lx, GROUND, RED, 1, theta=-0.25 if cyc < .5 else 0.1, eyes="closed" if hit else "happy", num="6",
           arms=[(1.8 * U, -1.5 * U), (-1.6 * U, -1.2 * U)])
    player(d, rx, GROUND, BLUE, -1, theta=-0.25 if cyc < .5 else 0.1, eyes="closed" if hit else "happy", num="8",
           arms=[(1.8 * U, -1.5 * U), (-1.6 * U, -1.2 * U)])
    if t > 1.0: hearts(d, 540, GROUND - 320, t, 6, 200)

SCENES = [
    (s_slide,   5.0, "เห็นคู่แข่งวิ่งมาทั้งเกมจนเหนื่อย\nเลยช่วยให้ได้นอนพักสักหน่อยครับ", [2.2]),
    (s_shirt,   5.0, "เสื้อคู่แข่งยับนิดหน่อย\nเลยช่วยดึงให้เรียบ ใส่ใจรายละเอียดมาก", [3.4]),
    (s_dive,    5.0, "หญ้านุ่มขนาดนี้\nอดใจไม่ไหว ต้องขอกอดสักหน่อย", [1.4, 3.2]),
    (s_keeper,  4.5, "บอลอยากเข้าไปเที่ยวในตาข่าย\nโกลเลยใจดี หลีกทางให้ครับ", [2.0]),
    (s_penalty, 5.0, "ของขวัญสำหรับแฟนบอลแถวบนสุด\nส่งตรงถึงที่นั่งเลยครับ", [1.2]),
    (s_redcard, 5.0, "กรรมการมอบบัตรวีไอพีให้\nได้ไปพักห้องแอร์ก่อนใครเลย", []),
    (s_chest,   5.0, "สองคนนี้ไม่ได้เจอกันนาน\nขอซบอกกันหน่อยครับ", []),
]
INTRO = ("ฟุตบอล…\nกีฬาแห่งมิตรภาพ\nและความห่วงใย", 3.0)
OUTRO = ("และนี่คือฟุตบอล\nกีฬาแห่งความรัก", 3.5)

def title_card(d, t, outro=False):
    d.rectangle([0, 0, W, H], fill=(255, 236, 244) if outro else (230, 245, 255))
    for i in range(14):
        heart(d, (i * 173) % W, (i * 311 + t * 120) % H, 26, (255, 170, 200))
    ball(d, W / 2, 620 + math.sin(t * 5) * 30, 90)

# ---------------------------------------------------------------- เรนเดอร์
def render(out):
    TMP = os.path.join(HERE, "_tmp"); os.makedirs(TMP, exist_ok=True)
    timeline, cur, impacts, whistles = [], 0.0, [], []
    timeline.append(("intro", INTRO[1], INTRO[0])); cur += INTRO[1]
    for fn, dur, txt, imp in SCENES:
        timeline.append((fn, dur, txt)); impacts += [cur + x for x in imp]
        if fn is s_redcard: whistles.append(cur + 0.4)
        cur += dur
    timeline.append(("outro", OUTRO[1], OUTRO[0])); total = cur + OUTRO[1]

    # ซับ ASS
    def c(x): return f"{int(x // 3600)}:{int(x % 3600 // 60):02}:{x % 60:05.2f}"
    ass = os.path.join(TMP, "cartoon.ass")
    with open(ass, "w", encoding="utf-8") as f:
        f.write(f"[Script Info]\nScriptType: v4.00+\nPlayResX: {W}\nPlayResY: {H}\nWrapStyle: 0\n\n"
                "[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, "
                "Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV\n"
                "Style: D,Loma,80,&H00FFFFFF,&H00000000,&H80000000,1,0,1,7,3,2,50,50,330\n"
                "Style: C,Loma,96,&H00FFFFFF,&H00B04080,&H80000000,1,0,1,8,3,8,50,50,900\n"
                "Style: T,Loma,52,&H0000E0FF,&H00000000,&H80000000,1,0,1,5,2,8,40,40,70\n\n"
                "[Events]\nFormat: Layer, Start, End, Style, Text\n")
        f.write(f"Dialogue: 0,{c(INTRO[1])},{c(total - OUTRO[1])},T,ช่องพากย์โลกสวย ⚽ LIVE\n".replace(" ⚽", ""))
        st = 0.0
        for fn, dur, txt in timeline:
            sty = "C" if isinstance(fn, str) else "D"
            f.write(f"Dialogue: 0,{c(st + 0.25)},{c(st + dur)},{sty},{{\\fad(200,100)}}{txt.replace(chr(10), chr(92) + 'N')}\n")
            st += dur

    # เสียง: เพลงกล่อมแต่งเอง + เสียงกระแทก + นกหวีด
    sr = 44100; n = int(total * sr); a = np.zeros(n)
    notes = [72, 76, 79, 76, 77, 74, 71, 74, 72, 76, 79, 84, 81, 77, 74, 72]
    beat = 0.375; tt = np.arange(int(sr * 1.2)) / sr
    i = 0; pos = 0.0
    while pos < total:
        fr = 440 * 2 ** ((notes[i % len(notes)] - 69) / 12)
        tone = (np.sin(2 * np.pi * fr * tt) + .3 * np.sin(4 * np.pi * fr * tt)) * np.exp(-tt * 4) * .18
        s0 = int(pos * sr); e0 = min(n, s0 + len(tone)); a[s0:e0] += tone[:e0 - s0]
        if i % 4 == 0:
            bf = 440 * 2 ** ((notes[i % len(notes)] - 81) / 12)
            bass = np.sin(2 * np.pi * bf * tt) * np.exp(-tt * 2) * .12
            a[s0:e0] += bass[:e0 - s0]
        pos += beat; i += 1
    rng = np.random.default_rng(1)
    for x in impacts:
        L = int(sr * .35); q = np.arange(L) / sr
        thud = (np.sin(2 * np.pi * 70 * q) * .9 + rng.normal(0, .3, L)) * np.exp(-q * 14) * .7
        s0 = int(x * sr); a[s0:s0 + L] += thud[:max(0, min(L, n - s0))]
        boing = np.sin(2 * np.pi * (300 + 500 * q) * q) * np.exp(-q * 6) * .25
        s1 = s0 + int(.15 * sr); a[s1:s1 + L] += boing[:max(0, min(L, n - s1))]
    for x in whistles:
        L = int(sr * .7); q = np.arange(L) / sr
        wh = np.sin(2 * np.pi * (2600 + 120 * np.sin(2 * np.pi * 30 * q)) * q) * .25 * np.minimum(1, (L / sr - q) * 10)
        s0 = int(x * sr); a[s0:s0 + L] += wh[:max(0, min(L, n - s0))]
    a = np.clip(a / max(1e-6, np.abs(a).max()) * .85, -1, 1)
    wav = os.path.join(TMP, "audio.wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes((a * 32767).astype(np.int16).tobytes())

    esc = ass.replace(":", "\\:")
    proc = subprocess.Popen(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-i", wav,
        "-vf", f"ass='{esc}'", "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", out], stdin=subprocess.PIPE)
    gt = 0.0
    for fn, dur, txt in timeline:
        for fi in range(int(round(dur * FPS))):
            t = fi / FPS
            img = Image.new("RGB", (W, H)); d = ImageDraw.Draw(img)
            if fn == "intro": title_card(d, t)
            elif fn == "outro": title_card(d, t, True)
            else: fn(d, t)
            g = gt + t
            if any(0 <= g - x < 0.25 for x in impacts):     # สั่นจอตอนกระแทก
                k = 1 - min(g - x for x in impacts if g >= x) / 0.25
                img = img.transform(img.size, Image.AFFINE, (1, 0, math.sin(g * 90) * 18 * k, 0, 1, math.cos(g * 70) * 12 * k))
            proc.stdin.write(img.tobytes())
        gt += dur
    proc.stdin.close(); proc.wait()
    print("เสร็จแล้ว →", out, f"({total:.1f} วินาที)")

if __name__ == "__main__":
    render(os.path.join(HERE, "output_cartoon.mp4"))
