#include <metal_stdlib>
using namespace metal;

// ============================================================================
// MARK: - Vertex Shader
// ============================================================================

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut highEndSpectrogramVertexShader(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// ============================================================================
// MARK: - Color Mapping (Turbo Colormap)
// ============================================================================

// Turbo colormap - perceptually uniform, high contrast
// Based on Google's Turbo colormap (optimized for scientific visualization)
float3 turboColormap(float t) {
    // Clamp input to [0, 1]
    t = clamp(t, 0.0, 1.0);

    // Polynomial approximation of Turbo colormap
    const float3 c0 = float3(0.1140890109226559, 0.06288340699912215, 0.2248337216805064);
    const float3 c1 = float3(6.716419496985708, 3.182286745507602, 7.571581586103393);
    const float3 c2 = float3(-66.09402360453038, -4.9279827041226, -10.09439367561635);
    const float3 c3 = float3(228.7660791526501, 25.04986699771073, -91.54105330182436);
    const float3 c4 = float3(-334.8351565777451, -69.31749712757485, 288.5858850615712);
    const float3 c5 = float3(218.7637218434795, 67.52150567819112, -305.2045772184957);
    const float3 c6 = float3(-52.88903478218835, -21.54527364654712, 110.5174647748972);

    return c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * (c5 + t * c6)))));
}

// Alternative: Jet colormap (classic, high contrast)
float3 jetColormap(float t) {
    t = clamp(t, 0.0, 1.0);

    float r = clamp(1.5 - abs(4.0 * t - 3.0), 0.0, 1.0);
    float g = clamp(1.5 - abs(4.0 * t - 2.0), 0.0, 1.0);
    float b = clamp(1.5 - abs(4.0 * t - 1.0), 0.0, 1.0);

    return float3(r, g, b);
}

// Viridis colormap (perceptually uniform, accessible)
float3 viridisColormap(float t) {
    t = clamp(t, 0.0, 1.0);

    const float3 c0 = float3(0.267004, 0.004874, 0.329415);
    const float3 c1 = float3(0.127568, 1.932795, 0.196227);
    const float3 c2 = float3(-0.024239, -2.195853, -0.697154);
    const float3 c3 = float3(0.436538, 3.615417, 4.418481);
    const float3 c4 = float3(-0.531314, -3.346937, -6.315638);
    const float3 c5 = float3(0.271936, 1.443310, 3.363816);

    return c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * c5))));
}

// ============================================================================
// MARK: - dB Conversion & Normalization
// ============================================================================

// Convert linear magnitude to dB and normalize to [0, 1] range
// Input: linear magnitude (0 to inf)
// Output: normalized value (0 to 1) for color mapping
float magnitudeToNormalizedDB(float magnitude, float minDB, float maxDB) {
    const float epsilon = 1e-10;
    float db = 20.0 * log10(magnitude + epsilon);

    // Normalize to [0, 1] range
    float normalized = (db - minDB) / (maxDB - minDB);
    return clamp(normalized, 0.0, 1.0);
}

// ============================================================================
// MARK: - Noise Gate with Soft-Knee Compression
// ============================================================================

// Apply noise gate with smooth soft-knee transition
// noiseFloor: threshold below which signal is zeroed (e.g., -90 dB)
// kneeWidth: width of soft transition region (e.g., 10 dB)
float applyNoiseGate(float db, float noiseFloor, float kneeWidth) {
    if (db < noiseFloor) {
        return noiseFloor;  // Hard gate below floor
    }

    float kneeStart = noiseFloor;
    float kneeEnd = noiseFloor + kneeWidth;

    if (db < kneeEnd) {
        // Soft-knee region: smooth cubic interpolation
        float t = (db - kneeStart) / kneeWidth;
        float factor = t * t * (3.0 - 2.0 * t);  // Smoothstep
        return mix(noiseFloor, db, factor);
    }

    return db;  // No change above knee
}

// ============================================================================
// MARK: - Bilinear Texture Interpolation
// ============================================================================

