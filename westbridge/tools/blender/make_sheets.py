"""Builds the review sheets from the preview renders (run after build_characters.py --render).

    python tools/blender/make_sheets.py      (needs Pillow)

Writes assets/characters/renders/sheet_base.png, sheet_outfits.png, sheet_styles.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REN = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "characters", "renders"))
BG = (232, 234, 238)
INK = (40, 44, 52)


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/Library/Fonts/Arial Bold.ttf", "C:/Windows/Fonts/arialbd.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def sheet(name, title, rows, cell_w, label_h=34):
    """rows: list of rows; each row = list of (file, label, width) -> width in cells of cell_w."""
    imgs = []
    width = 0
    height = 70
    for row in rows:
        loaded = []
        row_h = 0
        x = 0
        for fn, label, span in row:
            im = Image.open(os.path.join(REN, fn)).convert("RGB")
            w = int(cell_w * span)
            h = int(im.height * w / im.width)
            loaded.append((im.resize((w, h), Image.LANCZOS), label, x))
            x += w
            row_h = max(row_h, h)
        width = max(width, x)
        imgs.append((loaded, row_h))
        height += row_h + label_h
    out = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(out)
    d.text((16, 16), title, fill=INK, font=font(30))
    y = 70
    for loaded, row_h in imgs:
        for im, label, x in loaded:
            d.text((x + 10, y + 4), label, fill=INK, font=font(20))
            out.paste(im, (x, y + label_h))
        y += row_h + label_h
    path = os.path.join(REN, name)
    out.save(path)
    print("SHEET", path, out.size)


def main():
    sheet("sheet_base.png", "WESTBRIDGE - character base mesh (Blender)", [
        [("view_front.png", "Front", 1), ("view_right.png", "Side", 1), ("view_back.png", "Back", 1), ("view_sizes.png", "Sizes", 1)],
        [("face_closeup.png", "Face", 2), ("size_compare.png", "Size comparison", 2)],
        [("base_mesh_variants.png", "Base mesh + shape keys", 4)],
    ], 480)
    outfits = ["casual", "gardener", "photographer", "officer", "surfer", "designer", "student", "manager"]
    sheet("sheet_outfits.png", "WESTBRIDGE - outfit pack (original designs)", [
        [("outfit_%s.png" % o, o.capitalize(), 1) for o in outfits[:4]],
        [("outfit_%s.png" % o, o.capitalize(), 1) for o in outfits[4:]],
    ], 480)
    styles = sorted(f[6:-4] for f in os.listdir(REN) if f.startswith("style_") and f.endswith(".png"))
    rows = [[("style_%s.png" % s, s, 1) for s in styles[i:i + 4]] for i in range(0, len(styles), 4)]
    sheet("sheet_styles.png", "WESTBRIDGE - hair, facial hair and hats", rows, 310)


if __name__ == "__main__":
    main()
