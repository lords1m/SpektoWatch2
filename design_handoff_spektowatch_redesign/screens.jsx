/* SpektoWatch — preset screens (chart widgets) */
/* global React, SpektoUI */
(function() {
const { useState, useEffect, useRef, useMemo } = React;
const { Icon, Widget, SpectrogramCanvas, FreqScaleY, viridis, inferno, magma } = window.SpektoUI;

/* ---------- SPECTROGRAM ---------- */
function ScreenSpectrogram({ cmap }) {
  const H = 360;
  return (
    <Widget title="STFT · Live" icon="Falls" meta={<><b>1024 bins · Δf 21.5 Hz</b></>}>
      <div className="row" style={{ alignItems: "stretch" }}>
        <FreqScaleY height={H}/>
        <div className="canvas" style={{ flex: 1, height: H }}>
          <SpectrogramCanvas cmap={cmap} width={300} height={H}/>
          <div className="readout">
            <div className="readout-row"><span>NOW</span><span>−5.0 s</span></div>
            <div className="readout-row"><span>BIN</span><span>1024</span></div>
            <div className="readout-row"><span>WIN</span><span>B-Harris</span></div>
          </div>
        </div>
      </div>
      <div className="scale-x" style={{ marginLeft: 28 }}>
        <span>−5.0s</span><span>−4.0s</span><span>−3.0s</span><span>−2.0s</span><span>−1.0s</span><span>0.0</span>
      </div>
    </Widget>
  );
}

/* ---------- WATERFALL (3D) ---------- */
function ScreenWaterfall({ cmap }) {
  // Simulated 3D ridge plot — rows of polyline with skew, viridis-colored fill
  const ROWS = 28;
  const POINTS = 60;
  const W = 300;
  const H = 320;
  const lines = useMemo(() => {
    return Array.from({ length: ROWS }, (_, r) => {
      const pts = [];
      for (let i = 0; i < POINTS; i++) {
        const t = i / (POINTS - 1);
        const base = Math.exp(-Math.pow((t - 0.45) * 3, 2)) * 0.8;
        const noise = (Math.sin(i * 1.3 + r * 0.7) * 0.5 + 0.5) * 0.3;
        const decay = 1 - r / ROWS;
        pts.push(base * decay * (0.7 + noise * 0.6));
      }
      return pts;
    });
  }, []);
  const skewX = 30;
  const skewY = 6;
  const rowH = H / ROWS;
  const peakH = rowH * 4.5;

  return (
    <Widget title="3D · A-bewertet" icon="Falls" meta={<><b>28 Frames · 20→−110 dB</b></>}>
      <div className="canvas" style={{ height: H, position: "relative" }}>
        <svg viewBox={`0 0 ${W + skewX} ${H + skewY * ROWS / 4}`} width="100%" height="100%" preserveAspectRatio="none">
          {lines.map((pts, r) => {
            const yBase = H - r * rowH * 0.55;
            const offsetX = (r / ROWS) * skewX;
            const path = pts.map((v, i) => {
              const x = offsetX + (i / (POINTS - 1)) * W;
              const y = yBase - v * peakH;
              return `${i === 0 ? "M" : "L"} ${x.toFixed(2)} ${y.toFixed(2)}`;
            }).join(" ");
            const filled = `${path} L ${offsetX + W} ${yBase} L ${offsetX} ${yBase} Z`;
            const [cR, cG, cB] = (cmap === "magma" ? magma : cmap === "viridis" ? viridis : inferno)(0.85 - r / ROWS * 0.4);
            const fillColor = `rgba(${cR},${cG},${cB},0.35)`;
            const strokeColor = `rgba(${cR},${cG},${cB},0.9)`;
            return (
              <g key={r}>
                <path d={filled} fill={fillColor}/>
                <path d={path} stroke={strokeColor} strokeWidth="0.6" fill="none"/>
              </g>
            );
          })}
        </svg>
        <div className="readout">
          <div className="readout-row"><span>FRAME</span><span>028</span></div>
          <div className="readout-row"><span>PEAK</span><span>−12 dB</span></div>
        </div>
        <div className="canvas-label" style={{ left: 10, top: 10 }}>20 dB</div>
        <div className="canvas-label" style={{ left: 10, bottom: 30 }}>−110 dB</div>
        <div className="canvas-label" style={{ left: 10, bottom: 10 }}>20 Hz</div>
        <div className="canvas-label" style={{ right: 10, bottom: 10 }}>20 kHz</div>
      </div>
    </Widget>
  );
}

/* ---------- LEVEL TIME (Pegelverlauf) ---------- */
function ScreenLevelTime() {
  const W = 320, H = 220;
  const pts = useMemo(() => {
    const out = [];
    for (let i = 0; i < 200; i++) {
      const t = i / 199;
      const base = 32;
      const peak1 = 14 * Math.exp(-Math.pow((t - 0.32) * 8, 2));
      const peak2 = 17 * Math.exp(-Math.pow((t - 0.78) * 10, 2));
      const noise = (Math.sin(i * 0.7) * 0.5 + Math.sin(i * 2.3) * 0.3) * 1.2;
      out.push(base + peak1 + peak2 + noise);
    }
    return out;
  }, []);
  const yMin = 20, yMax = 110;
  const xs = pts.map((_, i) => (i / (pts.length - 1)) * W);
  const ys = pts.map(v => H - ((v - yMin) / (yMax - yMin)) * H);
  const linePath = xs.map((x, i) => `${i === 0 ? "M" : "L"} ${x.toFixed(2)} ${ys[i].toFixed(2)}`).join(" ");
  const fillPath = `${linePath} L ${W} ${H} L 0 ${H} Z`;
  const yLabels = [110, 100, 90, 80, 70, 60, 50, 40, 30, 20];
  const last = pts[pts.length - 1];

  return (
    <Widget title="LAF · 5 s Verlauf" icon="Wave" meta={<><b>aktuell {last.toFixed(1)} dB</b></>}>
      <div className="row" style={{ alignItems: "stretch" }}>
        <div className="scale-y" style={{ height: H }}>
          {yLabels.map((y, i) => (
            <div key={y} className="scale-y-tick" style={{ top: `${(i / (yLabels.length - 1)) * 100}%` }}>{y}</div>
          ))}
        </div>
        <div className="canvas" style={{ flex: 1, height: H, position: "relative" }}>
          <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%" preserveAspectRatio="none">
            <defs>
              <linearGradient id="lafFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.35"/>
                <stop offset="100%" stopColor="var(--accent)" stopOpacity="0"/>
              </linearGradient>
            </defs>
            {/* h-grid */}
            {yLabels.map((_, i) => (
              <line key={i}
                x1="0" x2={W}
                y1={(i / (yLabels.length - 1)) * H}
                y2={(i / (yLabels.length - 1)) * H}
                className="axis-line"
              />
            ))}
            <path d={fillPath} fill="url(#lafFill)"/>
            <path d={linePath} stroke="var(--accent)" strokeWidth="1.4" fill="none"/>
          </svg>
          <div className="readout">
            <div className="readout-row"><span>LAF</span><span>{last.toFixed(1)} dB</span></div>
            <div className="readout-row"><span>Leq</span><span>38.4 dB</span></div>
            <div className="readout-row"><span>Lmax</span><span>49.1 dB</span></div>
          </div>
        </div>
      </div>
      <div className="scale-x" style={{ marginLeft: 28 }}>
        <span>−5.0s</span><span>−4.0s</span><span>−3.0s</span><span>−2.0s</span><span>−1.0s</span><span>0.0</span>
      </div>
    </Widget>
  );
}

/* ---------- FREQUENCY SPECTRUM ---------- */
function ScreenSpectrum() {
  const W = 320, H = 240;
  const pts = useMemo(() => {
    const out = [];
    for (let i = 0; i < 160; i++) {
      const t = i / 159;
      const peaks =
        20 * Math.exp(-Math.pow((t - 0.12) * 18, 2)) +
        45 * Math.exp(-Math.pow((t - 0.28) * 22, 2)) +
        38 * Math.exp(-Math.pow((t - 0.46) * 16, 2)) +
        28 * Math.exp(-Math.pow((t - 0.68) * 20, 2)) +
        18 * Math.exp(-Math.pow((t - 0.85) * 14, 2));
      const noise = Math.abs(Math.sin(i * 1.7) * Math.cos(i * 0.3)) * 8;
      out.push(20 + peaks + noise);
    }
    return out;
  }, []);
  const yMin = 20, yMax = 110;
  const xs = pts.map((_, i) => (i / (pts.length - 1)) * W);
  const ys = pts.map(v => H - ((v - yMin) / (yMax - yMin)) * H);
  const linePath = xs.map((x, i) => `${i === 0 ? "M" : "L"} ${x.toFixed(2)} ${ys[i].toFixed(2)}`).join(" ");
  const fillPath = `${linePath} L ${W} ${H} L 0 ${H} Z`;
  const yLabels = [110, 100, 90, 80, 70, 60, 50, 40, 30, 20];

  return (
    <Widget title="1/3 Oktav · Leq" icon="Spectrum" meta={<><b>64.2 dB · 20 Hz–20 kHz</b></>}>
      <div className="row" style={{ alignItems: "stretch" }}>
        <div className="scale-y" style={{ height: H }}>
          {yLabels.map((y, i) => (
            <div key={y} className="scale-y-tick" style={{ top: `${(i / (yLabels.length - 1)) * 100}%` }}>{y}</div>
          ))}
        </div>
        <div className="canvas" style={{ flex: 1, height: H, position: "relative" }}>
          <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%" preserveAspectRatio="none">
            <defs>
              <linearGradient id="specFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="oklch(0.78 0.18 145)" stopOpacity="0.55"/>
                <stop offset="100%" stopColor="oklch(0.78 0.18 145)" stopOpacity="0"/>
              </linearGradient>
            </defs>
            {yLabels.map((_, i) => (
              <line key={i} x1="0" x2={W}
                y1={(i / (yLabels.length - 1)) * H}
                y2={(i / (yLabels.length - 1)) * H}
                className="axis-line"
              />
            ))}
            <path d={fillPath} fill="url(#specFill)"/>
            <path d={linePath} stroke="oklch(0.82 0.16 145)" strokeWidth="1.2" fill="none"/>
          </svg>
          <div className="readout">
            <div className="readout-row"><span>PEAK</span><span>1.6 kHz</span></div>
            <div className="readout-row"><span>L</span><span>64.2 dB</span></div>
          </div>
        </div>
      </div>
      <div className="scale-x" style={{ marginLeft: 28 }}>
        <span>20</span><span>63</span><span>200</span><span>630</span><span>2k</span><span>6.3k</span><span>20k</span>
      </div>
    </Widget>
  );
}

/* ---------- LEVEL METER (Pegel-Meter) ---------- */
function ScreenLevelMeter() {
  const v1 = 0.48; // 30..100 → position
  const v2 = 0.55;
  return (
    <Widget title="Stereo L · R" icon="Sliders" meta={<><b>48 · 55 dB(A)</b></>}>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
        {[
          { label: "LAF · KANAL 1", val: 48.3, pos: v1 },
          { label: "LAF · KANAL 2", val: 55.1, pos: v2 },
        ].map((m, i) => (
          <div key={i} className="canvas" style={{ padding: 14, display: "flex", flexDirection: "column", gap: 10 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <div className="canvas-label">{m.label}</div>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--fg-dim)" }}>30 – 100 dB</div>
            </div>
            <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
              <div className="bignum" style={{ fontSize: 44 }}>{m.val.toFixed(1)}</div>
              <div className="bignum-unit">dB(A)</div>
            </div>
            <div className="peak">
              <div className="peak-fill" style={{ width: `${m.pos * 100}%` }}/>
              {[0.2, 0.5, 0.85].map(t => (
                <div key={t} className="peak-tick" style={{ left: `${t * 100}%` }}/>
              ))}
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--fg-dim)" }}>
              <span>30</span><span>65</span><span>100</span>
            </div>
          </div>
        ))}
      </div>
    </Widget>
  );
}

/* ---------- SINGLE VALUE ---------- */
function ScreenSingle() {
  const cards = [
    { sub: "LAF · A-bewertet", val: "50.2", unit: "dB(A)", accent: false },
    { sub: "LCF · C-bewertet", val: "62.3", unit: "dB(C)", accent: true },
    { sub: "Lmax · seit 00:00", val: "78.1", unit: "dB(A)", accent: false },
    { sub: "Leq · 10 min",      val: "54.7", unit: "dB(A)", accent: false },
  ];
  return (
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
      {cards.map((c, i) => (
        <section key={i} className="widget glass">
          <div className="widget-title">
            <Icon.Number/>
            <span>{c.sub}</span>
          </div>
          <div className="canvas" style={{ padding: "18px 14px", display: "flex", flexDirection: "column", gap: 4, alignItems: "flex-start" }}>
            <div className="bignum" style={{ fontSize: 56, color: c.accent ? "var(--accent)" : "var(--fg)" }}>
              {c.val}
            </div>
            <div className="bignum-unit">{c.unit}</div>
            <div style={{ marginTop: 8, fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--fg-dim)", display: "flex", gap: 10 }}>
              <span>min 32.1</span>
              <span>max 78.1</span>
            </div>
          </div>
        </section>
      ))}
    </div>
  );
}

/* ---------- TONE GENERATOR ---------- */
function ScreenTone({ accentTrace = true }) {
  const W = 320, H = 220;
  const [freq, setFreq] = useState(1000);
  const [playing, setPlaying] = useState(true);
  const [shape, setShape] = useState("Sinus");

  const lambdaCm = (343 / freq * 100).toFixed(1);

  // Render the wave to canvas — quick mock based on freq
  const cycles = Math.max(0.5, Math.log10(freq / 100) * 2.3);
  const path = useMemo(() => {
    const pts = [];
    for (let i = 0; i <= 200; i++) {
      const t = i / 200;
      let y;
      if (shape === "Sinus") y = Math.sin(t * Math.PI * 2 * cycles);
      else if (shape === "Rechteck") y = Math.sign(Math.sin(t * Math.PI * 2 * cycles));
      else if (shape === "Sägezahn") y = 2 * (t * cycles - Math.floor(0.5 + t * cycles));
      else y = (Math.random() - 0.5) * 1.4;
      pts.push(`${i === 0 ? "M" : "L"} ${t * W} ${H / 2 - y * H * 0.36}`);
    }
    return pts.join(" ");
  }, [shape, cycles]);

  const presets = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000];
  const sliderPos = ((Math.log10(freq) - Math.log10(20)) / (Math.log10(20000) - Math.log10(20))) * 100;

  return (
    <Widget title={`${shape} · Generator`} icon="Tone" meta={<><b>λ {lambdaCm} cm</b></>}>
      <div className="canvas" style={{ height: H, position: "relative" }}>
        <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%" preserveAspectRatio="none">
          <defs>
            <pattern id="toneGrid" width={W/16} height={H/10} patternUnits="userSpaceOnUse">
              <path d={`M ${W/16} 0 L 0 0 0 ${H/10}`} fill="none" stroke="oklch(0.6 0.1 145 / 0.18)" strokeWidth="0.5"/>
            </pattern>
          </defs>
          <rect width={W} height={H} fill="url(#toneGrid)"/>
          <line x1="0" y1={H/2} x2={W} y2={H/2} stroke="oklch(0.6 0.1 145 / 0.35)" strokeWidth="0.5"/>
          {/* glow */}
          <path d={path} stroke="var(--accent)" strokeWidth="2.4" fill="none" style={{ filter: "blur(3px)", opacity: 0.55 }}/>
          <path d={path} stroke="oklch(0.92 0.16 145)" strokeWidth="1.1" fill="none"/>
        </svg>
        <div className="readout">
          <div className="readout-row"><span>f</span><span>{freq.toFixed(0)} Hz</span></div>
          <div className="readout-row"><span>λ</span><span>{lambdaCm} cm</span></div>
          <div className="readout-row"><span>L</span><span>−6 dB</span></div>
        </div>
        <button className="icon-btn" style={{ position: "absolute", top: 8, left: 8, background: "oklch(0 0 0 / 0.4)" }}>
          <Icon.Expand/>
        </button>
      </div>

      <div style={{ display: "flex", alignItems: "baseline", gap: 8, justifyContent: "center", paddingTop: 4 }}>
        <div className="bignum" style={{ fontSize: 30, color: "var(--accent)" }}>{freq >= 1000 ? (freq/1000).toFixed(2) : freq.toFixed(0)}</div>
        <div className="bignum-unit">{freq >= 1000 ? "kHz" : "Hz"}</div>
      </div>

      <div className="slider" style={{ marginTop: -4 }}>
        <div className="slider-track"/>
        <div className="slider-fill" style={{ width: `${sliderPos}%` }}/>
        <div className="slider-thumb" style={{ left: `${sliderPos}%` }}/>
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--fg-dim)", marginTop: -6 }}>
        <span>20</span><span>20k</span>
      </div>

      <div className="chip-strip">
        {presets.map(p => (
          <button key={p} className="chip" aria-current={p === freq} onClick={() => setFreq(p)}>
            {p >= 1000 ? `${p/1000}k` : p}
          </button>
        ))}
      </div>

      <div className="row" style={{ gap: 8 }}>
        <div className="segmented" style={{ flex: 1 }}>
          {["Sinus","Rechteck","Sägezahn","Noise"].map(s => (
            <button key={s} aria-current={s === shape} onClick={() => setShape(s)}>{s}</button>
          ))}
        </div>
      </div>

      <button
        onClick={() => setPlaying(p => !p)}
        style={{
          marginTop: 4,
          padding: "12px 16px",
          borderRadius: 14,
          border: 0,
          background: playing ? "oklch(from var(--accent) l c h / 0.18)" : "var(--accent)",
          color: playing ? "var(--accent)" : "oklch(0.15 0.02 250)",
          fontWeight: 600,
          fontSize: 13,
          letterSpacing: "0.04em",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 8,
          cursor: "pointer",
          border: "0.5px solid oklch(from var(--accent) l c h / 0.4)"
        }}
      >
        {playing ? <Icon.Pause/> : <Icon.Play/>}
        {playing ? "Pause" : "Play"}
      </button>
    </Widget>
  );
}

/* ---------- SOUND MASKING ---------- */
function ScreenMasking() {
  const sources = ["Sprache", "Tippen", "Verkehr", "Lüftung"];
  const W = 320, H = 100;
  const bars = useMemo(() => {
    return Array.from({ length: 18 }, (_, i) => ({
      target: 0.4 + Math.sin(i * 0.5) * 0.15 + 0.1,
      actual: 0.35 + Math.cos(i * 0.3) * 0.18 + (Math.random() * 0.05),
    }));
  }, []);

  return (
    <>
      <Widget title="Masking · Tippen" icon="Grid" meta={<><b>IDLE · ΔL 8.4 dB</b></>}>
        <div className="canvas" style={{ height: H, position: "relative", padding: 10 }}>
          <svg viewBox={`0 0 ${W} ${H - 20}`} width="100%" height="100%" preserveAspectRatio="none">
            {bars.map((b, i) => {
              const x = (i / bars.length) * W;
              const w = W / bars.length - 2;
              return (
                <g key={i}>
                  <rect x={x} y={(H-20) - b.target * (H-20)}
                    width={w} height={b.target * (H-20)}
                    fill="oklch(0.55 0.06 250 / 0.4)"
                  />
                  <rect x={x} y={(H-20) - b.actual * (H-20)}
                    width={w} height={b.actual * (H-20)}
                    fill="var(--accent)" opacity="0.9"
                  />
                </g>
              );
            })}
          </svg>
          <div className="status-floor">
            <span>20 Hz</span>
            <span>1 kHz</span>
            <span>20 kHz</span>
          </div>
        </div>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {sources.map((s, i) => (
            <button key={s} className="chip" style={{
              flex: "0 0 auto",
              padding: "5px 10px",
              border: "0.5px solid var(--glass-stroke)",
              background: i === 1 ? "oklch(from var(--accent) l c h / 0.18)" : "var(--glass-fill)",
              color: i === 1 ? "var(--accent)" : "var(--fg-muted)",
              borderRadius: 999,
            }}>{s}</button>
          ))}
        </div>
      </Widget>
      <Widget title="Masking-Übersicht" icon="Grid" meta={<><b>4 Quellen · LRA 12 dB</b></>}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
          {sources.map((s, i) => (
            <div key={s} className="canvas" style={{ padding: 10, display: "flex", flexDirection: "column", gap: 8 }}>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <div className="canvas-label">{s}</div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: i === 1 ? "var(--accent)" : "var(--fg-dim)" }}>
                  {i === 1 ? "MASK" : "IDLE"}
                </div>
              </div>
              <div className="bignum" style={{ fontSize: 22 }}>{(38 + i * 4.2).toFixed(1)}<span className="bignum-unit" style={{ marginLeft: 4, fontSize: 9 }}>dB</span></div>
              <div className="peak">
                <div className="peak-fill" style={{ width: `${30 + i * 12}%`, opacity: i === 1 ? 1 : 0.4 }}/>
              </div>
            </div>
          ))}
        </div>
      </Widget>
    </>
  );
}

