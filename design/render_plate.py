#!/usr/bin/env python3
"""
SPEKTRALGRUND — Plate I of the Atlas of the Audible Field
A canvas expressing the SpektoWatch design philosophy.

Output:  spektowatch_plate_I.pdf  (vector)
         spektowatch_plate_I.png  (300-dpi preview)

Conceptual notes
----------------
The piece treats sixty seconds of acoustic observation as a single chromatic
landscape. The composition descends — invisibly — from Ernst Chladni's 1787
plates: the first visualisations of sound. Its restraint, axes, and
calibration marks are the language of scientific observation; its colour
restraint is the language of careful measurement.
"""
from __future__ import annotations

import glob
import os
import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.patches import Rectangle
from scipy.ndimage import gaussian_filter

# ─── fonts ──────────────────────────────────────────────────────────────────
FONT_DIR = "/sessions/bold-beautiful-bardeen/mnt/.claude/skills/canvas-design/canvas-fonts"
for f in glob.glob(os.path.join(FONT_DIR, "*.ttf")):
    try:
        fm.fontManager.addfont(f)
    except Exception:
        pass


def _resolve(preferred: str, fallbacks: list[str]) -> str:
    available = {f.name for f in fm.fontManager.ttflist}
    for name in [preferred] + fallbacks:
        if name in available:
            return name
    return "DejaVu Sans"


F_TITLE   = _resolve("Italiana",          ["Gloock", "Young Serif"])
F_DISPLAY = _resolve("Boldonse",          ["Big Shoulders Display", "Tektur"])
F_SERIF_I = _resolve("Instrument Serif",  ["Lora", "Crimson Pro"])
F_SANS    = _resolve("Instrument Sans",   ["Work Sans", "Outfit"])
F_MONO    = _resolve("DM Mono",           ["JetBrains Mono", "IBM Plex Mono"])

print(f"Fonts: {F_TITLE} | {F_DISPLAY} | {F_SERIF_I} | {F_SANS} | {F_MONO}")

# ─── palette ────────────────────────────────────────────────────────────────
PAPER     = "#0A1118"   # deep midnight ground (the noise floor)
INK       = "#E5DFD2"   # pale calibration bone
INK_DIM   = "#9A968E"   # dimmer text
INK_FAINT = "#5A5852"   # sub-text
INK_GHOST = "#3E4148"   # very faint
RULE      = "#3A3F47"
ACCENT    = "#C4B25E"   # warm calibration mark

# Custom colormap — perceptually layered, austere. Inspired by Turbo
# but reserved: the lower band is genuinely dark, the warm peaks are
# rare and earned.
SPEKTRAL_CMAP = LinearSegmentedColormap.from_list(
    "spektralgrund",
    [
        (0.000, "#0A1118"),
        (0.050, "#0D1722"),
        (0.130, "#11233A"),
        (0.260, "#173961"),
        (0.380, "#205F84"),
        (0.500, "#33869A"),
        (0.620, "#5DA09A"),
        (0.730, "#A8B07A"),
        (0.820, "#D8B85A"),
        (0.890, "#DD9148"),
        (0.950, "#B85240"),
        (1.000, "#7A2229"),
    ],
    N=2048,
)


