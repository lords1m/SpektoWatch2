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
// 7-tap symmetric Gaussian blur in time direction (8 texel reads).
// Epoch width at hop=512, 44.1 kHz, 5 s span, 1050 px ≈ 2.4 px.
// The 7-column kernel spans ~6 px, blending ~2.5 epochs together
// so individual FFT frame boundaries become imperceptible.
// ============================================================================

fragment half4 liveSpectrogramFragment(
    VertexOut in [[stage_in]],
    texture2d<float> history  [[texture(0)]],
    texture2d<float> colormap [[texture(1)]],
    constant float& scrollOffset [[buffer(0)]]
) {
    constexpr sampler hs(filter::linear, address::repeat);
    constexpr sampler cs(filter::linear, address::clamp_to_edge);

    // Ring buffer scroll: left = newest, right = oldest
    float texX = fract(scrollOffset - in.uv.x + 1.0);
    // Flip Y: low frequencies at bottom, high at top
    float texY = 1.0 - in.uv.y;

    float texWidth = float(history.get_width());
    float cx = texX * texWidth;
    float x0 = floor(cx);
    float xFrac = cx - x0;

    // Sample 8 texel centres — enough for 7 bilinearly-interpolated taps.
    float s0 = history.sample(hs, float2((x0 - 2.5) / texWidth, texY)).r;
    float s1 = history.sample(hs, float2((x0 - 1.5) / texWidth, texY)).r;
    float s2 = history.sample(hs, float2((x0 - 0.5) / texWidth, texY)).r;
    float s3 = history.sample(hs, float2((x0 + 0.5) / texWidth, texY)).r;
    float s4 = history.sample(hs, float2((x0 + 1.5) / texWidth, texY)).r;
    float s5 = history.sample(hs, float2((x0 + 2.5) / texWidth, texY)).r;
    float s6 = history.sample(hs, float2((x0 + 3.5) / texWidth, texY)).r;
    float s7 = history.sample(hs, float2((x0 + 4.5) / texWidth, texY)).r;

    // Interpolate each tap to the exact fractional sub-column position.
    float v0 = mix(s0, s1, xFrac);   // column x0−2
    float v1 = mix(s1, s2, xFrac);   // column x0−1
    float v2 = mix(s2, s3, xFrac);   // column x0
    float v3 = mix(s3, s4, xFrac);   // column x0+1
    float v4 = mix(s4, s5, xFrac);   // column x0+2
    float v5 = mix(s5, s6, xFrac);   // column x0+3
    float v6 = mix(s6, s7, xFrac);   // column x0+4

    // Gaussian kernel σ ≈ 1.5:  [0.02, 0.08, 0.22, 0.36, 0.22, 0.08, 0.02]
    float t = v0 * 0.02 + v1 * 0.08 + v2 * 0.22 + v3 * 0.36
            + v4 * 0.22 + v5 * 0.08 + v6 * 0.02;

    return half4(colormap.sample(cs, float2(t, 0.5)));
}

// ============================================================================
// MARK: - Playback Spectrogram Fragment Shader
// ============================================================================

fragment half4 playbackSpectrogramFragment(
    VertexOut in [[stage_in]],
    texture2d<float> history  [[texture(0)]],
    texture2d<float> colormap [[texture(1)]],
    constant float2& viewport [[buffer(0)]]   // x = start, y = width
) {
    constexpr sampler hs(filter::linear, address::clamp_to_edge);
    constexpr sampler cs(filter::linear, address::clamp_to_edge);

    float texX = clamp(viewport.x + in.uv.x * viewport.y, 0.0, 1.0);
    float texY = 1.0 - in.uv.y;

    float t = history.sample(hs, float2(texX, texY)).r;
    return half4(colormap.sample(cs, float2(t, 0.5)));
}
