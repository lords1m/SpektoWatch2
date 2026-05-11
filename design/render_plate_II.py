#!/usr/bin/env python3
"""
SPEKTRALGRUND — Plate II
Liquid Glass interpretation of the SpektoWatch identity.

The Spektralgrund philosophy survives the medium: chromatic restraint,
calibrated typography, the architecture of frequency × time. But the
matter changes — opaque ink becomes refractive crystal. Glass holds
light the way the noise floor holds silence: as a ground for signal.

Output:  spektowatch_plate_II.pdf
         spektowatch_plate_II.png
"""
from __future__ import annotations
import os
import glob
import math
import numpy as np
from PIL import (
    Image, ImageDraw, ImageFilter, ImageFont, ImageChops, ImageEnhance
)
from scipy.ndimage import gaussian_filter

# ─── canvas ─────────────────────────────────────────────────────────────────
W, H = 1800, 2400  # 3:4 portrait, matches Plate I

# ─── fonts ──────────────────────────────────────────────────────────────────
FONT_DIR = "/sessions/bold-beautiful-bardeen/mnt/.claude/skills/canvas-design/canvas-fonts"

def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    path = os.path.join(FONT_DIR, name)
    return ImageFont.truetype(path, size)

# ─── palette (echoing Plate I) ──────────────────────────────────────────────
PAPER       = (10, 17, 24)       # deep midnight ground
INK         = (229, 223, 210)    # pale calibration bone
INK_DIM     = (154, 150, 142)
INK_FAINT   = (110, 108, 102)
INK_GHOST   = (62, 65, 72)
RULE        = (90, 96, 105)
ACCENT_WARM = (220, 145, 72)
ACCENT_COOL = (95, 192, 198)
RECORD_RED  = (208, 76, 78)

SPEKTRAL_STOPS = [
    (0.000, (10, 17, 24)),
    (0.060, (13, 23, 34)),
    (0.140, (17, 35, 58)),
    (0.260, (23, 57, 97)),
    (0.380, (32, 95, 132)),
    (0.500, (51, 134, 154)),
    (0.620, (93, 160, 154)),
    (0.730, (168, 176, 122)),
    (0.820, (216, 184, 90)),
    (0.890, (221, 145, 72)),
    (0.950, (184, 82, 64)),
    (1.000, (122, 34, 41)),
]

def cmap_lookup(values: np.ndarray) -> np.ndarray:
    """Map [0..1] floats → RGB (uint8) using Spektralgrund stops."""
    xs = np.array([s[0] for s in SPEKTRAL_STOPS])
    rs = np.array([s[1][0] for s in SPEKTRAL_STOPS])
    gs = np.array([s[1][1] for s in SPEKTRAL_STOPS])
    bs = np.array([s[1][2] for s in SPEKTRAL_STOPS])
    v = np.clip(values, 0, 1)
    r = np.interp(v, xs, rs)
    g = np.interp(v, xs, gs)
    b = np.interp(v, xs, bs)
    return np.stack([r, g, b], axis=-1).astype(np.uint8)


# ─── chromatic luminous background ──────────────────────────────────────────
def make_background() -> Image.Image:
    """Deep navy ground with soft chromatic light blobs."""
    yy, xx = np.indices((H, W))

    def blob(xc, yc, sigma, color, strength=1.0):
        d = np.exp(-((xx - xc) ** 2 + (yy - yc) ** 2) / (2 * sigma ** 2))
        return d[..., None] * (np.array(color) * strength)

    bg = np.full((H, W, 3), [10, 17, 24], dtype=float)

    # warm aurora — top-right quadrant
    bg += blob(W * 0.82, H * 0.18, 760, [180, 95, 55], strength=1.05)
    bg += blob(W * 0.72, H * 0.10, 460, [205, 165, 70], strength=0.45)

    # cool aurora — lower-left
    bg += blob(W * 0.18, H * 0.62, 820, [25, 105, 145], strength=1.10)
    bg += blob(W * 0.05, H * 0.80, 600, [40, 130, 150], strength=0.55)

    # mid magenta-blue glow
    bg += blob(W * 0.50, H * 0.50, 900, [60, 70, 110], strength=0.55)

    # subtle vignette (darkens corners)
    cx, cy = W / 2, H / 2
    rad = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    vignette = np.clip(1 - (rad / (W * 0.85)) ** 2, 0, 1)
    bg *= (0.55 + 0.45 * vignette)[..., None]

    # gentle film grain
    rng = np.random.RandomState(7)
    grain = rng.randn(H, W) * 2.4
    bg += grain[..., None]

    bg = np.clip(bg, 0, 255).astype(np.uint8)
    return Image.fromarray(bg, "RGB")


