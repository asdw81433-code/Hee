#!/usr/bin/env python3
"""ตัดต่อคลิป 'นักพากย์โลกสวย' อัตโนมัติ: python3 make_clip.py
ใส่คลิปไว้ในโฟลเดอร์ clips/ ตามชื่อใน shots.json แล้วรัน ได้ไฟล์ output.mp4 (แนวตั้ง 1080x1920)"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
W, H, FPS = 1080, 1920, 30
cfg = json.load(open(os.path.join(HERE, "shots.json"), encoding="utf-8"))
FONT = cfg.get("font", "Loma")
TMP = os.path.join(HERE, "_tmp"); os.makedirs(TMP, exist_ok=True)

def run(args):
    r = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"] + args)
    if r.returncode: sys.exit("ffmpeg ล้มเหลว")

EMOJI = re.compile("[\U0001F000-\U0001FAFF\u2600-\u27BF\uFE0F]")

def write_ass(path, text, dur, center=False):
    """ซับแบบ ASS ขนาดเท่าจอจริง ตัดอีโมจิออก (ฟอนต์ซับวาดอีโมจิสีไม่ได้)"""
    text = EMOJI.sub("", text).strip().replace("\n", "\\N")
    align, mv = (5, 0) if center else (2, 420)
    c = lambda t: f"{int(t//3600)}:{int(t%3600//60):02}:{t%60:05.2f}"
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 0

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV
Style: D,{FONT},84,&H00FFFFFF,&H00000000,&H80000000,1,0,1,6,3,{align},60,60,{mv}

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,{c(0.3)},{c(dur)},D,{{\\fad(150,0)}}{text}
""")

def esc(p):  # escape path for filtergraph
    return p.replace("\\", "/").replace(":", "\\:").replace("'", "\\'")

def card(text, dur, out):
    sub = out + ".ass"; write_ass(sub, text, dur, center=True)
    run(["-f", "lavfi", "-i", f"color=c=0x101828:s={W}x{H}:r={FPS}:d={dur}",
         "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", str(dur),
         "-vf", f"ass='{esc(sub)}'",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", out])

def shot(i, s, out):
    src = os.path.join(HERE, "clips", s["file"])
    if not os.path.exists(src):
        sys.exit(f"ไม่พบไฟล์ {src}")
    dur = float(s["dur"]); slow = s.get("slowmo")
    final = dur * 2 if slow else dur
    sub = os.path.join(TMP, f"s{i}.ass"); write_ass(sub, s["text"], final)
    speed = "setpts=2.0*PTS," if slow else ""
    # พื้นหลังเบลอเต็มจอ + คลิปจริงอยู่ตรงกลาง (แนวตั้งสำหรับ TikTok/Reels)
    vf = (f"[0:v]{speed}fps={FPS},split[a][b];"
          f"[a]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},boxblur=20:2[bg];"
          f"[b]scale={W}:-2[fg];"
          f"[bg][fg]overlay=(W-w)/2:(H-h)/2,"
          f"ass='{esc(sub)}'[v]")
    run(["-ss", s["start"], "-t", str(dur), "-i", src,
         "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
         "-filter_complex", vf, "-map", "[v]", "-map", "1:a", "-t", str(final),
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", out])

parts = []
p = os.path.join(TMP, "intro.mp4"); card(cfg["intro"], 3, p); parts.append(p)
for i, s in enumerate(cfg["shots"]):
    p = os.path.join(TMP, f"shot{i}.mp4"); print("ตัดช็อต", i + 1, s["file"]); shot(i, s, p); parts.append(p)
p = os.path.join(TMP, "outro.mp4"); card(cfg["outro"], 3, p); parts.append(p)

lst = os.path.join(TMP, "list.txt")
open(lst, "w").write("".join(f"file '{x}'\n" for x in parts))
joined = os.path.join(TMP, "joined.mp4")
run(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", joined])

out = os.path.join(HERE, "output.mp4")
music = os.path.join(HERE, cfg.get("music", ""))
if cfg.get("music") and os.path.exists(music):
    run(["-i", joined, "-stream_loop", "-1", "-i", music, "-map", "0:v", "-map", "1:a",
         "-c:v", "copy", "-c:a", "aac", "-shortest", out])
else:
    os.replace(joined, out)
print("เสร็จแล้ว →", out)
