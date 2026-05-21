/* SpektoWatch — top-level App */
/* global React, ReactDOM, IOSDevice, SpektoUI, SpektoScreens, TweaksPanel,
          useTweaks, TweakSection, TweakRadio, TweakSelect, TweakColor, TweakToggle, TweakSlider */
(function() {
const { useState, useEffect, useRef } = React;
const { PRESETS, AppHeader, PresetRail, Transport, Icon } = window.SpektoUI;
const S = window.SpektoScreens;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "dark",
  "accent": "phosphor",
  "density": "default",
  "numerals": "mono",
  "colormap": "viridis",
  "canvasInLight": "light",
  "glassStrength": "default",
  "showReadouts": true
}/*EDITMODE-END*/;

const ACCENTS = {
  phosphor: { l: 0.84, c: 0.18, h: 145, label: "Phosphor" },
  amber:    { l: 0.82, c: 0.16, h: 80,  label: "Amber" },
  cyan:     { l: 0.82, c: 0.14, h: 220, label: "Cyan" },
  magenta:  { l: 0.78, c: 0.18, h: 340, label: "Magenta" },
  paper:    { l: 0.92, c: 0.005, h: 255, label: "Paper" },
};

function PresetScreen({ id, tweaks }) {
  switch (id) {
    case "overview":    return <S.ScreenOverview/>;
    case "spectrogram": return <S.ScreenSpectrogram cmap={tweaks.colormap}/>;
    case "waterfall":   return <S.ScreenWaterfall cmap={tweaks.colormap}/>;
    case "level-time":  return <S.ScreenLevelTime/>;
    case "spectrum":    return <S.ScreenSpectrum/>;
    case "level-meter": return <S.ScreenLevelMeter/>;
    case "single":      return <S.ScreenSingle/>;
    case "tone":        return <S.ScreenTone/>;
    case "masking":     return <S.ScreenMasking/>;
    case "phase":       return <S.ScreenPhase/>;
    case "lab":         return <S.ScreenLab/>;
    default: return null;
  }
}

function App() {
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [active, setActive] = useState("overview");
  const [editing, setEditing] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [recording, setRecording] = useState(false);
  const [tick, setTick] = useState("00:00.0");

  // Update CSS vars for theme/accent
  useEffect(() => {
    const root = document.querySelector(".app");
    if (!root) return;
    root.dataset.theme = tweaks.theme;
    root.dataset.density = tweaks.density;
    root.dataset.num = tweaks.numerals;
    root.dataset.canvas = tweaks.canvasInLight;

    const a = ACCENTS[tweaks.accent] || ACCENTS.phosphor;
    root.style.setProperty("--accent", `oklch(${a.l} ${a.c} ${a.h})`);
    root.style.setProperty("--accent-soft", `oklch(${a.l} ${a.c} ${a.h} / 0.18)`);
    root.style.setProperty("--accent-faint", `oklch(${a.l} ${a.c} ${a.h} / 0.08)`);
  }, [tweaks]);

  // Tick clock
  useEffect(() => {
    if (!playing && !recording) return;
    const start = Date.now();
    const t = setInterval(() => {
      const e = (Date.now() - start) / 1000;
      const mm = String(Math.floor(e / 60)).padStart(2, "0");
      const ss = String(Math.floor(e % 60)).padStart(2, "0");
      const tenths = String(Math.floor((e * 10) % 10));
      setTick(`${mm}:${ss}.${tenths}`);
    }, 100);
    return () => clearInterval(t);
  }, [playing, recording]);

  const activePreset = PRESETS.find(p => p.id === active) || PRESETS[0];

  return (
    <IOSDevice width={402} height={874} dark={tweaks.theme === "dark"}>
    <div className="app app-grain"
      data-theme={tweaks.theme}
      data-density={tweaks.density}
      data-num={tweaks.numerals}
      data-editing={editing ? "true" : "false"}
      style={{ position: "absolute", inset: 0 }}
    >
      <AppHeader
        presetName={activePreset.name}
        editing={editing}
        onSettings={() => {}}
        onLayouts={() => {}}
        onEdit={() => setEditing(e => !e)}
      />
      <PresetRail
        presets={PRESETS}
        activeId={active}
        onSelect={setActive}
      />

      <div className="app-scroll">
        <PresetScreen id={active} tweaks={tweaks}/>
        {editing && (
          <button className="add-widget-btn">
            <Icon.Plus/> Widget hinzufügen
          </button>
        )}
      </div>

      <Transport
        state={playing ? "playing" : "live"}
        playing={playing}
        recording={recording}
        cursor={(playing || recording) ? tick : "Bereit"}
        onPlay={() => setPlaying(p => !p)}
        onRec={() => setRecording(r => !r)}
      />

      <TweaksPanel title="Tweaks">
        <TweakSection title="Theme">
          <TweakRadio
            label="Modus"
            value={tweaks.theme}
            onChange={(v) => setTweak("theme", v)}
            options={[{ value: "dark", label: "Dunkel" }, { value: "light", label: "Hell" }]}
          />
          {tweaks.theme === "light" && (
            <TweakRadio
              label="Canvas"
              value={tweaks.canvasInLight}
              onChange={(v) => setTweak("canvasInLight", v)}
              options={[{ value: "light", label: "Hell" }, { value: "dark", label: "Dunkel" }]}
            />
          )}
          <TweakSelect
            label="Akzent"
            value={tweaks.accent}
            onChange={(v) => setTweak("accent", v)}
            options={Object.entries(ACCENTS).map(([k, v]) => ({ value: k, label: v.label }))}
          />
        </TweakSection>

        <TweakSection title="Layout">
          <TweakRadio
            label="Dichte"
            value={tweaks.density}
            onChange={(v) => setTweak("density", v)}
            options={[
              { value: "compact", label: "Kompakt" },
              { value: "default", label: "Standard" },
              { value: "airy",    label: "Luftig" },
            ]}
          />
          <TweakRadio
            label="Ziffern"
            value={tweaks.numerals}
            onChange={(v) => setTweak("numerals", v)}
            options={[
              { value: "mono", label: "Mono" },
              { value: "sans", label: "Sans" },
            ]}
          />
        </TweakSection>

        <TweakSection title="Visualisierung">
          <TweakSelect
            label="Colormap"
            value={tweaks.colormap}
            onChange={(v) => setTweak("colormap", v)}
            options={[
              { value: "viridis", label: "Viridis" },
              { value: "inferno", label: "Inferno" },
              { value: "magma",   label: "Magma" },
            ]}
          />
        </TweakSection>
      </TweaksPanel>
    </div>
    </IOSDevice>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App/>);
})();