/* ---------- PHASE METER ---------- */
function ScreenPhase() {
  return (
    <Widget title="Lissajous · Korrelation" icon="Phase" meta={<><b>Stereo erforderlich</b></>}>
      <div className="canvas" style={{ height: 280, position: "relative" }}>
        <svg viewBox="0 0 200 200" width="100%" height="100%" preserveAspectRatio="xMidYMid meet">
          {/* grid */}
          <circle cx="100" cy="100" r="80" stroke="oklch(0.55 0.01 255 / 0.18)" strokeWidth="0.5" fill="none"/>
          <circle cx="100" cy="100" r="55" stroke="oklch(0.55 0.01 255 / 0.14)" strokeWidth="0.5" fill="none"/>
          <circle cx="100" cy="100" r="30" stroke="oklch(0.55 0.01 255 / 0.10)" strokeWidth="0.5" fill="none"/>
          <line x1="20" y1="100" x2="180" y2="100" stroke="oklch(0.55 0.01 255 / 0.18)" strokeWidth="0.5"/>
          <line x1="100" y1="20" x2="100" y2="180" stroke="oklch(0.55 0.01 255 / 0.18)" strokeWidth="0.5"/>
          {/* diagonals — Mid/Side */}
          <line x1="44" y1="44" x2="156" y2="156" stroke="oklch(0.6 0.05 250 / 0.20)" strokeWidth="0.5" strokeDasharray="2 3"/>
          <line x1="156" y1="44" x2="44" y2="156" stroke="oklch(0.6 0.05 250 / 0.20)" strokeWidth="0.5" strokeDasharray="2 3"/>
          {/* labels */}
          <text x="100" y="15" textAnchor="middle" className="axis-tick">+M</text>
          <text x="100" y="195" textAnchor="middle" className="axis-tick">−M</text>
          <text x="14" y="103" className="axis-tick">−S</text>
          <text x="186" y="103" textAnchor="end" className="axis-tick">+S</text>
        </svg>
        <div className="empty-state">
          <Icon.MicOff/>
          <h4>Kein Stereo-Signal</h4>
          <p>Stereo-Mikrofon in Einstellungen aktivieren</p>
        </div>
        <div className="readout">
          <div className="readout-row"><span>L</span><span>−∞ dB</span></div>
          <div className="readout-row"><span>R</span><span>−∞ dB</span></div>
          <div className="readout-row"><span>φ</span><span>—</span></div>
        </div>
      </div>
    </Widget>
  );
}

