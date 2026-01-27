import SwiftUI
import MetalKit

protocol AudioWidget: Identifiable {
    var id: UUID { get }
    var title: String { get }
    var widgetType: AudioWidgetType { get }
    var minSize: CGSize { get }
    var preferredSize: CGSize { get }
    var usesMetalRendering: Bool { get }
    
    func makeView(audioEngine: AudioEngine) -> AnyView
}

protocol MetalAudioWidget: AudioWidget {
    func createMetalRenderer(device: MTLDevice) -> MetalWidgetRenderer?
}

protocol MetalWidgetRenderer: AnyObject {
    var device: MTLDevice { get }
    var commandQueue: MTLCommandQueue? { get }
    var viewportSize: CGSize { get set }
    
    func update(audioData: [Float])
    func draw(in view: MTKView)
}