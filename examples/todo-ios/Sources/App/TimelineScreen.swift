import Feedback
import SwiftUI

/// A `ScrollView` longer than a full-length capture, with a `LazyVStack` that pins its section
/// headers and footers. SwiftUI draws these itself, unlike a `List`'s headers, which are UIKit
/// supplementary views.
struct TimelineScreen: View {
    private static let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    private static let sessions = ["Warm-up", "Strength", "Intervals", "Accessories", "Core", "Balance", "Sprints", "Mobility", "Stretch", "Cool-down", "Recovery", "Notes"]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                ForEach(Self.days, id: \.self) { day in
                    Section {
                        // A lazy stack that sees an id twice draws only the first row, so ids include the day.
                        ForEach(Self.sessions.map { "\(day) \($0)" }, id: \.self) { title in
                            TimelineRow(title: title, minutes: title.count * 3)
                        }
                    } header: {
                        DayHeader(day: day, count: Self.sessions.count)
                    } footer: {
                        Text("\(Self.sessions.count) sessions planned")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(.bar)
                    }
                }
            }
        }
        .navigationTitle("Timeline")
        .feedback("TimelineScreen")
    }
}

private struct DayHeader: View {
    let day: String
    let count: Int

    var body: some View {
        HStack {
            Text(day).font(.headline)
            Spacer()
            Text("\(count) sessions").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .feedback(self)
    }
}

private struct TimelineRow: View {
    let title: String
    let minutes: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text("\(minutes) min").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().padding(.leading) }
        .feedback(self)
    }
}
