import SwiftUI
import WidgetKit

struct LevelCircularWidget: Widget {
    static let kind = "SpektoWatchLevelCircular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchComplicationProvider()) { entry in
            CircularComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SpektoWatch Level")
        .description("Zeigt den aktuellen Schallpegel.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LevelRectangularWidget: Widget {
    static let kind = "SpektoWatchLevelRectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchComplicationProvider()) { entry in
            RectangularComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SpektoWatch Level")
        .description("Zeigt den aktuellen Schallpegel mit Pegelanzeige.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LevelInlineWidget: Widget {
    static let kind = "SpektoWatchLevelInline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchComplicationProvider()) { entry in
            InlineComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SpektoWatch Level")
        .description("Kompakte Pegelanzeige.")
        .supportedFamilies([.accessoryInline])
    }
}
