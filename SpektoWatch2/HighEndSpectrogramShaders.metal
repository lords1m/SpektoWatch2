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

float3 turboColormap(float t) {
    t = clamp(t, 0.0, 1.0);
    const float3 c0 = float3(0.1140890109226559, 0.06288340699912215, 0.2248337216805064);
    const float3 c1 = float3(6.716419496985708, 3.182286745507602, 7.571581586103393);
    const float3 c2 = float3(-66.09402360453038, -4.9279827041226, -10.09439367561635);
    const float3 c3 = float3(228.7660791526501, 25.04986699771073, -91.54105330182436);
    const float3 c4 = float3(-334.8351565777451, -69.31749712757485, 288.5858850615712);
    const float3 c5 = float3(218.7637218434795, 67.52150567819112, -305.2045772184957);
    const float3 c6 = float3(-52.88903478218835, -21.54527364654712, 110.5174647748972);
    return c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * (c5 + t * c6)))));
}

float3 jetColormap(float t) {
    t = clamp(t, 0.0, 1.0);
    float r = clamp(1.5 - abs(4.0 * t - 3.0), 0.0, 1.0);
    float g = clamp(1.5 - abs(4.0 * t - 2.0), 0.0, 1.0);
    float b = clamp(1.5 - abs(4.0 * t - 1.0), 0.0, 1.0);
    return float3(r, g, b);
}

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
// MARK: - dB Conversion & Normalization (KORRIGIERT)
// ============================================================================

float magnitudeToNormalizedDB(float magnitude, float minDB, float maxDB) {
    const float epsilon = 1e-10;
    float db = 20.0 * log10(magnitude + epsilon);
    // KORREKTUR: Verwende 'db' statt 'magnitude' für Normalisierung
    float normalized = (db - minDB) / (maxDB - minDB);
    return clamp(normalized, 0.0, 1.0);
}

// ============================================================================
// MARK: - Noise Gate with Soft-Knee Compression
// ============================================================================

float applyNoiseGate(float db, float noiseFloor, float kneeWidth, float minDB) {
    if (db < noiseFloor) {
        return minDB;
    }
    
    float kneeStart = noiseFloor;
    float kneeEnd = noiseFloor + kneeWidth;
    
    if (db < kneeEnd) {
        float t = (db - kneeStart) / kneeWidth;
        float factor = t * t * (3.0 - 2.0 * t); // Smoothstep
        return mix(minDB, db, factor);
    }
    
    return db;
}

// ============================================================================
// MARK: - Bilinear Texture Interpolation
// ============================================================================

float sampleBilinear(
    texture2d<float> tex,
    float2 texCoord,
    float2 texSize
) {
    float2 texelCoord = texCoord * texSize - 0.5;
    float2 texelFloor = floor(texelCoord);
    float2 frac = texelCoord - texelFloor;
    
    float2 uv00 = (texelFloor + float2(0.5, 0.5)) / texSize;
    float2 uv10 = (texelFloor + float2(1.5, 0.5)) / texSize;
    float2 uv01 = (texelFloor + float2(0.5, 1.5)) / texSize;
    float2 uv11 = (texelFloor + float2(1.5, 1.5)) / texSize;
    
    uv00.x = fmod(uv00.x + 1.0, 1.0);
    uv10.x = fmod(uv10.x + 1.0, 1.0);
    uv01.x = fmod(uv01.x + 1.0, 1.0);
    uv11.x = fmod(uv11.x + 1.0, 1.0);
    
    uv00.y = clamp(uv00.y, 0.0, 1.0);
    uv10.y = clamp(uv10.y, 0.0, 1.0);
    uv01.y = clamp(uv01.y, 0.0, 1.0);
    uv11.y = clamp(uv11.y, 0.0, 1.0);
    
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    
    float s00 = tex.sample(s, uv00).r;
    float s10 = tex.sample(s, uv10).r;
    float s01 = tex.sample(s, uv01).r;
    float s11 = tex.sample(s, uv11).r;
    
    float s0 = mix(s00, s10, frac.x);
    float s1 = mix(s01, s11, frac.x);
    return mix(s0, s1, frac.y);
}

// ============================================================================
// MARK: - Logarithmic Frequency Mapping (KORRIGIERT)
// ============================================================================