// Sample texture with bilinear interpolation for smoother results
// This interpolates between 4 neighboring texels for anti-aliased appearance
float sampleBilinear(
    texture2d<float> tex,
    float2 texCoord,
    float2 texSize
) {
    // CRITICAL: Convert UV [0,1] to texel coordinates
    // The -0.5 offset centers the sampling between texels for proper interpolation
    float2 texelCoord = texCoord * texSize - 0.5;

    // Find the 4 surrounding texels
    float2 texelFloor = floor(texelCoord);
    float2 frac = texelCoord - texelFloor;

    // Calculate UV coordinates for the 4 texels
    // Add 0.5 to sample from texel centers
    float2 uv00 = (texelFloor + float2(0.5, 0.5)) / texSize;
    float2 uv10 = (texelFloor + float2(1.5, 0.5)) / texSize;
    float2 uv01 = (texelFloor + float2(0.5, 1.5)) / texSize;
    float2 uv11 = (texelFloor + float2(1.5, 1.5)) / texSize;

    // Wrap X coordinate for ring buffer (fmod for proper wrapping)
    // Y stays clamped to [0,1]
    uv00.x = fmod(uv00.x + 1.0, 1.0);
    uv10.x = fmod(uv10.x + 1.0, 1.0);
    uv01.x = fmod(uv01.x + 1.0, 1.0);
    uv11.x = fmod(uv11.x + 1.0, 1.0);

    // Clamp Y to valid range
    uv00.y = clamp(uv00.y, 0.0, 1.0);
    uv10.y = clamp(uv10.y, 0.0, 1.0);
    uv01.y = clamp(uv01.y, 0.0, 1.0);
    uv11.y = clamp(uv11.y, 0.0, 1.0);

    // Sample with nearest filter for explicit control
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float s00 = tex.sample(s, uv00).r;
    float s10 = tex.sample(s, uv10).r;
    float s01 = tex.sample(s, uv01).r;
    float s11 = tex.sample(s, uv11).r;

    // Bilinear interpolation (mix is GLSL lerp)
    float s0 = mix(s00, s10, frac.x);  // Interpolate horizontally
    float s1 = mix(s01, s11, frac.x);
    return mix(s0, s1, frac.y);         // Interpolate vertically
}

// ============================================================================
// MARK: - Logarithmic Frequency Mapping
// ============================================================================

// Map linear Y coordinate to logarithmic frequency bin
// Input: screenY (0 to 1, where 0 = top/high freq, 1 = bottom/low freq)
// Output: texture Y coordinate in logarithmic space
float linearToLogFrequency(float screenY, float minFreq, float maxFreq, float nyquist, int fftSize) {
    // Invert Y: screen top (0) = high freq, screen bottom (1) = low freq
    float t = 1.0 - screenY;

    // Logarithmic interpolation between minFreq and maxFreq
    float logMin = log2(minFreq);
    float logMax = log2(maxFreq);
    float frequency = exp2(logMin + t * (logMax - logMin));

    // Convert frequency to FFT bin index (normalized)
    float binIndex = (frequency / nyquist) * float(fftSize / 2);

    // Normalize to texture coordinate [0, 1]
    return binIndex / float(fftSize / 2);
}

// ============================================================================
// MARK: - Fragment Shader (Main Rendering)
// ============================================================================

struct ShaderParams {
    float minDB;           // e.g., -120.0
    float maxDB;           // e.g., -20.0
    float minFreq;         // e.g., 20.0 Hz
    float maxFreq;         // e.g., 20000.0 Hz
    float nyquist;         // e.g., 22050.0 Hz
    int fftSize;           // e.g., 8192 (with zero-padding)
    float scrollOffset;    // Ring buffer offset (0 to 1)
    int colormapType;      // 0 = Turbo, 1 = Jet, 2 = Viridis
    float horizontalBlur;  // Horizontal blur factor (deprecated - using bilinear now)
    float noiseFloor;      // Noise gate threshold in dB (e.g., -100.0)
    float kneeWidth;       // Soft-knee width in dB (e.g., 15.0)
    float gamma;           // Gamma correction factor (e.g., 0.5)
    int useInterpolation;  // 1 = bilinear interpolation, 0 = nearest neighbor
    int debugMode;         // 0=normal, 1=grayscale, 2=colormap test, 3=raw magnitude
};

