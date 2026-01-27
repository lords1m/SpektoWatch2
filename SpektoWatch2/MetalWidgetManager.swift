import MetalKit

class MetalWidgetManager {
    static let shared = MetalWidgetManager()
    
    private(set) var sharedDevice: MTLDevice?
    private(set) var sharedCommandQueue: MTLCommandQueue?
    private var renderers: [UUID: MetalWidgetRenderer] = [:]
    
    private init() {
        sharedDevice = MTLCreateSystemDefaultDevice()
        if let device = sharedDevice {
            sharedCommandQueue = device.makeCommandQueue()
        }
    }
    
    func getRenderer(for widgetID: UUID, factory: (MTLDevice) -> MetalWidgetRenderer?) -> MetalWidgetRenderer? {
        if let renderer = renderers[widgetID] {
            return renderer
        }
        
        guard let device = sharedDevice else { return nil }
        
        if let newRenderer = factory(device) {
            renderers[widgetID] = newRenderer
            return newRenderer
        }
        
        return nil
    }
    
    func releaseRenderer(for widgetID: UUID) {
        renderers.removeValue(forKey: widgetID)
    }
}