/* ---------- LAB (Spektralanalyse-Labor) ---------- */
function ScreenLab() {
  const [tab, setTab] = useState("Parameter");
  const [size, setSize] = useState(2048);
  const [win, setWin] = useState("Blackman-Harris");
  const [overlap, setOverlap] = useState(87);
  const sizes = [512, 1024, 2048, 4096, 8192, 16384];

  return (
    <Widget title="FFT-Konfiguration" icon="Atom" meta={<><b>{size} · {win}</b></>}>
      <div className="tabs">
        {["Parameter","Fenster","Auflösung"].map(t => (
          <button key={t} className="tab" aria-current={t === tab} onClick={() => setTab(t)}>
            {t === "Parameter" && <Icon.Sliders/>}
            {t === "Fenster" && <Icon.Wave/>}
            {t === "Auflösung" && <Icon.Atom/>}
            {t}
          </button>
        ))}
      </div>

      {tab === "Parameter" && (
        <>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <div className="widget-title"><Icon.Hash/><span>Blockgröße</span></div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--fg)" }}>{size.toLocaleString("de")}</div>
          </div>
          <div className="chip-strip">
            {sizes.map(s => (
              <button key={s} className="chip" aria-current={s === size} onClick={() => setSize(s)}>{s}</button>
            ))}
          </div>

          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 4 }}>
            <div className="widget-title"><Icon.Wave/><span>Fensterfunktion</span></div>
          </div>
          <div className="segmented">
            {["Hann","Hamming","Blackman","B-Harris","Flat-top"].map(w => (
              <button key={w} aria-current={w === "B-Harris" && win.startsWith("Blackman")} onClick={() => setWin(w)}>{w}</button>
            ))}
          </div>

          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 4 }}>
            <div className="widget-title"><Icon.Layers/><span>Overlap</span></div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--fg)" }}>{overlap}%</div>
          </div>
          <div className="slider">
            <div className="slider-track"/>
            <div className="slider-fill" style={{ width: `${overlap}%`, background: "linear-gradient(90deg, oklch(0.7 0.18 60 / 0.4), oklch(0.78 0.18 60))" }}/>
            <div className="slider-thumb" style={{ left: `${overlap}%` }}/>
          </div>

          <div className="row" style={{ gap: 8, marginTop: 6 }}>
            <div className="metric"><div className="metric-val">21.5<span className="unit">Hz</span></div><div className="metric-label">Δf</div></div>
            <div className="metric"><div className="metric-val">46<span className="unit">ms</span></div><div className="metric-label">Δt</div></div>
            <div className="metric"><div className="metric-val">1024</div><div className="metric-label">Bins</div></div>
          </div>
        </>
      )}

      {tab === "Fenster" && (
        <div className="canvas" style={{ padding: 16, height: 220, display: "grid", placeItems: "center" }}>
          <svg viewBox="0 0 200 100" width="100%" height="100%">
            <path d="M 0 95 Q 100 -10 200 95" stroke="var(--accent)" fill="none" strokeWidth="1.4"/>
            <path d="M 0 95 Q 100 -10 200 95 L 200 100 L 0 100 Z" fill="var(--accent)" opacity="0.18"/>
            <text x="100" y="40" textAnchor="middle" className="axis-tick">{win}</text>
          </svg>
        </div>
      )}

      {tab === "Auflösung" && (
        <div className="canvas" style={{ padding: 14, display: "flex", flexDirection: "column", gap: 10 }}>
          <div className="canvas-label">Frequenz-Zeit-Trade-off</div>
          <div style={{ display: "flex", gap: 6 }}>
            <div className="metric"><div className="metric-val">{(size/44.1).toFixed(0)}<span className="unit">ms</span></div><div className="metric-label">Fensterlänge</div></div>
            <div className="metric"><div className="metric-val">{(44100/size).toFixed(1)}<span className="unit">Hz</span></div><div className="metric-label">Bin-Breite</div></div>
          </div>
          <div className="metric">
            <div className="metric-val">{(size/2).toLocaleString("de")}</div>
            <div className="metric-label">Nutzbare Bins</div>
          </div>
        </div>
      )}
    </Widget>
  );
}

