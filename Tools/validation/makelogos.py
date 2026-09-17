from PIL import Image, ImageDraw, ImageFont
import numpy as np

def bold_glyph(size=512):
    im = Image.new("L", (size, size), 255)
    d = ImageDraw.Draw(im)
    m = size*0.08
    d.ellipse([m, m, size-m, size-m], fill=0)
    d.ellipse([size*0.30, size*0.20, size*0.95, size*0.62], fill=255)   # a crescent-ish mark
    return im

def block_letter(size=512, ch="A"):
    im = Image.new("L", (size, size), 255)
    d = ImageDraw.Draw(im)
    try:
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", int(size*0.85))
    except Exception:
        f = ImageFont.load_default()
    bbox = d.textbbox((0,0), ch, font=f)
    d.text(((size-(bbox[2]-bbox[0]))/2 - bbox[0], (size-(bbox[3]-bbox[1]))/2 - bbox[1]), ch, font=f, fill=0)
    return im

def thin_wordmark(size=512, text="markscout"):
    im = Image.new("L", (size, size), 255)
    d = ImageDraw.Draw(im)
    try:
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", int(size*0.13))
    except Exception:
        f = ImageFont.load_default()
    bbox = d.textbbox((0,0), text, font=f)
    d.text(((size-(bbox[2]-bbox[0]))/2 - bbox[0], (size-(bbox[3]-bbox[1]))/2 - bbox[1]), text, font=f, fill=0)
    return im

def detailed(size=512):
    rng = np.random.default_rng(3)
    a = rng.random((size//8, size//8))
    im = Image.fromarray((a*255).astype(np.uint8)).resize((size,size), Image.BICUBIC)
    return im

def solid_square(size=512):
    im = Image.new("L", (size, size), 255)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([size*0.12, size*0.12, size*0.88, size*0.88], radius=size*0.18, fill=0)
    return im

LOGOS = {"bold_glyph": bold_glyph(), "letter_A": block_letter(), "thin_wordmark": thin_wordmark(),
         "detailed": detailed(), "solid_square": solid_square()}
if __name__ == "__main__":
    for k, v in LOGOS.items():
        v.save(f"logo_{k}.png")
    print("saved", list(LOGOS))
