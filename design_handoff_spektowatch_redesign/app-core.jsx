/* SpektoWatch redesign — main app + preset screens */
/* global React, ReactDOM, IOSFrame */
(function() {
const { useState, useEffect, useRef, useMemo } = React;

/* ============================================================
   ICONS — minimal stroke
   ============================================================ */
const Icon = {
  Gear: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3"/>
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06A2 2 0 1 1 4.27 16.96l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h0a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v0a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>
    </svg>
  ),
  Layers: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 2 2 7l10 5 10-5-10-5z"/>
      <path d="m2 17 10 5 10-5"/>
      <path d="m2 12 10 5 10-5"/>
    </svg>
  ),
  Edit: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 20h9"/>
      <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4z"/>
    </svg>
  ),
  Play: () => (
    <svg viewBox="0 0 24 24" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg>
  ),
  Pause: () => (
    <svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>
  ),
  Rec: () => (
    <svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="6"/></svg>
  ),
  Stop: () => (
    <svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>
  ),
  Folder: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>
    </svg>
  ),
  Wave: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 12c2 0 2-4 4-4s2 8 4 8 2-12 4-12 2 16 4 16 2-8 4-8"/>
    </svg>
  ),
  Spectrum: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <line x1="4" y1="20" x2="4" y2="14"/>
      <line x1="9" y1="20" x2="9" y2="6"/>
      <line x1="14" y1="20" x2="14" y2="10"/>
      <line x1="19" y1="20" x2="19" y2="16"/>
    </svg>
  ),
  Falls: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <path d="M3 6h18M3 11h18M3 16h18M3 21h18"/>
    </svg>
  ),
  Atom: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
      <circle cx="12" cy="12" r="2"/>
      <ellipse cx="12" cy="12" rx="10" ry="4"/>
      <ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(60 12 12)"/>
      <ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(-60 12 12)"/>
    </svg>
  ),
  Sliders: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/>
      <line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/>
      <line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/>
      <line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/>
    </svg>
  ),
  Mic: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
      <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
      <line x1="12" y1="19" x2="12" y2="23"/>
      <line x1="8" y1="23" x2="16" y2="23"/>
    </svg>
  ),
  MicOff: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <line x1="1" y1="1" x2="23" y2="23"/>
      <path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/>
      <path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/>
      <line x1="12" y1="19" x2="12" y2="23"/>
    </svg>
  ),
  Tone: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <path d="M3 12 c 3 -8 6 -8 9 0 s 6 8 9 0"/>
    </svg>
  ),
  Expand: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="15 3 21 3 21 9"/>
      <polyline points="9 21 3 21 3 15"/>
      <line x1="21" y1="3" x2="14" y2="10"/>
      <line x1="3" y1="21" x2="10" y2="14"/>
    </svg>
  ),
  Hash: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <line x1="4" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="20" y2="15"/>
      <line x1="10" y1="3" x2="8" y2="21"/><line x1="16" y1="3" x2="14" y2="21"/>
    </svg>
  ),
  Grid: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
      <rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/>
      <rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/>
    </svg>
  ),
  Number: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <text x="12" y="17" textAnchor="middle" fontSize="14" fontFamily="monospace" stroke="none" fill="currentColor">42</text>
    </svg>
  ),
  Phase: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
      <circle cx="12" cy="12" r="9"/>
      <path d="M12 3a9 9 0 0 0 0 18"/>
    </svg>
  ),
  Check: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="20 6 9 17 4 12"/>
    </svg>
  ),
  Grip: () => (
    <svg viewBox="0 0 24 24" fill="currentColor">
      <circle cx="9" cy="6" r="1.5"/><circle cx="15" cy="6" r="1.5"/>
      <circle cx="9" cy="12" r="1.5"/><circle cx="15" cy="12" r="1.5"/>
      <circle cx="9" cy="18" r="1.5"/><circle cx="15" cy="18" r="1.5"/>
    </svg>
  ),
  X: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/>
    </svg>
  ),
  Plus: () => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
    </svg>
  ),
};
const PRESETS = [
  { id: "overview",    name: "Übersicht",    icon: "Grid" },
  { id: "spectrogram", name: "Spektrogramm", icon: "Falls" },
  { id: "waterfall",   name: "Wasserfall",   icon: "Falls" },
  { id: "level-time",  name: "Pegelverlauf", icon: "Wave" },
  { id: "spectrum",    name: "Frequenz-Spektrum", icon: "Spectrum" },
  { id: "phase",       name: "Phasen-Meter", icon: "Phase" },
  { id: "level-meter", name: "Pegel-Meter",  icon: "Sliders" },
  { id: "single",      name: "Einzelwert",   icon: "Number" },
  { id: "tone",        name: "Tongenerator", icon: "Tone" },
  { id: "masking",     name: "Sound Masking", icon: "Grid" },
  { id: "lab",         name: "Spektralanalyse-Labor", icon: "Atom" },
];