/* ---------- OVERVIEW (composition view) ---------- */
function ScreenOverview() {
  const lafPts = useMemo(() => {
    const out = [];
    for (let i = 0; i < 140; i++) {
      const t = i / 139;
      const base = 30;
      const peak1 = 14 * Math.exp(-Math.pow((t - 0.30) * 8, 2));
      const peak2 = 18 * Math.exp(-Math.pow((t - 0.74) * 10, 2));
      const noise = (Math.sin(i * 0.7) * 0.5 + Math.sin(i * 2.3) * 0.3) * 1.2;
      out.push(base + peak1 + peak2 + noise);
    }
    return out;
  }, []);
  const last = lafPts[lafPts.length - 1];

  // Mini LAF chart
  const W = 280, H = 90;
  const yMin = 20, yMax = 80;
  const xs = lafPts.map((_, i) => (i / (lafPts.length - 1)) * W);
  const ys = lafPts.map(v => H - ((v - yMin) / (yMax - yMin)) * H);
  const linePath = xs.map((x, i) => `${i === 0 ? "M" : "L"} ${x.toFixed(2)} ${ys[i].toFixed(2)}`).join(" ");
  const fillPath = `${linePath} L ${W} ${H} L 0 ${H} Z`;

  return (
    <>
      {/* Big number — primary metric */}
      <section className="widget glass" data-screen-label="01 Overview · Hero">
        <div className="widget-head">
          <div className="widget-title"><Icon.Number/><span>LAF · A-bewertet</span></div>
          <div className="widget-meta"><b>Live · Slow</b></div>
        </div>
        <div className="canvas" style={{ padding: "16px 18px", display: "grid", gridTemplateColumns: "1fr auto", gap: 12, alignItems: "center" }}>
          <div>
            <div className="bignum" style={{ fontSize: 64, color: "var(--accent)" }}>{last.toFixed(1)}</div>
            <div className="bignum-unit" style={{ marginTop: 4 }}>dB(A)</div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6, alignItems: "flex-end" }}>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-dim)", letterSpacing: "0.1em" }}>
              <span style={{ color: "var(--fg-dim)" }}>MIN </span>
              <span style={{ color: "var(--fg)" }}>28.4</span>
            </div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-dim)", letterSpacing: "0.1em" }}>
              <span>MAX </span>
              <span style={{ color: "var(--fg)" }}>49.1</span>
            </div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-dim)", letterSpacing: "0.1em" }}>
              <span>Leq </span>
              <span style={{ color: "var(--fg)" }}>38.4</span>
            </div>
          </div>
        </div>
      </section>

      {/* LAF Verlauf — small */}
      <section className="widget glass" data-screen-label="01 Overview · LAF">
        <div className="widget-head">
          <div className="widget-title"><Icon.Wave/><span>Verlauf · 30 s</span></div>
          <div className="widget-meta"><b>20–80 dB</b></div>
        </div>
        <div className="canvas" style={{ height: H, position: "relative" }}>
          <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%" preserveAspectRatio="none">
            <defs>
              <linearGradient id="ovFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.35"/>
                <stop offset="100%" stopColor="var(--accent)" stopOpacity="0"/>
              </linearGradient>
            </defs>
            {[20, 40, 60, 80].map(g => {
              const y = H - ((g - yMin) / (yMax - yMin)) * H;
              return <line key={g} x1="0" x2={W} y1={y} y2={y} className="axis-line"/>;
            })}
            <path d={fillPath} fill="url(#ovFill)"/>
            <path d={linePath} stroke="var(--accent)" strokeWidth="1.4" fill="none"/>
          </svg>
        </div>
      </section>

      {/* Mini Spektrogramm */}
      <section className="widget glass" data-screen-label="01 Overview · Spektrum">
        <div className="widget-head">
          <div className="widget-title"><Icon.Falls/><span>Spektrogramm · STFT</span></div>
          <div className="widget-meta"><b>1024 bins</b></div>
        </div>
        <div className="row" style={{ alignItems: "stretch" }}>
          <FreqScaleY height={150}/>
          <div className="canvas" style={{ flex: 1, height: 150, position: "relative" }}>
            <SpectrogramCanvas cmap="viridis" width={280} height={150}/>
          </div>
        </div>
      </section>

      {/* Pegel-Meter mini */}
      <section className="widget glass" data-screen-label="01 Overview · Meter">
        <div className="widget-head">
          <div className="widget-title"><Icon.Sliders/><span>Stereo L · R</span></div>
          <div className="widget-meta"><b>48.3 · 55.1 dB</b></div>
        </div>
        <div className="canvas" style={{ padding: 12, display: "flex", flexDirection: "column", gap: 10 }}>
          {[
            { ch: "L", val: 48.3, pos: 0.48 },
            { ch: "R", val: 55.1, pos: 0.55 },
          ].map(m => (
            <div key={m.ch} style={{ display: "grid", gridTemplateColumns: "20px 1fr 64px", gap: 10, alignItems: "center" }}>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-muted)", letterSpacing: "0.1em" }}>{m.ch}</div>
              <div className="peak">
                <div className="peak-fill" style={{ width: `${m.pos * 100}%` }}/>
                {[0.2, 0.5, 0.85].map(t => <div key={t} className="peak-tick" style={{ left: `${t * 100}%` }}/>)}
              </div>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--fg)", fontVariantNumeric: "tabular-nums", textAlign: "right" }}>
                {m.val.toFixed(1)}<span style={{ fontSize: 9, color: "var(--fg-dim)", marginLeft: 3 }}>dB</span>
              </div>
            </div>
          ))}
        </div>
      </section>
    </>
  );
}

window.SpektoScreens = {
  ScreenOverview, ScreenSpectrogram, ScreenWaterfall, ScreenLevelTime, ScreenSpectrum,
  ScreenLevelMeter, ScreenSingle, ScreenTone, ScreenMasking, ScreenPhase, ScreenLab
};
})();