# ─── synthesised spectrogram field ──────────────────────────────────────────
def synth_spectrogram(seed: int = 11):
    f_min, f_max = 20.0, 20_000.0
    N_F, N_T = 540, 1500
    log_f = np.logspace(np.log10(f_min), np.log10(f_max), N_F)
    t = np.linspace(0.0, 60.0, N_T)

    rng = np.random.RandomState(seed)
    data = -94.0 + rng.randn(N_F, N_T) * 1.2

    # subtle pink slope so lows have a touch more density
    slope_db = -0.18 * np.log10(np.maximum(log_f, 20) / 100.0)
    data += slope_db[:, None] * 8.0
    data = np.clip(data, -98, 0)

    def f_to_row(f):
        return int(np.argmin(np.abs(log_f - f)))

    def gauss(x, c, w):
        return np.exp(-((x - c) ** 2) / (2 * w ** 2))

    def add_harmonic(f0, env_t, base_db, n_harm=12, falloff=0.78,
                     width=2, vibrato=0.0, vib_rate=4.0,
                     micro_amp=1.5, micro_rate=2.7, seed_h=0):
        """Add a harmonic stack with subtle vibrato and per-frame micro-wobble."""
        rng_h = np.random.RandomState(73 + seed_h)
        # tiny, slow per-frame amplitude breath (independent random walk)
        wobble_phase = rng_h.uniform(0, 2 * np.pi)
        wobble = micro_amp * np.sin(2 * np.pi * micro_rate * t / 60 + wobble_phase)
        # add a touch of secondary modulation for organic feel
        wobble += 0.6 * micro_amp * np.sin(2 * np.pi * (micro_rate * 1.7) * t / 60 + wobble_phase * 0.6)

        for h in range(1, n_harm + 1):
            f_base = f0 * h
            if f_base > f_max:
                break
            row_w = max(1, width - h // 6)
            amp = base_db + 20 * np.log10(falloff) * (h - 1)
            # higher harmonics fluctuate slightly more
            harm_wobble = wobble * (1.0 + 0.15 * (h - 1))
            for ti in range(N_T):
                f = f_base * (1 + vibrato * 0.001 * np.sin(2 * np.pi * vib_rate * t[ti] / 60))
                row = f_to_row(f)
                e = env_t[ti]
                if e < 1e-4:
                    continue
                contrib_center = amp + 20 * np.log10(e) + harm_wobble[ti]
                for di in range(-row_w, row_w + 1):
                    r = row + di
                    if 0 <= r < N_F:
                        fall = np.exp(-(di ** 2) / (max(1, row_w) ** 2 * 0.95))
                        v = contrib_center + 20 * np.log10(max(fall, 1e-6))
                        if v > data[r, ti]:
                            data[r, ti] = v

    # Voice 1 — sustained low note A2 (110 Hz) with rich harmonics, breathing
    env1 = (
        0.85 * gauss(t, 14, 6.5)
        + 0.70 * gauss(t, 32, 7.5)
        + 0.55 * gauss(t, 49, 5.5)
    )
    env1 = np.clip(env1, 0, 1.0)
    add_harmonic(110.0, env1, base_db=-22, n_harm=14, falloff=0.74,
                 width=3, vibrato=2.0, vib_rate=3.0)

    # Voice 2 — perfect-fifth above (E3 ≈ 165 Hz), entering mid-piece
    env2 = 0.72 * gauss(t, 38, 5.2) + 0.50 * gauss(t, 47, 4.5)
    env2 = np.clip(env2, 0, 1.0)
    add_harmonic(164.81, env2, base_db=-26, n_harm=10, falloff=0.70,
                 width=2, vibrato=2.5, vib_rate=4.5)

    # Mid-register motif — held octave at A4 (440 Hz), brief
    env3 = 0.62 * gauss(t, 22, 2.6)
    add_harmonic(440.0, env3, base_db=-30, n_harm=6, falloff=0.65, width=2)

    # High accent — short bell tone around 2.6 kHz
    env4 = 0.58 * gauss(t, 27, 1.4)
    add_harmonic(2637.0, env4, base_db=-34, n_harm=2, falloff=0.55, width=1)

    # Rumble — sustained low band ~30-55 Hz
    for f in [32, 40, 50]:
        row = f_to_row(f)
        for di in range(-2, 3):
            r = row + di
            if 0 <= r < N_F:
                data[r, :] = np.maximum(
                    data[r, :], -57 + 4 * np.exp(-(di ** 2) / 4.5)
                )

    # Transients — sharp vertical events
    for tc, dur, lvl in [(8.7, 0.10, -42), (24.1, 0.06, -38), (43.6, 0.12, -45)]:
        ti0 = int(tc / 60 * N_T)
        ti1 = int((tc + dur) / 60 * N_T)
        roll = np.linspace(0, -8, N_F)
        data[:, ti0:ti1] = np.maximum(data[:, ti0:ti1], (lvl + roll)[:, None])

    # Ascending sweep 600 → 4500 Hz between 4-9 s
    s0, s1, f0_, f1_ = 4.0, 9.0, 600.0, 4500.0
    for ti in range(N_T):
        tt = t[ti]
        if s0 <= tt <= s1:
            ff = f0_ * (f1_ / f0_) ** ((tt - s0) / (s1 - s0))
            r = f_to_row(ff)
            for di in range(-3, 4):
                rr = r + di
                if 0 <= rr < N_F:
                    data[rr, ti] = max(
                        data[rr, ti],
                        -28 + 6 * np.exp(-(di ** 2) / 3.6),
                    )

    # Faint room noise filtering at very high freq (rolled off above 12 kHz)
    high_idx = f_to_row(12000)
    rolloff = np.linspace(0, -12, N_F - high_idx)
    data[high_idx:, :] += rolloff[:, None] * 0.5

    # Gentle smoothing for cleaner rendering
    data = gaussian_filter(data, sigma=(0.55, 1.4))
    return log_f, t, data


# ─── helpers ────────────────────────────────────────────────────────────────
def hline(ax, x0, x1, y, color=RULE, lw=0.35, alpha=1.0, zorder=3):
    ax.plot([x0, x1], [y, y], color=color, lw=lw, alpha=alpha,
            solid_capstyle="butt", zorder=zorder)


def vtick(ax, x, y0, y1, color=INK_DIM, lw=0.45, zorder=5):
    ax.plot([x, x], [y0, y1], color=color, lw=lw,
            solid_capstyle="butt", zorder=zorder)


def htick(ax, x0, x1, y, color=INK_DIM, lw=0.45, zorder=5):
    ax.plot([x0, x1], [y, y], color=color, lw=lw,
            solid_capstyle="butt", zorder=zorder)


# ─── compose ────────────────────────────────────────────────────────────────
def compose(out_pdf: str, out_png: str):
    log_f, t, data_db = synth_spectrogram()

    # PAGE: 11 × 14.667 inches (3:4 portrait, museum print)
    W_in, H_in = 11.0, 14.667
    fig = plt.figure(figsize=(W_in, H_in), facecolor=PAPER)
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)

    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_facecolor(PAPER)
    ax.axis("off")

    # ─── frame ──────────────────────────────────────────────────────────
    FX0, FX1 = 0.062, 0.938
    FY0, FY1 = 0.058, 0.964
    ax.add_patch(Rectangle((FX0, FY0), FX1 - FX0, FY1 - FY0,
                           fill=False, edgecolor=RULE, lw=0.45, zorder=2))

    # corner calibration ticks
    tk = 0.012
    for cx, cy in [(FX0, FY0), (FX1, FY0), (FX0, FY1), (FX1, FY1)]:
        ax.plot([cx - tk, cx + tk], [cy, cy], color=INK_DIM, lw=0.45, zorder=3)
        ax.plot([cx, cx], [cy - tk, cy + tk], color=INK_DIM, lw=0.45, zorder=3)

    # ─── top strip ──────────────────────────────────────────────────────
    Y_TOP = 0.940
    ax.text(0.084, Y_TOP, "I", fontfamily=F_DISPLAY, fontsize=11,
            color=INK, ha="left", va="center", alpha=0.92, zorder=5)
    ax.text(0.106, Y_TOP, "TAFEL  PRIMA",
            fontfamily=F_SANS, fontsize=7.0, color=INK_DIM,
            ha="left", va="center", zorder=5)

    # central thin rule with two ticks (ornament)
    hline(ax, 0.290, 0.710, Y_TOP, color=RULE, lw=0.30)
    vtick(ax, 0.486, Y_TOP - 0.005, Y_TOP + 0.005, color=INK_DIM, lw=0.35)
    vtick(ax, 0.514, Y_TOP - 0.005, Y_TOP + 0.005, color=INK_DIM, lw=0.35)

    ax.text(0.916, Y_TOP, "MMXXVI    EDITION  I",
            fontfamily=F_MONO, fontsize=7.0, color=INK_DIM,
            ha="right", va="center", zorder=5)

    # ─── title block ────────────────────────────────────────────────────
    ax.text(0.500, 0.876, "SPEKTRALGRUND",
            fontfamily=F_TITLE, fontsize=88, color=INK,
            ha="center", va="center", zorder=5)

    ax.text(0.500, 0.823,
            "an atlas of the audible field",
            fontfamily=F_SERIF_I, fontsize=15.5, fontstyle="italic",
            color=INK_DIM, ha="center", va="center", zorder=5)

    ax.text(0.500, 0.798,
            "·   S P E K T O · W A T C H   ·",
            fontfamily=F_SANS, fontsize=8.2, color=INK_FAINT,
            ha="center", va="center", zorder=5)

    # decorative micro-rule beneath
    hline(ax, 0.460, 0.540, 0.785, color=INK_GHOST, lw=0.35)

    # ─── plate ──────────────────────────────────────────────────────────
    PX0, PX1 = 0.140, 0.788
    PY0, PY1 = 0.250, 0.760

    img = SPEKTRAL_CMAP(np.clip((data_db + 96.0) / 96.0, 0, 1))
    ax.imshow(
        img,
        extent=[PX0, PX1, PY0, PY1],
        origin="lower",
        aspect="auto",
        interpolation="bilinear",
        zorder=2,
    )
    # plate border
    ax.add_patch(Rectangle((PX0, PY0), PX1 - PX0, PY1 - PY0,
                           fill=False, edgecolor=RULE, lw=0.55, zorder=4))

    # plate identifier inside top-left of plate (small, like an old engraving)
    ax.text(PX0 + 0.010, PY1 - 0.014, "fig. I",
            fontfamily=F_SERIF_I, fontstyle="italic", fontsize=9.5,
            color=INK, ha="left", va="top", zorder=5, alpha=0.95)

    # ─── frequency axis (left) ──────────────────────────────────────────
    f_ticks  = [20, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000]
    f_labels = ["20", "50", "100", "200", "500", "1 k", "2 k", "5 k", "10 k", "20 k"]
    log_min, log_max = np.log10(20), np.log10(20_000)
    for f, lbl in zip(f_ticks, f_labels):
        yn = (np.log10(f) - log_min) / (log_max - log_min)
        yp = PY0 + yn * (PY1 - PY0)
        htick(ax, PX0 - 0.010, PX0, yp)
        ax.text(PX0 - 0.014, yp, lbl,
                fontfamily=F_MONO, fontsize=7.2, color=INK_DIM,
                ha="right", va="center", zorder=5)

    ax.text(PX0 - 0.060, (PY0 + PY1) / 2,
            "F R E Q U E N C Y    /    H z",
            fontfamily=F_SANS, fontsize=7.4, color=INK_FAINT,
            rotation=90, ha="center", va="center", zorder=5)

    # ─── time axis (bottom) ─────────────────────────────────────────────
    t_ticks = [0, 10, 20, 30, 40, 50, 60]
    for tt in t_ticks:
        xn = tt / 60.0
        xp = PX0 + xn * (PX1 - PX0)
        vtick(ax, xp, PY0 - 0.008, PY0)
        m, s = divmod(tt, 60)
        ax.text(xp, PY0 - 0.014, f"{m:02d}:{s:02d}",
                fontfamily=F_MONO, fontsize=7.2, color=INK_DIM,
                ha="center", va="top", zorder=5)
    ax.text((PX0 + PX1) / 2, PY0 - 0.030,
            "T I M E    /    m m : s s",
            fontfamily=F_SANS, fontsize=7.4, color=INK_FAINT,
            ha="center", va="top", zorder=5)

    # ─── dB color bar (right) ───────────────────────────────────────────
    BX0, BX1 = 0.812, 0.832
    bar_grad = np.linspace(0, 1, 512)[:, None]
    ax.imshow(
        SPEKTRAL_CMAP(bar_grad),
        extent=[BX0, BX1, PY0, PY1],
        origin="lower", aspect="auto", zorder=3,
    )
    ax.add_patch(Rectangle((BX0, PY0), BX1 - BX0, PY1 - PY0,
                           fill=False, edgecolor=RULE, lw=0.55, zorder=4))
    db_ticks = [-90, -75, -60, -45, -30, -15, 0]
    for db in db_ticks:
        yn = (db + 96) / 96
        if not (0 <= yn <= 1):
            continue
        yp = PY0 + yn * (PY1 - PY0)
        htick(ax, BX1, BX1 + 0.008, yp)
        label = f"{db:+d}" if db != 0 else "  0"
        ax.text(BX1 + 0.012, yp, label,
                fontfamily=F_MONO, fontsize=7.0, color=INK_DIM,
                ha="left", va="center", zorder=5)
    ax.text(BX0 + (BX1 - BX0) / 2, PY1 + 0.012,
            "dB", fontfamily=F_SANS, fontsize=7.2,
            color=INK_FAINT, ha="center", va="bottom", zorder=5)
    # tiny weighting note below bar
    ax.text(BX0 + (BX1 - BX0) / 2, PY0 - 0.030,
            "A-wt.", fontfamily=F_SERIF_I, fontstyle="italic", fontsize=7.5,
            color=INK_FAINT, ha="center", va="top", zorder=5)

    # ─── plate caption (italic, beneath plate axes) ─────────────────────
    Y_RULE_CAP = 0.196
    Y_CAP1     = 0.181
    Y_CAP2     = 0.166

    hline(ax, FX0 + 0.008, FX1 - 0.008, Y_RULE_CAP, color=RULE, lw=0.35)

    ax.text(FX0 + 0.014, Y_CAP1, "fig. I",
            fontfamily=F_SERIF_I, fontstyle="italic", fontsize=10.5,
            color=INK, ha="left", va="center", zorder=5)
    ax.text(FX0 + 0.060, Y_CAP1,
            "Chromatic field — sixty seconds of acoustic observation,",
            fontfamily=F_SERIF_I, fontstyle="italic", fontsize=10.5,
            color=INK_DIM, ha="left", va="center", zorder=5)
    ax.text(FX0 + 0.060, Y_CAP2,
            "rendered through perceptual chromaticity over weighted dB(A).",
            fontfamily=F_SERIF_I, fontstyle="italic", fontsize=10.5,
            color=INK_DIM, ha="left", va="center", zorder=5)

    # ─── scientific footer (three columns) ──────────────────────────────
    Y_RULE_FOOT  = 0.150
    Y_FOOT_HEAD  = 0.140
    Y_FOOT_HRULE = 0.131
    Y_FOOT_BOD1  = 0.121
    Y_FOOT_BOD2  = 0.110

    hline(ax, FX0 + 0.008, FX1 - 0.008, Y_RULE_FOOT, color=RULE, lw=0.35)

    columns = [
        (0.250, "FREQUENCY  DOMAIN",
         "20 Hz — 22.05 kHz",
         "logarithmic chromaticity"),
        (0.500, "WEIGHTING   /   TRANSFORM",
         "dB(A)    FFT 8192",
         "hop 1024    87.5 % overlap"),
        (0.750, "TEMPORAL  RANGE",
         "60.000 s",
         "sample 48 kHz    24-bit"),
    ]
    for cx, head, b1, b2 in columns:
        ax.text(cx, Y_FOOT_HEAD, head,
                fontfamily=F_SANS, fontsize=7.4, color=INK,
                ha="center", va="center", zorder=5)
        hline(ax, cx - 0.062, cx + 0.062, Y_FOOT_HRULE,
              color=RULE, lw=0.30)
        ax.text(cx, Y_FOOT_BOD1, b1,
                fontfamily=F_MONO, fontsize=7.4, color=INK_DIM,
                ha="center", va="center", zorder=5)
        ax.text(cx, Y_FOOT_BOD2, b2,
                fontfamily=F_MONO, fontsize=7.0, color=INK_FAINT,
                ha="center", va="center", zorder=5)

    # ─── bottom matter (wordmark, tagline, maker mark) ──────────────────
    Y_RULE_BOT = 0.097
    hline(ax, FX0 + 0.008, FX1 - 0.008, Y_RULE_BOT, color=RULE, lw=0.35)

    Y_WORD    = 0.082
    Y_TAGLINE = 0.069

    ax.text(0.500, Y_WORD,
            "S  P  E  K  T  O      W  A  T  C  H",
            fontfamily=F_SANS, fontsize=11.0, color=INK,
            ha="center", va="center", zorder=5)
    ax.text(0.500, Y_TAGLINE,
            "instrument for the acoustic field",
            fontfamily=F_SERIF_I, fontstyle="italic", fontsize=9.5,
            color=INK_DIM, ha="center", va="center", zorder=5)

    # maker's mark right
    ax.text(0.916, Y_WORD, "S B    no. 0001",
            fontfamily=F_MONO, fontsize=7.0, color=INK_FAINT,
            ha="right", va="center", zorder=5)
    ax.text(0.916, Y_TAGLINE, "atlas i.",
            fontfamily=F_MONO, fontsize=6.6, color=INK_GHOST,
            ha="right", va="center", zorder=5)

    # left mark — date and provenance
    ax.text(0.084, Y_WORD, "·  M M X X V I",
            fontfamily=F_MONO, fontsize=7.0, color=INK_FAINT,
            ha="left", va="center", zorder=5)
    ax.text(0.084, Y_TAGLINE, "audible field",
            fontfamily=F_MONO, fontsize=6.6, color=INK_GHOST,
            ha="left", va="center", zorder=5)

    # ─── save ───────────────────────────────────────────────────────────
    fig.savefig(out_pdf, dpi=300, facecolor=PAPER,
                bbox_inches=None, pad_inches=0)
    fig.savefig(out_png, dpi=300, facecolor=PAPER,
                bbox_inches=None, pad_inches=0)
    plt.close(fig)
    print(f"Wrote {out_pdf}")
    print(f"Wrote {out_png}")


if __name__ == "__main__":
    out_dir = "/sessions/bold-beautiful-bardeen/mnt/SpektoWatch2/design"
    os.makedirs(out_dir, exist_ok=True)
    compose(
        out_pdf=os.path.join(out_dir, "spektowatch_plate_I.pdf"),
        out_png=os.path.join(out_dir, "spektowatch_plate_I.png"),
    )
