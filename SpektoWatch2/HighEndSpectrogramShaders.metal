#include <metal_stdlib>
using namespace metal;

// ============================================================================
// MARK: - Vertex Output
// ============================================================================

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// ============================================================================
// MARK: - Vertex Shader (Hardcoded Fullscreen Quad — no vertex buffer needed)
// ============================================================================

vertex VertexOut spectrogramVertex(uint vid [[vertex_id]]) {
    // Triangle strip: BL, BR, TL, TR
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 uvs[4] = {
        float2(0.0, 1.0),   // Bottom-left
        float2(1.0, 1.0),   // Bottom-right
        float2(0.0, 0.0),   // Top-left
        float2(1.0, 0.0)    // Top-right
    };

    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

// ============================================================================
// MARK: - Live Spectrogram Fragment Shader
// ============================================================================
//
// - history texture (R32Float): pre-normalized [0,1] values written by CPU
// - colormap texture (RGBA8): 256×1 LUT baked once on init
//
// All dB conversion, noise gating, gamma, and normalization happen on CPU
// via vDSP before writing to the history texture.
//
// Narrow symmetric Gaussian blur in time direction (σ ≈ 0.9).
// Tightened from the previous σ ≈ 2.0 / ~6 px kernel: it now blends just
// enough across the central taps to anti-alias discrete column writes while
// preserving transients/onsets so the image reads sharp.
// ============================================================================

fragment half4 liveSpectrogramFragment(
    VertexOut in [[stage_in]],
    texture2d<float> history  [[texture(0)]],
    texture2d<float> colormap [[texture(1)]],
    constant float& scrollOffset [[buffer(0)]],
    // x = time start (0 = newest edge), y = time width, z = freq start (from
    // bottom/low), w = freq height. Defaults (0,1,0,1) = full, unzoomed view.
    constant float4& viewport [[buffer(1)]]
) {
    constexpr sampler hs(filter::linear, address::repeat);
    constexpr sampler cs(filter::linear, address::clamp_to_edge);

    // Map the screen position through the time/frequency window (pan + zoom).
    float winX = viewport.x + in.uv.x * viewport.y;
    // Ring buffer scroll: left = newest, right = oldest
    float texX = fract(scrollOffset - winX + 1.0);
    // Flip Y: low frequencies at bottom, high at top, within the freq window.
    float texY = clamp(viewport.z + (1.0 - in.uv.y) * viewport.w, 0.0, 1.0);

    float texWidth = float(history.get_width());
    float cx = texX * texWidth;
    float x0 = floor(cx);
    float xFrac = cx - x0;

    // Narrow 6-tap blur: only the central samples the kernel actually weights.
    float s2 = history.sample(hs, float2((x0 - 2.5) / texWidth, texY)).r;
    float s3 = history.sample(hs, float2((x0 - 1.5) / texWidth, texY)).r;
    float s4 = history.sample(hs, float2((x0 - 0.5) / texWidth, texY)).r;
    float s5 = history.sample(hs, float2((x0 + 0.5) / texWidth, texY)).r;
    float s6 = history.sample(hs, float2((x0 + 1.5) / texWidth, texY)).r;
    float s7 = history.sample(hs, float2((x0 + 2.5) / texWidth, texY)).r;
    float s8 = history.sample(hs, float2((x0 + 3.5) / texWidth, texY)).r;

    // Interpolate each tap to the exact fractional sub-column position
    float v2 = mix(s2, s3, xFrac);
    float v3 = mix(s3, s4, xFrac);
    float v4 = mix(s4, s5, xFrac);
    float v5 = mix(s5, s6, xFrac);
    float v6 = mix(s6, s7, xFrac);
    float v7 = mix(s7, s8, xFrac);

    // Narrow Gaussian kernel σ ≈ 0.9 (6 taps, sum = 1.0).
    //
    // Display-only: operates on already-normalized [0,1] DCT/Mel values that
    // were written into the ring texture by HighEndSpectrogramAdapter. This blur
    // is a visual anti-aliasing pass so discrete column writes are imperceptible
    // at varying scroll speeds — it is NOT a duplicate of SpectrogramProcessor's
    // IEC 61672 EMA (which runs on FFT dB values and does not feed this texture
    // in normal live operation). The two smoothing stages work on independent
    // data paths (R10: intentional parallel pipelines, not a stack).
    float t = v2 * 0.04 + v3 * 0.12 + v4 * 0.34
            + v5 * 0.34 + v6 * 0.12 + v7 * 0.04;

    return half4(colormap.sample(cs, float2(t, 0.5)));
}

// ============================================================================
// MARK: - Playback Spectrogram Fragment Shader
// ============================================================================
//
// Unlike the live path, the playback history texture now stores *raw dB SPL*
// values (R32Float). The dB→[0,1] mapping (calibration, dynamic range, gamma)
// happens here in the shader via the `PlaybackMapping` uniform, so changing the
// calibration, range, or weighting no longer requires re-normalizing and
// re-uploading the whole texture on the CPU.
//
// `viewport` is now a two-axis window:
//   x = time start, y = time width, z = freq start (from low freq), w = freq height.

struct PlaybackMapping {
    float minDBFS;      // bottom of the displayed dynamic range (dBFS)
    float maxDBFS;      // top of the displayed dynamic range (dBFS)
    float gamma;        // perceptual gamma applied after normalization
    float calibration;  // dB SPL → dBFS offset (dBFS = dBSPL - calibration)
};

fragment half4 playbackSpectrogramFragment(
    VertexOut in [[stage_in]],
    texture2d<float> history  [[texture(0)]],
    texture2d<float> colormap [[texture(1)]],
    constant float4& viewport [[buffer(0)]],          // time start/width, freq start/height
    constant PlaybackMapping& mapping [[buffer(1)]]
) {
    constexpr sampler hs(filter::linear, address::clamp_to_edge);
    constexpr sampler cs(filter::linear, address::clamp_to_edge);

    float texX = clamp(viewport.x + in.uv.x * viewport.y, 0.0, 1.0);
    // uv.y is 0 at the top of the view. (1 - uv.y) is the fraction up from the
    // bottom; map it through the frequency window so the bottom row of the
    // visible window sits at the bottom of the screen.
    float freqNorm = clamp(viewport.z + (1.0 - in.uv.y) * viewport.w, 0.0, 1.0);
    float texY = 1.0 - freqNorm;

    float texWidth = float(history.get_width());
    float cx = texX * texWidth;
    float x0 = floor(cx);
    float xFrac = cx - x0;

    float s2 = history.sample(hs, float2((x0 - 2.5) / texWidth, texY)).r;
    float s3 = history.sample(hs, float2((x0 - 1.5) / texWidth, texY)).r;
    float s4 = history.sample(hs, float2((x0 - 0.5) / texWidth, texY)).r;
    float s5 = history.sample(hs, float2((x0 + 0.5) / texWidth, texY)).r;
    float s6 = history.sample(hs, float2((x0 + 1.5) / texWidth, texY)).r;
    float s7 = history.sample(hs, float2((x0 + 2.5) / texWidth, texY)).r;
    float s8 = history.sample(hs, float2((x0 + 3.5) / texWidth, texY)).r;

    float v2 = mix(s2, s3, xFrac);
    float v3 = mix(s3, s4, xFrac);
    float v4 = mix(s4, s5, xFrac);
    float v5 = mix(s5, s6, xFrac);
    float v6 = mix(s6, s7, xFrac);
    float v7 = mix(s7, s8, xFrac);

    // Blurred raw dB SPL value at this texel (narrow σ ≈ 0.9 kernel).
    float dbSPL = v2 * 0.04 + v3 * 0.12 + v4 * 0.34
                + v5 * 0.34 + v6 * 0.12 + v7 * 0.04;

    float dbfs = dbSPL - mapping.calibration;
    float range = max(mapping.maxDBFS - mapping.minDBFS, 0.0001);
    float normalized = clamp((dbfs - mapping.minDBFS) / range, 0.0, 1.0);
    normalized = pow(normalized, mapping.gamma);

    return half4(colormap.sample(cs, float2(normalized, 0.5)));
}