# ─── synthesised spectrogram (smaller, for screens) ─────────────────────────
def synth_spectrogram(N_F=320, N_T=720, seed=11):
    f_min, f_max = 20.0, 20_000.0
    log_f = np.logspace(np.log10(f_min), np.log10(f_max), N_F)
    t = np.linspace(0.0, 60.0, N_T)
    rng = np.random.RandomState(seed)

    data = -94.0 + rng.randn(N_F, N_T) * 1.2
    slope = -0.18 * np.log10(np.maximum(log_f, 20) / 100.0) * 8.0
    data += slope[:, None]
    data = np.clip(data, -98, 0)

    def f_to_row(f): return int(np.argmin(np.abs(log_f - f)))
    def gauss(x, c, w): return np.exp(-((x - c) ** 2) / (2 * w ** 2))

    def add_harm(f0, env, base, n=12, fall=0.78, w=2, vib=0.0):
        for h in range(1, n + 1):
            fb = f0 * h
            if fb > f_max: break
            wr = max(1, w - h // 6)
            amp = base + 20 * np.log10(fall) * (h - 1)
            for ti in range(N_T):
                f = fb * (1 + vib * 0.001 * np.sin(2 * np.pi * 3 * t[ti] / 60))
                row = f_to_row(f)
                e = env[ti]
                if e < 1e-4: continue
                cc = amp + 20 * np.log10(e)
                for di in range(-wr, wr + 1):
                    r = row + di
                    if 0 <= r < N_F:
                        falloff = np.exp(-(di ** 2) / (max(1, wr) ** 2 * 0.95))
                        v = cc + 20 * np.log10(max(falloff, 1e-6))
                        if v > data[r, ti]:
                            data[r, ti] = v

    e1 = 0.85 * gauss(t, 14, 6.5) + 0.70 * gauss(t, 32, 7.5) + 0.55 * gauss(t, 49, 5.5)
    e1 = np.clip(e1, 0, 1)
    add_harm(110.0, e1, -22, n=14, fall=0.74, w=3, vib=2.0)

    e2 = 0.72 * gauss(t, 38, 5.2) + 0.50 * gauss(t, 47, 4.5)
    e2 = np.clip(e2, 0, 1)
    add_harm(164.81, e2, -26, n=10, fall=0.70, w=2, vib=2.5)

    e3 = 0.62 * gauss(t, 22, 2.6)
    add_harm(440.0, e3, -30, n=6, fall=0.65, w=2)

    e4 = 0.58 * gauss(t, 27, 1.4)
    add_harm(2637.0, e4, -34, n=2, fall=0.55, w=1)

    for f in [32, 40, 50]:
        row = f_to_row(f)
        for di in range(-2, 3):
            r = row + di
            if 0 <= r < N_F:
                data[r, :] = np.maximum(data[r, :], -57 + 4 * np.exp(-(di**2)/4.5))

    for tc, dur, lvl in [(8.7, 0.10, -42), (24.1, 0.06, -38), (43.6, 0.12, -45)]:
        ti0 = int(tc / 60 * N_T)
        ti1 = int((tc + dur) / 60 * N_T)
        roll = np.linspace(0, -8, N_F)
        data[:, ti0:ti1] = np.maximum(data[:, ti0:ti1], (lvl + roll)[:, None])

    s0, s1, f0_, f1_ = 4.0, 9.0, 600.0, 4500.0
    for ti in range(N_T):
        tt = t[ti]
        if s0 <= tt <= s1:
            ff = f0_ * (f1_ / f0_) ** ((tt - s0) / (s1 - s0))
            r = f_to_row(ff)
            for di in range(-3, 4):
                rr = r + di
                if 0 <= rr < N_F:
                    data[rr, ti] = max(data[rr, ti],
                                       -28 + 6 * np.exp(-(di**2)/3.6))

    data = gaussian_filter(data, sigma=(0.55, 1.4))
    return data


def render_spectrogram(width: int, height: int) -> Image.Image:
    data = synth_spectrogram(N_F=320, N_T=720)
    norm = np.clip((data + 96.0) / 96.0, 0, 1)
    rgb = cmap_lookup(norm)
    img = Image.fromarray(rgb, "RGB").resize((width, height), Image.Resampling.LANCZOS)
    return img


# ─── liquid glass primitive ─────────────────────────────────────────────────
def liquid_glass_card(canvas: Image.Image, x: int, y: int, w: int, h: int,
                      radius: int = 36, blur: int = 38,
                      tint: tuple = (255, 255, 255, 18),
                      edge_alpha: int = 90,
                      inner_glow: int = 60,
                      drop_shadow: bool = True,
                      shadow_blur: int = 50,
                      shadow_alpha: int = 120) -> None:
    """Render a frosted-glass card in place on canvas (RGBA, mutates).

    Uses backdrop blur, subtle tint, top-edge specular, and soft drop shadow.
    """
    if canvas.mode != "RGBA":
        raise ValueError("canvas must be RGBA")

    # ── drop shadow first
    if drop_shadow:
        sh = Image.new("RGBA", (w + 4 * shadow_blur, h + 4 * shadow_blur), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            (2 * shadow_blur, 2 * shadow_blur,
             2 * shadow_blur + w, 2 * shadow_blur + h),
            radius=radius, fill=(0, 0, 0, shadow_alpha),
        )
        sh = sh.filter(ImageFilter.GaussianBlur(radius=shadow_blur))
        canvas.alpha_composite(
            sh,
            dest=(x - 2 * shadow_blur, y - 2 * shadow_blur + 14),
        )

    # ── crop the underlying region (after shadow has darkened it)
    region = canvas.crop((x, y, x + w, y + h)).convert("RGBA")
    blurred = region.filter(ImageFilter.GaussianBlur(radius=blur))
    # boost saturation slightly for the glass colour bleed
    enh = ImageEnhance.Color(blurred.convert("RGB"))
    blurred = enh.enhance(1.15).convert("RGBA")
    # gentle brightness lift
    enh2 = ImageEnhance.Brightness(blurred.convert("RGB"))
    blurred = enh2.enhance(1.04).convert("RGBA")

    # tint overlay
    tint_layer = Image.new("RGBA", (w, h), tint)
    blurred.alpha_composite(tint_layer)

    # rounded mask
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w, h), radius=radius, fill=255)

    # inner specular gradient — bright at top, fading down (~ liquid lens)
    if inner_glow > 0:
        spec = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        sd = ImageDraw.Draw(spec)
        for i in range(int(h * 0.55)):
            a = int(inner_glow * (1 - i / (h * 0.55)) ** 2)
            sd.line([(0, i), (w, i)], fill=(255, 255, 255, a))
        spec.putalpha(ImageChops.multiply(spec.split()[3], mask))
        blurred.alpha_composite(spec)

    # Composite blurred glass back into canvas at (x,y)
    glass_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    glass_layer.paste(blurred, (x, y), mask)
    canvas.alpha_composite(glass_layer)

    # edge highlight (top + left thin specular line)
    edge = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge)
    ed.rounded_rectangle(
        (x, y, x + w, y + h),
        radius=radius,
        outline=(255, 255, 255, edge_alpha),
        width=1,
    )
    # softer secondary border below
    ed.rounded_rectangle(
        (x + 1, y + 1, x + w - 1, y + h - 1),
        radius=radius - 1,
        outline=(255, 255, 255, max(0, edge_alpha - 60)),
        width=1,
    )
    canvas.alpha_composite(edge)

    # crisp top specular (very thin, only top arc)
    top_spec = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ts = ImageDraw.Draw(top_spec)
    # arc-ish top highlight
    ts.arc(
        (x + 2, y + 2, x + w - 2, y + h - 2),
        start=200, end=340,
        fill=(255, 255, 255, edge_alpha + 40),
        width=2,
    )
    top_spec_blur = top_spec.filter(ImageFilter.GaussianBlur(0.6))
    canvas.alpha_composite(top_spec_blur)


