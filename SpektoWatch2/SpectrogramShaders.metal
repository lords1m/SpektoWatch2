#include <metal_stdlib>
using namespace metal;

// Vertex structure for full-screen quad
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Vertex shader - simple passthrough for full-screen quad
vertex VertexOut spectrogramVertexShader(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// Smooth colormap: Black → Blue → Cyan → Green → Yellow → Red
float3 spectrogramColormap(float value) {
    // Logarithmic scaling for better dynamic range
    value = log10(max(value, 0.001) + 1.0) / log10(2.0);
    
    // Clamp value to [0, 1]
    value = clamp(value, 0.0, 1.0);
    
    float3 color;
    
    if (value < 0.05) {
        // Very low: pure black (noise floor)
        color = float3(0.0, 0.0, 0.0);
    } else if (value < 0.2) {
        // Low: black to dark blue
        float t = (value - 0.05) / 0.15;
        color = float3(0.0, 0.0, 0.3 + t * 0.7);
    } else if (value < 0.4) {
        // Medium-low: blue to cyan
        float t = (value - 0.2) / 0.2;
        color = float3(0.0, t, 1.0);
    } else if (value < 0.6) {
        // Medium: cyan to green
        float t = (value - 0.4) / 0.2;
        color = float3(0.0, 1.0, 1.0 - t);
    } else if (value < 0.8) {
        // Medium-high: green to yellow
        float t = (value - 0.6) / 0.2;
        color = float3(t, 1.0, 0.0);
    } else {
        // Very high: yellow to red
        float t = (value - 0.8) / 0.2;
        color = float3(1.0, 1.0 - t, 0.0);
    }
    
    return color;
}

// Bilinear interpolation for smooth texture sampling
float bilinearInterpolate(texture2d<float> tex, sampler s, float2 uv, float2 texSize) {
    // Convert UV to pixel coordinates
    float2 pixelCoord = uv * texSize - 0.5;
    float2 floorCoord = floor(pixelCoord);
    float2 fractCoord = pixelCoord - floorCoord;
    
    // Sample 4 neighboring pixels
    float2 uv00 = (floorCoord + float2(0.0, 0.0)) / texSize;
    float2 uv10 = (floorCoord + float2(1.0, 0.0)) / texSize;
    float2 uv01 = (floorCoord + float2(0.0, 1.0)) / texSize;
    float2 uv11 = (floorCoord + float2(1.0, 1.0)) / texSize;
    
    float val00 = tex.sample(s, uv00).r;
    float val10 = tex.sample(s, uv10).r;
    float val01 = tex.sample(s, uv01).r;
    float val11 = tex.sample(s, uv11).r;
    
    // Bilinear interpolation
    float val0 = mix(val00, val10, fractCoord.x);
    float val1 = mix(val01, val11, fractCoord.x);
    float result = mix(val0, val1, fractCoord.y);
    
    return result;
}

// Fragment shader with bilinear interpolation
fragment float4 spectrogramFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> spectrogramTexture [[texture(0)]],
    constant float2& textureSize [[buffer(0)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );
    
    // Sample with bilinear interpolation
    float value = bilinearInterpolate(spectrogramTexture, textureSampler, in.texCoord, textureSize);
    
    // Apply colormap
    float3 color = spectrogramColormap(value);
    
    return float4(color, 1.0);
}

// Alternative: Direct sampling with Metal's built-in linear filtering
// RTL (Right-to-Left) version with horizontal stretching
// Supports dynamic scaling (first 60s) and scrolling (after 60s)
fragment float4 spectrogramFragmentShaderSimple(
    VertexOut in [[stage_in]],
    texture2d<float> spectrogramTexture [[texture(0)]],
    constant float& stretchFactor [[buffer(0)]],
    constant float4& displayParams [[buffer(1)]]  // (fillRatio, currentColumn, isScrolling, padding)
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    float fillRatio = displayParams.x;
    float currentColumn = displayParams.y;
    bool isScrolling = displayParams.z > 0.5;

    float textureWidth = float(spectrogramTexture.get_width());
    float pixelWidth = 1.0 / textureWidth;

    // Calculate texture coordinate based on mode
    float texX;

    if (isScrolling) {
        // SCROLLING MODE (after 60s): Ring buffer, newest on right
        // Map screen X (0 to 1) to texture coordinates with ring buffer wrap
        float normalizedCurrentCol = currentColumn / textureWidth;

        // RTL: x=0 (left/old) should map to (currentColumn + 1), x=1 (right/now) should map to currentColumn
        texX = fmod(normalizedCurrentCol + (1.0 - in.texCoord.x), 1.0);
    } else {
        // DYNAMIC SCALING MODE (first 60s): Stretch written data across full width
        // Only use the filled portion of the texture
        // RTL: x=0 (left/old) maps to texture x=0, x=1 (right/now) maps to fillRatio
        texX = (1.0 - in.texCoord.x) * fillRatio;
    }

    float2 baseTexCoord = float2(texX, in.texCoord.y);

    // Horizontal stretching for blur effect
    float value = 0.0;
    int sampleCount = max(1, int(stretchFactor));

    for (int i = 0; i < sampleCount; i++) {
        float offset = (float(i) - float(sampleCount) / 2.0) * pixelWidth * 0.5;
        float2 sampleCoord = baseTexCoord + float2(offset, 0.0);

        // Handle wrapping for scrolling mode
        if (isScrolling) {
            sampleCoord.x = fmod(sampleCoord.x + 1.0, 1.0);
        } else {
            sampleCoord.x = clamp(sampleCoord.x, 0.0, fillRatio);
        }

        value += spectrogramTexture.sample(textureSampler, sampleCoord).r;
    }
    value /= float(sampleCount);

    // Apply colormap
    float3 color = spectrogramColormap(value);

    return float4(color, 1.0);
}

// Logarithmic frequency scaling helper
float frequencyToLog(float frequency, float minFreq, float maxFreq) {
    float logMin = log2(minFreq);
    float logMax = log2(maxFreq);
    float logFreq = log2(frequency);
    return (logFreq - logMin) / (logMax - logMin);
}
