import Foundation
import Combine

protocol AudioDataProvider: ObservableObject {
    var currentSpectrogramData: SpectrogramData? { get }
    var levelHistory: [Float] { get }
    var currentOctaveBands: [Float] { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    func play()
    func pause()
    func scrub(to time: TimeInterval)
}