# ─── small helpers ──────────────────────────────────────────────────────────
def round_button(canvas: Image.Image, cx: int, cy: int, r: int,
                 fill=(255, 255, 255, 36), edge_alpha=110):
    """A circular liquid glass button."""
    w = h = r * 2
    x = cx - r
    y = cy - r
    liquid_glass_card(canvas, x, y, w, h,
                      radius=r, blur=22,
                      tint=fill,
                      edge_alpha=edge_alpha,
                      inner_glow=70,
                      drop_shadow=True,
                      shadow_blur=18, shadow_alpha=70)


def text_anchor(draw, xy, text, font, fill, anchor="lt"):
    draw.text(xy, text, font=font, fill=fill, anchor=anchor)


# ─── iPhone mockup ──────────────────────────────────────────────────────────
def build_iphone_panel(spectrogram_img: Image.Image) -> Image.Image:
    """Build the iPhone display content (just the screen contents, RGBA)."""
    SW, SH = 660, 1430
    screen = Image.new("RGBA", (SW, SH), (8, 12, 18, 255))

    # Soft chromatic gradient inside screen (subtle)
    yy, xx = np.indices((SH, SW))
    base = np.full((SH, SW, 3), [8, 12, 18], dtype=float)
    base += np.exp(-((xx - SW * 0.2) ** 2 + (yy - SH * 0.7) ** 2) / (2 * 380 ** 2))[..., None] * np.array([10, 60, 110]) * 0.65
    base += np.exp(-((xx - SW * 0.85) ** 2 + (yy - SH * 0.25) ** 2) / (2 * 320 ** 2))[..., None] * np.array([170, 90, 50]) * 0.5
    base = np.clip(base, 0, 255).astype(np.uint8)
    screen = Image.fromarray(base, "RGB").convert("RGBA")

    draw = ImageDraw.Draw(screen)

    # ── status bar
    f_status = font("InstrumentSans-Bold.ttf", 22)
    draw.text((40, 28), "9:41", font=f_status, fill=INK + (255,))
    # right indicators (small bars representing signal/wifi/battery)
    bar_x = SW - 130
    for i, h_bar in enumerate([6, 9, 12, 15]):
        draw.rounded_rectangle(
            (bar_x + i * 7, 50 - h_bar, bar_x + i * 7 + 5, 50),
            radius=1, fill=INK + (220,),
        )
    # wifi triangle
    wx, wy = SW - 92, 36
    draw.polygon([(wx, wy + 14), (wx + 22, wy + 14), (wx + 11, wy + 0)], fill=INK + (220,))
    # battery
    bx, by = SW - 64, 36
    draw.rounded_rectangle((bx, by, bx + 40, by + 18), radius=4, outline=INK + (220,), width=2)
    draw.rounded_rectangle((bx + 42, by + 5, bx + 46, by + 13), radius=1, fill=INK + (220,))
    draw.rounded_rectangle((bx + 3, by + 3, bx + 33, by + 15), radius=2, fill=INK + (240,))

    # ── dynamic island (just decorative, on top of status bar)
    di_w, di_h = 240, 44
    di_x = (SW - di_w) // 2
    di_y = 14
    draw.rounded_rectangle((di_x, di_y, di_x + di_w, di_y + di_h),
                           radius=22, fill=(0, 0, 0, 255))

    # ── header card (small, doesn't compete with page title)
    f_inner_label = font("InstrumentSans-Bold.ttf", 18)
    f_subtle = font("InstrumentSerif-Italic.ttf", 22)
    draw.text((SW // 2, 110), "·   D A S H B O A R D   ·",
              font=f_inner_label, fill=INK + (220,), anchor="mt")
    draw.text((SW // 2, 152), "live spectral observation",
              font=f_subtle, fill=INK_DIM + (240,), anchor="mt")
    # thin rule under header
    draw.line((SW * 0.30, 200, SW * 0.70, 200), fill=RULE + (180,), width=1)

    # ── main spectrogram zone (full bleed within margins)
    spec_x, spec_y = 28, 244
    spec_w, spec_h = SW - 56, 600
    spec_resized = spectrogram_img.resize((spec_w, spec_h), Image.Resampling.LANCZOS)
    # rounded mask for spectrogram
    spec_mask = Image.new("L", (spec_w, spec_h), 0)
    ImageDraw.Draw(spec_mask).rounded_rectangle((0, 0, spec_w, spec_h), radius=28, fill=255)
    screen.paste(spec_resized, (spec_x, spec_y), spec_mask)
    # subtle border on spectrogram
    draw = ImageDraw.Draw(screen)
    draw.rounded_rectangle((spec_x, spec_y, spec_x + spec_w, spec_y + spec_h),
                           radius=28, outline=(255, 255, 255, 50), width=1)

    # ── frequency axis labels (tiny, on right edge of spectrogram)
    f_mono_xs = font("DMMono-Regular.ttf", 14)
    f_labels = [(20, "20"), (200, "200"), (2_000, "2 k"), (20_000, "20 k")]
    log_min, log_max = np.log10(20), np.log10(20_000)
    for f_, lbl in f_labels:
        yn = (np.log10(f_) - log_min) / (log_max - log_min)
        ypix = spec_y + spec_h - int(yn * spec_h)
        draw.text((spec_x + spec_w - 12, ypix), lbl,
                  font=f_mono_xs, fill=INK_DIM + (200,), anchor="rm")

    # tiny "Hz" label top-right of spectrogram
    draw.text((spec_x + spec_w - 12, spec_y + 16), "Hz",
              font=f_mono_xs, fill=INK_FAINT + (220,), anchor="rt")

    # tiny live indicator
    f_mono_tiny = font("DMMono-Regular.ttf", 13)
    draw.ellipse((spec_x + 18, spec_y + 18, spec_x + 28, spec_y + 28),
                 fill=RECORD_RED + (255,))
    draw.text((spec_x + 36, spec_y + 22), "LIVE  ·  48 kHz",
              font=f_mono_tiny, fill=INK + (220,), anchor="lm")

    return screen.convert("RGBA")


def overlay_iphone_glass_panels(screen: Image.Image) -> None:
    """Place liquid-glass HUD panels on top of the iPhone screen content."""
    SW, SH = screen.size

    # Big LAEQ readout — glass card overlaid lower middle
    card_w, card_h = SW - 80, 200
    card_x, card_y = 40, 880
    liquid_glass_card(screen, card_x, card_y, card_w, card_h,
                      radius=34, blur=30,
                      tint=(255, 255, 255, 22),
                      edge_alpha=110, inner_glow=70,
                      drop_shadow=True, shadow_blur=42, shadow_alpha=110)

    d = ImageDraw.Draw(screen)
    f_huge = font("Italiana-Regular.ttf", 110)
    f_unit = font("InstrumentSerif-Italic.ttf", 30)
    f_label = font("InstrumentSans-Bold.ttf", 16)
    f_sub = font("DMMono-Regular.ttf", 16)

    # Label top-left
    d.text((card_x + 28, card_y + 22), "LAEQ   ·   60 s",
           font=f_label, fill=INK + (220,), anchor="lt")
    d.text((card_x + card_w - 28, card_y + 22), "A-WEIGHTED",
           font=f_label, fill=INK_DIM + (220,), anchor="rt")

    # huge number
    d.text((card_x + 32, card_y + 168), "82.4",
           font=f_huge, fill=INK + (255,), anchor="ls")
    d.text((card_x + 280, card_y + 158), "dB(A)",
           font=f_unit, fill=INK_DIM + (255,), anchor="ls")

    # right side mini values
    d.text((card_x + card_w - 28, card_y + 78), "max",
           font=f_sub, fill=INK_FAINT + (220,), anchor="rt")
    f_med = font("Italiana-Regular.ttf", 42)
    d.text((card_x + card_w - 28, card_y + 100), "94.1",
           font=f_med, fill=INK + (240,), anchor="rt")
    d.text((card_x + card_w - 28, card_y + 152), "min",
           font=f_sub, fill=INK_FAINT + (220,), anchor="rt")
    d.text((card_x + card_w - 28, card_y + 174), "61.7",
           font=f_med, fill=INK + (240,), anchor="rt")

    # ── thin info card — frequency cursor
    info_w, info_h = SW - 80, 76
    info_x, info_y = 40, 1100
    liquid_glass_card(screen, info_x, info_y, info_w, info_h,
                      radius=24, blur=24,
                      tint=(255, 255, 255, 18),
                      edge_alpha=100, inner_glow=50,
                      drop_shadow=True, shadow_blur=30, shadow_alpha=80)
    d = ImageDraw.Draw(screen)
    f_mono_lbl = font("DMMono-Regular.ttf", 17)
    f_mono_val = font("DMMono-Regular.ttf", 21)
    d.text((info_x + 26, info_y + info_h // 2), "f   440.0 Hz",
           font=f_mono_val, fill=INK + (240,), anchor="lm")
    d.text((info_x + 320, info_y + info_h // 2), "−28.4 dB",
           font=f_mono_val, fill=INK + (240,), anchor="lm")
    d.text((info_x + info_w - 26, info_y + info_h // 2), "A 4    fundamental",
           font=f_mono_lbl, fill=INK_DIM + (220,), anchor="rm")

    # ── bottom control bar — round glass buttons
    bar_y = 1240
    btn_centers = [
        (SW * 0.16, bar_y, 36, "settings"),
        (SW * 0.32, bar_y, 36, "freeze"),
        (SW * 0.50, bar_y, 56, "record"),  # main record
        (SW * 0.68, bar_y, 36, "marker"),
        (SW * 0.84, bar_y, 36, "share"),
    ]
    for cx, cy, r, kind in btn_centers:
        if kind == "record":
            round_button(screen, int(cx), int(cy), r,
                         fill=(255, 255, 255, 30),
                         edge_alpha=130)
            # red record dot
            rd = ImageDraw.Draw(screen)
            rd.ellipse((cx - 18, cy - 18, cx + 18, cy + 18),
                       fill=RECORD_RED + (255,))
        else:
            round_button(screen, int(cx), int(cy), r,
                         fill=(255, 255, 255, 22),
                         edge_alpha=95)

    # tiny glyphs on each button (using simple shapes)
    d = ImageDraw.Draw(screen)
    glyph_color = INK + (235,)

    # settings — three horizontal bars
    cx, cy = int(SW * 0.16), bar_y
    for i, off in enumerate([-9, 0, 9]):
        d.rectangle((cx - 12, cy + off - 1, cx + 12, cy + off + 1), fill=glyph_color)
        d.ellipse((cx - 4 + (i - 1) * 6, cy + off - 4, cx + 4 + (i - 1) * 6, cy + off + 4),
                  fill=glyph_color)

    # freeze — snowflake-ish
    cx, cy = int(SW * 0.32), bar_y
    for ang in range(0, 180, 60):
        rad = math.radians(ang)
        dx = math.cos(rad) * 12
        dy = math.sin(rad) * 12
        d.line((cx - dx, cy - dy, cx + dx, cy + dy), fill=glyph_color, width=2)

    # marker — triangle pin
    cx, cy = int(SW * 0.68), bar_y
    d.polygon([(cx, cy - 12), (cx - 9, cy + 6), (cx + 9, cy + 6)], outline=glyph_color, width=2)
    d.line((cx, cy + 6, cx, cy + 12), fill=glyph_color, width=2)

    # share — arrow up from box
    cx, cy = int(SW * 0.84), bar_y
    d.rectangle((cx - 10, cy + 2, cx + 10, cy + 12), outline=glyph_color, width=2)
    d.line((cx, cy + 2, cx, cy - 12), fill=glyph_color, width=2)
    d.line((cx, cy - 12, cx - 6, cy - 6), fill=glyph_color, width=2)
    d.line((cx, cy - 12, cx + 6, cy - 6), fill=glyph_color, width=2)

    # tiny labels under buttons
    f_btn = font("InstrumentSans-Regular.ttf", 11)
    labels = [
        (int(SW * 0.16), "SETTINGS"),
        (int(SW * 0.32), "FREEZE"),
        (int(SW * 0.50), "RECORD"),
        (int(SW * 0.68), "MARK"),
        (int(SW * 0.84), "SHARE"),
    ]
    for cx, lbl in labels:
        d.text((cx, bar_y + 70), lbl, font=f_btn, fill=INK_DIM + (220,), anchor="mt")

    # home indicator
    d.rounded_rectangle((SW // 2 - 70, SH - 16, SW // 2 + 70, SH - 10),
                        radius=3, fill=INK + (160,))


def build_iphone(spec_img: Image.Image) -> Image.Image:
    """Compose the full iPhone with body + screen + Liquid Glass UI."""
    screen = build_iphone_panel(spec_img)
    overlay_iphone_glass_panels(screen)

    SW, SH = screen.size
    # body wraps the screen with bezel + corner radius
    BEZEL = 14
    BODY_W = SW + 2 * BEZEL
    BODY_H = SH + 2 * BEZEL
    body = Image.new("RGBA", (BODY_W, BODY_H), (0, 0, 0, 0))

    bd = ImageDraw.Draw(body)
    # outer body (titanium dark)
    bd.rounded_rectangle((0, 0, BODY_W, BODY_H), radius=88, fill=(22, 26, 32, 255))
    # subtle metallic edge highlight
    bd.rounded_rectangle((1, 1, BODY_W - 1, BODY_H - 1), radius=87,
                         outline=(120, 130, 142, 220), width=2)
    # thin inner darkness
    bd.rounded_rectangle((BEZEL - 2, BEZEL - 2, BODY_W - BEZEL + 2, BODY_H - BEZEL + 2),
                         radius=78, fill=(0, 0, 0, 255))
    # Inner screen area
    inner_mask = Image.new("L", (SW, SH), 0)
    ImageDraw.Draw(inner_mask).rounded_rectangle((0, 0, SW, SH), radius=72, fill=255)
    body.paste(screen, (BEZEL, BEZEL), inner_mask)

    # Side button details
    bd = ImageDraw.Draw(body)
    # power button (right side)
    bd.rounded_rectangle((BODY_W - 4, 280, BODY_W, 380), radius=2, fill=(40, 44, 50, 255))
    # volume
    bd.rounded_rectangle((0, 240, 4, 290), radius=2, fill=(40, 44, 50, 255))
    bd.rounded_rectangle((0, 320, 4, 410), radius=2, fill=(40, 44, 50, 255))
    bd.rounded_rectangle((0, 200, 4, 220), radius=2, fill=(40, 44, 50, 255))  # mute switch

    return body


# ─── Apple Watch mockup ─────────────────────────────────────────────────────
def build_watch(spec_img: Image.Image) -> Image.Image:
    """Compose Apple Watch with screen content."""
    SW, SH = 380, 460
    # watch body
    body = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    # outer body
    bd.rounded_rectangle((0, 0, SW, SH), radius=84, fill=(20, 22, 28, 255))
    bd.rounded_rectangle((1, 1, SW - 1, SH - 1), radius=83,
                         outline=(120, 130, 142, 220), width=2)
    # screen area
    SCR_PAD = 22
    scr_w = SW - 2 * SCR_PAD
    scr_h = SH - 2 * SCR_PAD
    bd.rounded_rectangle((SCR_PAD - 4, SCR_PAD - 4,
                          SW - SCR_PAD + 4, SH - SCR_PAD + 4),
                         radius=66, fill=(0, 0, 0, 255))

    # screen content
    screen = Image.new("RGBA", (scr_w, scr_h), (8, 12, 18, 255))
    # mini spectrogram in background — softly visible
    mini_spec = spec_img.resize((scr_w, scr_h), Image.Resampling.LANCZOS)
    mini_spec = mini_spec.filter(ImageFilter.GaussianBlur(2.5))
    # darken
    enh = ImageEnhance.Brightness(mini_spec)
    mini_spec = enh.enhance(0.55).convert("RGBA")
    # round mask
    sm = Image.new("L", (scr_w, scr_h), 0)
    ImageDraw.Draw(sm).rounded_rectangle((0, 0, scr_w, scr_h), radius=58, fill=255)
    screen.paste(mini_spec, (0, 0), sm)

    # Dark gradient overlay (so the number is readable)
    grad = Image.new("RGBA", (scr_w, scr_h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for i in range(scr_h):
        a = int(150 * (1 - abs(i - scr_h / 2) / (scr_h / 2)) ** 1.4)
        gd.line([(0, i), (scr_w, i)], fill=(8, 14, 22, a))
    screen.alpha_composite(grad)

    sd = ImageDraw.Draw(screen)
    # top tiny label
    f_w_label = font("InstrumentSans-Bold.ttf", 17)
    sd.text((scr_w // 2, 24), "L A F   /   d B (A)",
            font=f_w_label, fill=INK_DIM + (240,), anchor="mt")
    # huge number
    f_w_huge = font("Italiana-Regular.ttf", 138)
    sd.text((scr_w // 2, scr_h // 2 + 22), "82",
            font=f_w_huge, fill=INK + (255,), anchor="mm")
    # decimal
    f_w_dec = font("Italiana-Regular.ttf", 56)
    sd.text((scr_w // 2 + 92, scr_h // 2 + 8), ".4",
            font=f_w_dec, fill=INK_DIM + (240,), anchor="lm")
    # bottom small reading (peak)
    f_w_mini = font("DMMono-Regular.ttf", 16)
    sd.text((scr_w // 2, scr_h - 50), "peak  94.1   ·   live",
            font=f_w_mini, fill=INK_DIM + (220,), anchor="mt")

    # Liquid glass mini card around the number
    liquid_glass_card(screen,
                      x=int(scr_w * 0.10), y=int(scr_h * 0.30),
                      w=int(scr_w * 0.80), h=int(scr_h * 0.45),
                      radius=42, blur=18,
                      tint=(255, 255, 255, 14),
                      edge_alpha=80, inner_glow=40,
                      drop_shadow=False)
    # restate the number on top of the glass
    sd = ImageDraw.Draw(screen)
    sd.text((scr_w // 2, scr_h // 2 + 22), "82",
            font=f_w_huge, fill=INK + (255,), anchor="mm")
    sd.text((scr_w // 2 + 92, scr_h // 2 + 8), ".4",
            font=f_w_dec, fill=INK_DIM + (240,), anchor="lm")

    body.paste(screen, (SCR_PAD, SCR_PAD), sm)

    # Crown
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle((SW - 4, SH // 2 - 28, SW + 12, SH // 2 + 28),
                         radius=4, fill=(95, 100, 108, 255))
    # crown center detail
    bd.line((SW + 2, SH // 2 - 22, SW + 2, SH // 2 + 22),
            fill=(160, 170, 180, 240), width=1)
    # side button
    bd.rounded_rectangle((SW - 2, SH // 2 + 50, SW + 6, SH // 2 + 110),
                         radius=2, fill=(60, 65, 72, 255))

    # tiny strap hints — top and bottom
    bd.rectangle((40, -10, SW - 40, 0), fill=(30, 32, 40, 255))
    bd.rectangle((40, SH, SW - 40, SH + 10), fill=(30, 32, 40, 255))

    return body


# ─── compose master canvas ──────────────────────────────────────────────────
def compose(out_pdf: str, out_png: str):
    canvas = make_background().convert("RGBA")
    spec_img = render_spectrogram(900, 1700)

    # iPhone — scaled to fit cleanly below title
    iphone = build_iphone(spec_img)
    # scale down a touch
    target_w = int(iphone.size[0] * 0.86)
    target_h = int(iphone.size[1] * 0.86)
    iphone = iphone.resize((target_w, target_h), Image.Resampling.LANCZOS)
    iphone_rot = iphone.rotate(-3.5, resample=Image.Resampling.BICUBIC, expand=True)
    # drop shadow underneath the phone
    sh = Image.new("RGBA", iphone_rot.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        (10, 30, iphone_rot.size[0] - 10, iphone_rot.size[1] - 10),
        radius=110, fill=(0, 0, 0, 200),
    )
    sh = sh.filter(ImageFilter.GaussianBlur(85))
    PHONE_X, PHONE_Y = 320, 600
    canvas.alpha_composite(sh, dest=(PHONE_X - 30, PHONE_Y + 50))
    canvas.alpha_composite(iphone_rot, dest=(PHONE_X, PHONE_Y))

    # Watch — slightly larger
    watch = build_watch(spec_img)
    watch = watch.resize((int(watch.size[0] * 1.05), int(watch.size[1] * 1.05)),
                         Image.Resampling.LANCZOS)
    watch_rot = watch.rotate(7, resample=Image.Resampling.BICUBIC, expand=True)
    sh2 = Image.new("RGBA", watch_rot.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh2).rounded_rectangle(
        (10, 30, watch_rot.size[0] - 10, watch_rot.size[1] - 10),
        radius=80, fill=(0, 0, 0, 200),
    )
    sh2 = sh2.filter(ImageFilter.GaussianBlur(60))
    WATCH_X, WATCH_Y = 1200, 1430
    canvas.alpha_composite(sh2, dest=(WATCH_X - 30, WATCH_Y + 30))
    canvas.alpha_composite(watch_rot, dest=(WATCH_X, WATCH_Y))

    # ── header text (top of page)
    d = ImageDraw.Draw(canvas)
    # frame ticks
    for cx, cy in [(110, 110), (W - 110, 110), (110, H - 110), (W - 110, H - 110)]:
        d.line((cx - 18, cy, cx + 18, cy), fill=INK_DIM + (200,), width=2)
        d.line((cx, cy - 18, cx, cy + 18), fill=INK_DIM + (200,), width=2)

    # ── top strip (consistent with Plate I)
    f_disp = font("Boldonse-Regular.ttf", 22)
    f_sans_sm = font("InstrumentSans-Regular.ttf", 16)
    f_mono_sm = font("DMMono-Regular.ttf", 16)
    d.text((140, 156), "II", font=f_disp, fill=INK + (240,), anchor="lt")
    d.text((188, 162), "TAFEL  SECUNDA", font=f_sans_sm, fill=INK_DIM + (240,), anchor="lt")
    # rule
    d.line((W // 2 - 200, 168, W // 2 + 200, 168), fill=RULE + (200,), width=1)
    d.line((W // 2 - 12, 162, W // 2 - 12, 174), fill=INK_DIM + (200,), width=1)
    d.line((W // 2 + 12, 162, W // 2 + 12, 174), fill=INK_DIM + (200,), width=1)
    d.text((W - 140, 162), "MMXXVI    EDITION  I", font=f_mono_sm, fill=INK_DIM + (240,), anchor="rt")

    # title block
    f_title = font("Italiana-Regular.ttf", 168)
    d.text((W // 2, 240), "SPEKTRALGRUND", font=f_title, fill=INK + (255,), anchor="mt")
    f_subtitle = font("InstrumentSerif-Italic.ttf", 34)
    d.text((W // 2, 410), "instrument · ii · liquid glass",
           font=f_subtitle, fill=INK_DIM + (255,), anchor="mt")
    # tracked subtitle
    f_track = font("InstrumentSans-Regular.ttf", 18)
    d.text((W // 2, 458), "·   S P E K T O · W A T C H   ·",
           font=f_track, fill=INK_FAINT + (240,), anchor="mt")

    # ── caption / footer (bottom)
    Y_BOT_RULE = H - 280
    d.line((140, Y_BOT_RULE, W - 140, Y_BOT_RULE), fill=RULE + (200,), width=1)

    # caption italic
    f_cap = font("InstrumentSerif-Italic.ttf", 26)
    d.text((150, Y_BOT_RULE + 28), "fig. II",
           font=f_cap, fill=INK + (240,), anchor="lt")
    d.text((260, Y_BOT_RULE + 28),
           "The same field, refracted — chromatic energy held inside translucent",
           font=f_cap, fill=INK_DIM + (240,), anchor="lt")
    d.text((260, Y_BOT_RULE + 64),
           "matter; signal transmitted through layered light.",
           font=f_cap, fill=INK_DIM + (240,), anchor="lt")

    # 3 columns
    f_col_h = font("InstrumentSans-Bold.ttf", 16)
    f_col_b = font("DMMono-Regular.ttf", 17)
    f_col_s = font("DMMono-Regular.ttf", 15)

    col_x = [W * 0.27, W * 0.50, W * 0.73]
    Y_COL_HEAD = Y_BOT_RULE + 130
    headers = ["MATERIAL", "INTERFACE", "PLATFORM"]
    bodies = [
        ("translucent crystal", "frosted refraction"),
        ("dB(A)   ·   FFT 8192", "60-fps live render"),
        ("iPhone   ·   watchOS", "S B    /    no. 0001"),
    ]
    for cx, head, (b1, b2) in zip(col_x, headers, bodies):
        d.text((cx, Y_COL_HEAD), head, font=f_col_h, fill=INK + (250,), anchor="mt")
        d.line((cx - 100, Y_COL_HEAD + 30, cx + 100, Y_COL_HEAD + 30),
               fill=RULE + (200,), width=1)
        d.text((cx, Y_COL_HEAD + 44), b1, font=f_col_b, fill=INK_DIM + (240,), anchor="mt")
        d.text((cx, Y_COL_HEAD + 70), b2, font=f_col_s, fill=INK_FAINT + (220,), anchor="mt")

    # Wordmark stripe at very bottom
    Y_STRIPE_RULE = H - 130
    d.line((140, Y_STRIPE_RULE, W - 140, Y_STRIPE_RULE), fill=RULE + (200,), width=1)
    f_word = font("InstrumentSans-Bold.ttf", 22)
    d.text((W // 2, Y_STRIPE_RULE + 26),
           "S  P  E  K  T  O      W  A  T  C  H",
           font=f_word, fill=INK + (255,), anchor="mt")
    f_tag = font("InstrumentSerif-Italic.ttf", 18)
    d.text((W // 2, Y_STRIPE_RULE + 64),
           "instrument for the acoustic field",
           font=f_tag, fill=INK_DIM + (240,), anchor="mt")

    # left corner: edition
    f_corner = font("DMMono-Regular.ttf", 14)
    d.text((150, Y_STRIPE_RULE + 32), "·  M M X X V I",
           font=f_corner, fill=INK_FAINT + (220,), anchor="lt")
    d.text((150, Y_STRIPE_RULE + 60), "audible field",
           font=f_corner, fill=INK_GHOST + (220,), anchor="lt")
    # right corner: maker
    d.text((W - 150, Y_STRIPE_RULE + 32), "S B    no. 0001",
           font=f_corner, fill=INK_FAINT + (220,), anchor="rt")
    d.text((W - 150, Y_STRIPE_RULE + 60), "atlas ii.",
           font=f_corner, fill=INK_GHOST + (220,), anchor="rt")

    # (device labels removed — composition is cleaner without them;
    #  the figures speak for themselves and the footer columns provide
    #  the platform information)

    # ── frame outline
    d.rectangle((110, 110, W - 110, H - 110), outline=RULE + (180,), width=1)

    # ── save
    out_rgb = canvas.convert("RGB")
    out_rgb.save(out_png, "PNG", dpi=(300, 300), optimize=True)
    out_rgb.save(out_pdf, "PDF", resolution=300.0)
    print(f"Wrote {out_png}")
    print(f"Wrote {out_pdf}")


if __name__ == "__main__":
    out_dir = "/sessions/bold-beautiful-bardeen/mnt/SpektoWatch2/design"
    os.makedirs(out_dir, exist_ok=True)
    compose(
        out_pdf=os.path.join(out_dir, "spektowatch_plate_II.pdf"),
        out_png=os.path.join(out_dir, "spektowatch_plate_II.png"),
    )
