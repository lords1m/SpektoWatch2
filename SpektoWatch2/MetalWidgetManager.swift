import MetalKit

/// Process-wide holder for the shared Metal device.
///
/// Historical note: this class also exposed a `renderers: [UUID: MetalWidgetRenderer]`
/// cache and `getRenderer(for:factory:)` / `releaseRenderer(for:)` methods,
/// plus `MetalWidgetRenderer` as a protocol type. None of those were called
/// from anywhere in the project — the renderer cache was scaffolding for a
/// widget abstraction (`AudioWidget` / `MetalAudioWidget` / `MetalWidgetRenderer`)
/// that no concrete widget ever conformed to. Removed in M6 task-9 along
/// with `AudioWidget.swift`. Only `sharedDevice` survives — it's the single
/// `MTLDevice` reference passed to every Metal-backed widget initializer.
class MetalWidgetManager {
    static let shared = MetalWidgetManager()

    private(set) var sharedDevice: MTLDevice?

    private init() {
        sharedDevice = MTLCreateSystemDefaultDevice()
    }
}