/* ============================================================
   Generators (deterministic-ish noise)
   ============================================================ */
function makeSpectrogramData(w, h, seed = 1) {
  // Returns 2D array [h][w] in [0,1]
  const out = [];
  for (let y = 0; y < h; y++) {
    const row = new Float32Array(w);
    const freqWeight = Math.pow(1 - y / h, 1.4); // low freq louder
    for (let x = 0; x < w; x++) {
      const t = x / w;
      const n1 = Math.sin(t * 13 + y * 0.3 + seed) * 0.5 + 0.5;
      const n2 = Math.sin(t * 47 + y * 0.7 + seed * 3) * 0.5 + 0.5;
      const n3 = Math.sin(t * 5 + y * 0.05) * 0.5 + 0.5;
      const noise = (Math.sin((x * 7 + y * 11) * seed) * 10000) % 1;
      const noiseAbs = Math.abs(noise);
      let v = (n1 * 0.4 + n2 * 0.3 + n3 * 0.2 + noiseAbs * 0.4) * freqWeight;
      v = Math.max(0, Math.min(1, v));
      row[x] = v;
    }
    out.push(row);
  }
  return out;
}

function viridis(t) {
  // Approximate viridis colormap, t in [0,1]
  t = Math.max(0, Math.min(1, t));
  const stops = [
    [0.00, [68, 1, 84]],
    [0.25, [59, 82, 139]],
    [0.50, [33, 145, 140]],
    [0.75, [94, 201, 98]],
    [1.00, [253, 231, 37]],
  ];
  for (let i = 0; i < stops.length - 1; i++) {
    const [a, ca] = stops[i];
    const [b, cb] = stops[i + 1];
    if (t <= b) {
      const k = (t - a) / (b - a);
      return [
        Math.round(ca[0] + (cb[0] - ca[0]) * k),
        Math.round(ca[1] + (cb[1] - ca[1]) * k),
        Math.round(ca[2] + (cb[2] - ca[2]) * k),
      ];
    }
  }
  return stops[stops.length - 1][1];
}

function inferno(t) {
  t = Math.max(0, Math.min(1, t));
  const stops = [
    [0.00, [0, 0, 4]],
    [0.25, [87, 16, 110]],
    [0.50, [188, 55, 84]],
    [0.75, [249, 142, 9]],
    [1.00, [252, 255, 164]],
  ];
  for (let i = 0; i < stops.length - 1; i++) {
    const [a, ca] = stops[i];
    const [b, cb] = stops[i + 1];
    if (t <= b) {
      const k = (t - a) / (b - a);
      return [
        Math.round(ca[0] + (cb[0] - ca[0]) * k),
        Math.round(ca[1] + (cb[1] - ca[1]) * k),
        Math.round(ca[2] + (cb[2] - ca[2]) * k),
      ];
    }
  }
  return stops[stops.length - 1][1];
}

function magma(t) {
  t = Math.max(0, Math.min(1, t));
  const stops = [
    [0.00, [0, 0, 4]],
    [0.50, [128, 28, 109]],
    [1.00, [252, 253, 191]],
  ];
  for (let i = 0; i < stops.length - 1; i++) {
    const [a, ca] = stops[i];
    const [b, cb] = stops[i + 1];
    if (t <= b) {
      const k = (t - a) / (b - a);
      return [
        Math.round(ca[0] + (cb[0] - ca[0]) * k),
        Math.round(ca[1] + (cb[1] - ca[1]) * k),
        Math.round(ca[2] + (cb[2] - ca[2]) * k),
      ];
    }
  }
  return stops[stops.length - 1][1];
}

const COLORMAPS = { viridis, inferno, magma };

/* ============================================================
   SpectrogramCanvas
   ============================================================ */
