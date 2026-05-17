import WidgetKit
import SwiftUI

@main
struct SpektoWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        LevelCircularWidget()
        LevelRectangularWidget()
        LevelInlineWidget()
    }
}
