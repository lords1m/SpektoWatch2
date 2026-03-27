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
// Ultra-minimal: 2 texture samples per pixel.
// - history texture (R32Float): pre-normalized [0,1] values written by CPU
// - colormap texture (RGBA8): 256×1 LUT baked once on init
//
// All dB conversion, noise gating, gamma, and normalization happen on CPU
// via vDSP before writing to the history texture.
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

    // 3-tap temporal blur [0.2, 0.6, 0.2] to smooth column boundaries.
    // Each tap is bilinearly interpolated between its two surrounding texels
    // at the same fractional sub-column position, keeping the filter symmetric.
    float tm1 = history.sample(hs, float2((x0 - 0.5) / texWidth, texY)).r;
    float t0v  = history.sample(hs, float2((x0 + 0.5) / texWidth, texY)).r;
    float t1v  = history.sample(hs, float2((x0 + 1.5) / texWidth, texY)).r;
    float t2v  = history.sample(hs, float2((x0 + 2.5) / texWidth, texY)).r;

    float v_left  = mix(tm1, t0v, xFrac);
    float v_mid   = mix(t0v, t1v, xFrac);
    float v_right = mix(t1v, t2v, xFrac);

    float t = v_left * 0.2 + v_mid * 0.6 + v_right * 0.2;
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