fragment float4 highEndSpectrogramFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> spectrogramTexture [[texture(0)]],
    constant ShaderParams& params [[buffer(0)]]
) {
    // ========================================================================
    // 1. HORIZONTAL SCROLLING (Ring Buffer)
    // ========================================================================

    // Apply scroll offset for ring buffer
    // Screen X: 0 (left/old) to 1 (right/now)
    // Reverse for RTL display
    float screenX = 1.0 - in.texCoord.x;

    // Apply ring buffer offset
    float texX = fmod(screenX + params.scrollOffset, 1.0);

    // ========================================================================
    // 2. VERTICAL LOGARITHMIC FREQUENCY MAPPING
    // ========================================================================

    // Convert screen Y to logarithmic frequency space
    float texY = linearToLogFrequency(
        in.texCoord.y,
        params.minFreq,
        params.maxFreq,
        params.nyquist,
        params.fftSize
    );

    // ========================================================================
    // 3. SAMPLE TEXTURE (with optional bilinear interpolation)
    // ========================================================================

    float magnitude;
    if (params.useInterpolation == 1) {
        // Bilinear interpolation for smooth, anti-aliased appearance
        float2 texSize = float2(spectrogramTexture.get_width(), spectrogramTexture.get_height());
        float2 texCoord = float2(texX, texY);
        magnitude = sampleBilinear(spectrogramTexture, texCoord, texSize);
    } else {
        // Nearest neighbor (legacy)
        constexpr sampler s(address::clamp_to_edge, filter::nearest);
        magnitude = spectrogramTexture.sample(s, float2(texX, texY)).r;
    }

    // ========================================================================
    // 4. CONVERT TO dB WITH NOISE GATE
    // ========================================================================

    const float epsilon = 1e-10;
    float db = 20.0 * log10(magnitude + epsilon);

    // Apply noise gate with soft-knee compression
    db = applyNoiseGate(db, params.noiseFloor, params.kneeWidth);

    // Normalize to [0, 1] range
    float normalizedValue = (db - params.minDB) / (params.maxDB - params.minDB);
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);

    // ========================================================================
    // 5. APPLY PERCEPTUAL COMPRESSION
    // ========================================================================

    // CRITICAL FIX: Logarithmic compression to spread out lower values
    // This prevents everything from being red/orange
    // Maps [0,1] → [0,1] but with more emphasis on lower values
    normalizedValue = log10(1.0 + 9.0 * normalizedValue) / log10(10.0);

    // Then apply gamma correction for fine-tuning
    // Gamma < 1.0 emphasizes quiet signals (better detail in low-energy regions)
    // Gamma > 1.0 emphasizes loud signals
    normalizedValue = pow(normalizedValue, params.gamma);

    // ========================================================================
    // 6. DEBUG MODES (for diagnostics)
    // ========================================================================

    #ifdef DEBUG_ENABLED
    if (params.debugMode == 1) {
        // Grayscale: Show normalized value directly
        return float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
    } else if (params.debugMode == 2) {
        // Colormap test: Horizontal gradient from 0 to 1
        float testValue = in.texCoord.x;
        return float4(turboColormap(testValue), 1.0);
    } else if (params.debugMode == 3) {
        // Raw magnitude (scaled for visibility)
        float rawVis = clamp(magnitude * 100.0, 0.0, 1.0);
        return float4(rawVis, rawVis, rawVis, 1.0);
    }
    #endif

    // ========================================================================
    // 7. APPLY COLORMAP
    // ========================================================================

    float3 color;
    if (params.colormapType == 0) {
        color = turboColormap(normalizedValue);
    } else if (params.colormapType == 1) {
        color = jetColormap(normalizedValue);
    } else {
        color = viridisColormap(normalizedValue);
    }

    // ========================================================================
    // 8. ANTI-ALIASING AT RING BUFFER BOUNDARY
    // ========================================================================

    // Fade out near the write position to hide ring buffer seam
    float distanceToWriteHead = abs(texX - params.scrollOffset);
    if (distanceToWriteHead > 0.5) {
        distanceToWriteHead = 1.0 - distanceToWriteHead;  // Wrap around
    }

    // Fade width: ~1% of texture width
    float fadeWidth = 0.01;
    if (distanceToWriteHead < fadeWidth) {
        float fadeFactor = distanceToWriteHead / fadeWidth;
        color *= fadeFactor;  // Smooth fade to black
    }

    return float4(color, 1.0);
}

// ============================================================================
// MARK: - Compute Shader (Write FFT Data to Texture)
// ============================================================================

// Compute shader to write a single column of FFT data to the ring buffer
kernel void writeFFTColumn(
    texture2d<float, access::write> spectrogramTexture [[texture(0)]],
    constant float* fftMagnitudes [[buffer(0)]],          // Input FFT data
    constant int& columnIndex [[buffer(1)]],              // Which column to write
    constant int& fftSize [[buffer(2)]],                  // FFT size (e.g., 4096)
    uint2 gid [[thread_position_in_grid]]
) {
    // gid.y = frequency bin index (0 to texture height - 1)
    // gid.x should be 0 (we're writing a single column)

    int textureHeight = spectrogramTexture.get_height();

    // Only process the frequency bin for this thread
    if (gid.y < uint(textureHeight) && gid.x == 0) {
        // Map texture row to FFT bin (linear mapping - log mapping happens in fragment shader)
        int fftBinIndex = int(float(gid.y) / float(textureHeight) * float(fftSize / 2));
        fftBinIndex = min(fftBinIndex, fftSize / 2 - 1);

        // Get magnitude from FFT data
        float magnitude = fftMagnitudes[fftBinIndex];

        // Write to texture at (columnIndex, gid.y)
        uint2 writePos = uint2(columnIndex, gid.y);
        spectrogramTexture.write(float4(magnitude, 0.0, 0.0, 0.0), writePos);
    }
}

// ============================================================================
// MARK: - Alternative: Direct Write (without compute shader)
// ============================================================================

// If you prefer to write from CPU, use texture.replace() in Swift
// This is simpler but may be slightly less efficient for large textures

