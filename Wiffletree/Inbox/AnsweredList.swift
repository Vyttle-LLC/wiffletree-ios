import SwiftUI
import WiffletreeDesignSystem

/// What was asked and what was decided, by day, newest first. Items decided before this iPhone
/// saw them come last, under Earlier.
struct AnsweredList: View {
    let history: [InboxModel.Decided]

    var body: some View {
        if history.isEmpty {
            ContentUnavailableView(
                "Nothing answered yet",
                systemImage: "checkmark.circle",
                description: Text("What you answer, approve or dismiss shows here.")
            )
        } else {
            TidalList {
                ForEach(days, id: \.title) { day in
                    Section(day.title) {
                        ForEach(day.decided) { decided in
                            HStack(spacing: 12) {
                                IconTile(decided.outcome == .dismissed ? "xmark" : decided.item.systemImage)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(decided.item.title)
                                        .foregroundStyle(Tidal.text)
                                    Text(decided.summary)
                                        .font(.footnote)
                                        .foregroundStyle(Tidal.subtle)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var days: [(title: String, decided: [InboxModel.Decided])] {
        var days: [(title: String, decided: [InboxModel.Decided])] = []
        for decided in history {
            let title = decided.at.map(Self.dayTitle) ?? "Earlier"
            if days.last?.title == title {
                days[days.count - 1].decided.append(decided)
            } else {
                days.append((title, [decided]))
            }
        }
        return days
    }

    private static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}