float linearToLogFrequency(float screenY, float minFreq, float maxFreq, float nyquist, int fftSize) {
    float t = 1.0 - screenY;
    
    float logMin = log2(minFreq);
    float logMax = log2(maxFreq);
    float frequency = exp2(logMin + t * (logMax - logMin));
    
    float binIndex = (frequency / nyquist) * float(fftSize / 2);
    
    // KORREKTUR: Clamp hinzugefügt um ungültige Koordinaten zu vermeiden
    float normalized = binIndex / float(fftSize / 2);
    return clamp(normalized, 0.0, 1.0);
}

// ============================================================================
// MARK: - Fragment Shader (Main Rendering)
// ============================================================================

struct ShaderParams {
    float minDB;
    float maxDB;
    float minFreq;
    float maxFreq;
    float nyquist;
    int fftSize;
    float scrollOffset;
    int colormapType;
    float horizontalBlur;
    float noiseFloor;
    float kneeWidth;
    float gamma;
    int useInterpolation;
    int debugMode;
};

fragment float4 highEndSpectrogramFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> spectrogramTexture [[texture(0)]],
    constant ShaderParams& params [[buffer(0)]]
) {
    // 1. HORIZONTAL SCROLLING (Ring Buffer)
    float screenX = in.texCoord.x;
    float texX = fmod(params.scrollOffset - screenX + 1.0, 1.0);
    
    // 2. VERTIKALE KOORDINATE - DIREKT verwenden (keine Log-Transformation!)
    // KORREKTUR: Die Textur ist bereits logarithmisch organisiert
    float texY = in.texCoord.y;  // Direkt verwenden!
    
    // 3. SAMPLE TEXTURE
    float magnitude;
    if (params.useInterpolation == 1) {
        float2 texSize = float2(spectrogramTexture.get_width(), spectrogramTexture.get_height());
        float2 texCoord = float2(texX, texY);
        magnitude = sampleBilinear(spectrogramTexture, texCoord, texSize);
    } else {
        constexpr sampler s(address::clamp_to_edge, filter::nearest);
        magnitude = spectrogramTexture.sample(s, float2(texX, texY)).r;
    }
    
    // Rest bleibt gleich...
    const float epsilon = 1e-10;
    float db = 20.0 * log10(magnitude + epsilon);
    db = applyNoiseGate(db, params.noiseFloor, params.kneeWidth, params.minDB);
    
    float normalizedValue = (db - params.minDB) / (params.maxDB - params.minDB);
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);
    
    normalizedValue = log10(1.0 + 99.0 * normalizedValue) / log10(100.0);
    normalizedValue = pow(normalizedValue, params.gamma);
    
    float3 color;
    if (params.colormapType == 0) {
        color = turboColormap(normalizedValue);
    } else if (params.colormapType == 1) {
        color = jetColormap(normalizedValue);
    } else {
        color = viridisColormap(normalizedValue);
    }
    
    // Anti-Aliasing at ring buffer boundary
    float distanceToWriteHead = abs(texX - params.scrollOffset);
    if (distanceToWriteHead > 0.5) {
        distanceToWriteHead = 1.0 - distanceToWriteHead;
    }
    
    float fadeWidth = 0.01;
    if (distanceToWriteHead < fadeWidth) {
        float fadeFactor = distanceToWriteHead / fadeWidth;
        color *= fadeFactor;
    }
    
    return float4(color, 1.0);
}

// ============================================================================
// MARK: - Compute Shader (Write FFT Data to Texture)
// ============================================================================

kernel void writeFFTColumn(
    texture2d<float, access::write> spectrogramTexture [[texture(0)]],
    constant float* fftMagnitudes [[buffer(0)]],
    constant int& columnIndex [[buffer(1)]],
    constant int& fftSize [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    int textureHeight = spectrogramTexture.get_height();
    
    if (gid.y < uint(textureHeight) && gid.x == 0) {
        int fftBinIndex = int(float(gid.y) / float(textureHeight) * float(fftSize / 2));
        fftBinIndex = min(fftBinIndex, fftSize / 2 - 1);
        
        float magnitude = fftMagnitudes[fftBinIndex];
        
        uint2 writePos = uint2(columnIndex, gid.y);
        spectrogramTexture.write(float4(magnitude, 0.0, 0.0, 0.0), writePos);
    }
}
