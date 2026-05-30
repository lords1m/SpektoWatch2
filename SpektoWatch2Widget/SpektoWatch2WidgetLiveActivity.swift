//
//  SpektoWatch2WidgetLiveActivity.swift
//  SpektoWatch2Widget
//
//  Renders the measurement Live Activity (Lock Screen + Dynamic Island)
//  driven by MeasurementLiveActivityController in the host app.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SpektoWatch2WidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeasurementActivityAttributes.self) { context in
            LockScreenView(context: context)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(Int(context.state.currentLevel)) dB(\(context.state.weighting))")
                            .font(.headline.monospacedDigit())
                    } icon: {
                        Image(systemName: "waveform")
                            .foregroundStyle(.green)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: 64)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Peak \(Int(context.state.peakLevel)) dB")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if context.state.isPaused {
                            Label("Pausiert", systemImage: "pause.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Label("Aufnahme", systemImage: "record.circle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "waveform")
                    .foregroundStyle(context.state.isPaused ? .orange : .green)
            } compactTrailing: {
                Text("\(Int(context.state.currentLevel))")
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.green)
            }
            .widgetURL(URL(string: "spektowatch://measurement"))
            .keylineTint(.green)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<MeasurementActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(context.attributes.sessionTitle, systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                Text(context.attributes.startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(context.state.currentLevel))")
                    .font(.system(size: 44, weight: .light).monospacedDigit())
                Text("dB(\(context.state.weighting))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PEAK")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(context.state.peakLevel)) dB")
                        .font(.headline.monospacedDigit())
                }
            }
            if context.state.isPaused {
                Label("Pausiert", systemImage: "pause.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

#Preview("Notification", as: .content, using: MeasurementActivityAttributes.preview) {
    SpektoWatch2WidgetLiveActivity()
} contentStates: {
    MeasurementActivityAttributes.ContentState.sample
}

private extension MeasurementActivityAttributes {
    static var preview: MeasurementActivityAttributes {
        MeasurementActivityAttributes(sessionTitle: "Messung", startedAt: .now)
    }
}

private extension MeasurementActivityAttributes.ContentState {
    static var sample: MeasurementActivityAttributes.ContentState {
        MeasurementActivityAttributes.ContentState(currentLevel: 62, peakLevel: 78, weighting: "A", isPaused: false)
    }
}
