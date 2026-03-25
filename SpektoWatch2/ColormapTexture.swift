import MetalKit

// ============================================================================
// MARK: - Colormap LUT Texture Builder
// ============================================================================

/// Builds 256×1 RGBA8 lookup textures for GPU-efficient colormap sampling.
/// Instead of computing colormaps per-pixel in the fragment shader (expensive polynomial),
/// we pre-bake them into a 1D texture and do a single texture lookup.
enum ColormapType: Int, CaseIterable, Identifiable {
    case turbo = 0
    case jet = 1
    case viridis = 2
    case grayscale = 3
    case inferno = 4
    case magma = 5
    case plasma = 6

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .turbo: return "Turbo"
        case .jet: return "Jet"
        case .viridis: return "Viridis"
        case .grayscale: return "Graustufen"
        case .inferno: return "Inferno"
        case .magma: return "Magma"
        case .plasma: return "Plasma"
        }
    }
}

enum ColormapTexture {

    /// Create a 256×1 RGBA8Unorm texture for the given colormap.
    static func makeTexture(device: MTLDevice, type: ColormapType) -> MTLTexture? {
        let width = 256
        var pixels = [UInt8](repeating: 0, count: width * 4)

        for i in 0..<width {
            let t = Float(i) / Float(width - 1)
            let (r, g, b) = color(for: type, t: t)
            pixels[i * 4 + 0] = UInt8(clamping: Int(r * 255.0 + 0.5))
            pixels[i * 4 + 1] = UInt8(clamping: Int(g * 255.0 + 0.5))
            pixels[i * 4 + 2] = UInt8(clamping: Int(b * 255.0 + 0.5))
            pixels[i * 4 + 3] = 255
        }

        let desc = MTLTextureDescriptor()
        desc.textureType = .type2D
        desc.pixelFormat = .rgba8Unorm
        desc.width = width
        desc.height = 1
        desc.usage = .shaderRead
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(
            region: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: width, height: 1, depth: 1)),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
        return texture
    }

    // MARK: - Helpers

    /// Horner evaluation for degree-6 polynomial (broken into steps for Swift type-checker)
    private static func horner6(_ t: Float, _ c0: SIMD3<Float>, _ c1: SIMD3<Float>, _ c2: SIMD3<Float>,
                                _ c3: SIMD3<Float>, _ c4: SIMD3<Float>, _ c5: SIMD3<Float>, _ c6: SIMD3<Float>) -> SIMD3<Float> {
        var r = c6 * t + c5
        r = r * t + c4
        r = r * t + c3
        r = r * t + c2
        r = r * t + c1
        r = r * t + c0
        return r
    }

    /// Horner evaluation for degree-5 polynomial
    private static func horner5(_ t: Float, _ c0: SIMD3<Float>, _ c1: SIMD3<Float>, _ c2: SIMD3<Float>,
                                _ c3: SIMD3<Float>, _ c4: SIMD3<Float>, _ c5: SIMD3<Float>) -> SIMD3<Float> {
        var r = c5 * t + c4
        r = r * t + c3
        r = r * t + c2
        r = r * t + c1
        r = r * t + c0
        return r
    }

    private static func clampRGB(_ c: SIMD3<Float>) -> (Float, Float, Float) {
        (max(0, min(1, c.x)), max(0, min(1, c.y)), max(0, min(1, c.z)))
    }

    // MARK: - Colormap Functions

    private static func color(for type: ColormapType, t: Float) -> (Float, Float, Float) {
        let t = max(0, min(1, t))
        switch type {
        case .turbo:     return turbo(t)
        case .jet:       return jet(t)
        case .viridis:   return viridis(t)
        case .grayscale: return (t, t, t)
        case .inferno:   return inferno(t)
        case .magma:     return magma(t)
        case .plasma:    return plasma(t)
        }
    }

    private static func turbo(_ t: Float) -> (Float, Float, Float) {
        let c0 = SIMD3<Float>(0.1140890109226559, 0.06288340699912215, 0.2248337216805064)
        let c1 = SIMD3<Float>(6.716419496985708, 3.182286745507602, 7.571581586103393)
        let c2 = SIMD3<Float>(-66.09402360453038, -4.9279827041226, -10.09439367561635)
        let c3 = SIMD3<Float>(228.7660791526501, 25.04986699771073, -91.54105330182436)
        let c4 = SIMD3<Float>(-334.8351565777451, -69.31749712757485, 288.5858850615712)
        let c5 = SIMD3<Float>(218.7637218434795, 67.52150567819112, -305.2045772184957)
        let c6 = SIMD3<Float>(-52.88903478218835, -21.54527364654712, 110.5174647748972)
        let c = horner6(t, c0, c1, c2, c3, c4, c5, c6)
        return clampRGB(c)
    }

    private static func jet(_ t: Float) -> (Float, Float, Float) {
        let r = max(0, min(1, 1.5 - abs(4.0 * t - 3.0)))
        let g = max(0, min(1, 1.5 - abs(4.0 * t - 2.0)))
        let b = max(0, min(1, 1.5 - abs(4.0 * t - 1.0)))
        return (r, g, b)
    }

    private static func viridis(_ t: Float) -> (Float, Float, Float) {
        let c = horner5(t,
            SIMD3<Float>(0.267004, 0.004874, 0.329415),
            SIMD3<Float>(0.127568, 1.932795, 0.196227),
            SIMD3<Float>(-0.024239, -2.195853, -0.697154),
            SIMD3<Float>(0.436538, 3.615417, 4.418481),
            SIMD3<Float>(-0.531314, -3.346937, -6.315638),
            SIMD3<Float>(0.271936, 1.443310, 3.363816))
        return clampRGB(c)
    }

    private static func inferno(_ t: Float) -> (Float, Float, Float) {
        let c = horner6(t,
            SIMD3<Float>(0.0002189403691192265, 0.001651004631001012, 0.01488457814098775),
            SIMD3<Float>(0.1065134194856116, 0.0563037668698395, 0.5840172024906974),
            SIMD3<Float>(11.60249308247187, -3.972853965665698, -15.9423941062914),
            SIMD3<Float>(-41.70399613139459, 17.43639888205313, 44.35414519872813),
            SIMD3<Float>(77.162935699427, -33.40235894210092, -81.80730925738993),
            SIMD3<Float>(-73.07006457692328, 32.62606426397723, 73.20951985803202),
            SIMD3<Float>(27.21020178251394, -12.24266895238568, -23.07032500287172))
        return clampRGB(c)
    }

    private static func magma(_ t: Float) -> (Float, Float, Float) {
        let c = horner6(t,
            SIMD3<Float>(0.0014861, 0.0004857, 0.0139810),
            SIMD3<Float>(0.1260442, 0.0742132, 0.6318928),
            SIMD3<Float>(8.6242950, -2.8441890, -13.941340),
            SIMD3<Float>(-27.668930, 12.447710, 36.838110),
            SIMD3<Float>(52.176130, -24.011050, -65.013610),
            SIMD3<Float>(-50.768520, 22.476270, 56.291470),
            SIMD3<Float>(18.655700, -7.6455300, -18.517010))
        return clampRGB(c)
    }

    private static func plasma(_ t: Float) -> (Float, Float, Float) {
        let c = horner6(t,
            SIMD3<Float>(0.0504700, 0.0298030, 0.5279800),
            SIMD3<Float>(2.0213900, -0.158415, -1.604100),
            SIMD3<Float>(-7.242200, 1.2435400, 4.4283200),
            SIMD3<Float>(18.067200, -2.230600, -7.7038600),
            SIMD3<Float>(-23.978300, 3.6205400, 7.9468600),
            SIMD3<Float>(16.197600, -2.985800, -4.7268200),
            SIMD3<Float>(-4.367700, 0.9531890, 0.9413970))
        return clampRGB(c)
    }
}