function SpectrogramCanvas({ cmap = "viridis", width = 280, height = 320 }) {
  const ref = useRef(null);
  useEffect(() => {
    const c = ref.current;
    if (!c) return;
    c.width = width;
    c.height = height;
    const ctx = c.getContext("2d");
    const data = makeSpectrogramData(width, height, 1.3);
    const img = ctx.createImageData(width, height);
    const fn = COLORMAPS[cmap] || viridis;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const v = data[y][x];
        const [r, g, b] = fn(v);
        const idx = (y * width + x) * 4;
        img.data[idx] = r;
        img.data[idx + 1] = g;
        img.data[idx + 2] = b;
        img.data[idx + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
  }, [cmap, width, height]);
  return <canvas ref={ref} style={{ width: "100%", height: "100%", display: "block" }} />;
}

/* ============================================================
   FrequencyAxis (vertical, log)
   ============================================================ */
function FreqScaleY({ height }) {
  const labels = [
    { hz: "20k", pos: 0.02 },
    { hz: "8k",  pos: 0.18 },
    { hz: "2k",  pos: 0.38 },
    { hz: "500", pos: 0.55 },
    { hz: "125", pos: 0.72 },
    { hz: "31",  pos: 0.92 },
  ];
  return (
    <div className="scale-y" style={{ height }}>
      {labels.map((l) => (
        <div key={l.hz} className="scale-y-tick" style={{ top: `${l.pos * 100}%` }}>{l.hz}</div>
      ))}
    </div>
  );
}

/* ============================================================
   Header + Preset Rail
   ============================================================ */
function AppHeader({ presetName, editing, onLayouts, onSettings, onEdit }) {
  return (
    <div className="header glass-strong">
      <div className="header-title">
        <div className="header-eyebrow">{editing ? "Layout bearbeiten" : "Dashboard · Live"}</div>
        <div className="header-name">{presetName}</div>
      </div>
      <div className="header-actions">
        {!editing && <button className="icon-btn" onClick={onSettings} aria-label="Einstellungen"><Icon.Gear/></button>}
        {!editing && <button className="icon-btn" onClick={onLayouts} aria-label="Layouts"><Icon.Layers/></button>}
        <button
          className={editing ? "icon-btn is-done" : "icon-btn is-accent"}
          onClick={onEdit}
          aria-label="Bearbeiten"
        >
          {editing ? <Icon.Check/> : <Icon.Edit/>}
        </button>
      </div>
    </div>
  );
}

function PresetRail({ presets, activeId, onSelect }) {
  const railRef = useRef(null);
  useEffect(() => {
    const el = railRef.current;
    if (!el) return;
    const active = el.querySelector('[aria-current="true"]');
    if (active) {
      const elRect = el.getBoundingClientRect();
      const aRect = active.getBoundingClientRect();
      const center = aRect.left + aRect.width / 2 - elRect.left;
      el.scrollTo({ left: el.scrollLeft + center - el.clientWidth / 2, behavior: "smooth" });
    }
  }, [activeId]);
  return (
    <div className="preset-rail" ref={railRef}>
      {presets.map((p) => (
        <button
          key={p.id}
          className="preset-chip"
          aria-current={p.id === activeId}
          onClick={() => onSelect(p.id)}
        >
          <span className="preset-chip-dot"/>
          {p.name}
        </button>
      ))}
    </div>
  );
}

/* ============================================================
   Transport
   ============================================================ */
function Transport({ state, onPlay, onRec, recording, playing, cursor }) {
  const statusText =
    recording ? "Aufnahme" :
    playing ? "Wiedergabe" :
    state === "live" ? "Live-Modus" :
    "Bereit";
  const ledClass =
    recording ? "rec" :
    (state === "live" || playing) ? "live" :
    "";
  return (
    <div className="transport glass-strong">
      <div className="transport-status">
        <span className={`led ${ledClass}`}/>
        <span className="transport-status-text">
          {statusText} · <b>{cursor}</b>
        </span>
      </div>
      <div className="transport-actions">
        <button className="t-btn is-play" data-on={playing} onClick={onPlay}>
          {playing ? <Icon.Pause/> : <Icon.Play/>}
        </button>
        <button className="t-btn is-rec" data-on={recording} onClick={onRec}>
          {recording ? <Icon.Stop/> : <Icon.Rec/>}
        </button>
        <button className="t-btn"><Icon.Folder/></button>
      </div>
    </div>
  );
}

/* ============================================================
   Widget chrome
   ============================================================ */
function Widget({ title, icon, meta, children, className = "" }) {
  const IconEl = icon ? Icon[icon] : null;
  return (
    <section className={`widget glass ${className}`}>
      <div className="widget-edit-overlay">
        <button className="widget-grip" aria-label="Verschieben"><Icon.Grip/></button>
        <button className="widget-close" aria-label="Entfernen"><Icon.X/></button>
      </div>
      <header className="widget-head">
        <div className="widget-title">
          {IconEl && <IconEl/>}
          <span>{title}</span>
        </div>
        {meta && <div className="widget-meta">{meta}</div>}
      </header>
      {children}
    </section>
  );
}

window.SpektoUI = { Icon, PRESETS, COLORMAPS, viridis, inferno, magma,
  AppHeader, PresetRail, Transport, Widget, SpectrogramCanvas, FreqScaleY,
  makeSpectrogramData };
})();
