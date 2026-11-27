import SwiftUI
import WiffletreeDesignSystem

/// The host's questions and approvals (mockup 5): what needs you, and what was decided.
struct InboxTab: View {
    @Environment(LiveHost.self) private var host
    @State private var model: InboxModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    InboxScreen(model: model)
                } else {
                    Tidal.base
                }
            }
            .navigationTitle("Inbox")
        }
        .onAppear {
            if model == nil { model = InboxModel(host: host) }
        }
    }
}

private struct InboxScreen: View {
    enum Section: Hashable { case needsYou, answered }

    let model: InboxModel
    @State private var section = Section.needsYou

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner(host: model.host)
                .padding(.bottom, 4)
            Picker("Show", selection: $section) {
                Text("Needs you · \(model.open.count)").tag(Section.needsYou)
                Text("Answered").tag(Section.answered)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            switch section {
            case .needsYou: NeedsYouList(model: model)
            case .answered: AnsweredList(history: model.history)
            }
        }
        .background(Tidal.base)
    }
}

/// A card per open item, newest first. Only a question swipes to Dismiss.
private struct NeedsYouList: View {
    let model: InboxModel

    var body: some View {
        if model.host.snapshot == nil {
            ProgressView("Loading \(model.host.name)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.open.isEmpty {
            ContentUnavailableView(
                "Nothing needs you",
                systemImage: "tray",
                description: Text("Questions and approvals from \(model.host.name)'s coordinators land here.")
            )
        } else {
            List {
                if !model.canAnswer {
                    Text(model.host.level.explanation)
                        .font(.footnote)
                        .foregroundStyle(Tidal.subtle)
                        .listRowBackground(Color.clear)
                }
                ForEach(model.open) { item in
                    InboxCard(item: item, model: model)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if item.canDismiss && model.canAnswer {
                                Button("Dismiss", systemImage: "xmark") {
                                    Task { await model.dismiss(item) }
                                }
                                .tint(Tidal.subtle)
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
