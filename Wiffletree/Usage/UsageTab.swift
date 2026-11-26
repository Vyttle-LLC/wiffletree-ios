import SwiftUI
import WiffletreeDesignSystem

/// Account limits and the week's tokens on the host (mockup 7, usage half).
struct UsageTab: View {
    @Environment(LiveHost.self) private var host
    @State private var model: UsageModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    UsageScreen(model: model)
                        .task { await model.follow() }
                        .refreshable { await model.load() }
                } else {
                    Tidal.base
                }
            }
            .navigationTitle("Usage")
        }
        .onAppear {
            if model == nil { model = UsageModel(host: host) }
        }
    }
}

private struct UsageScreen: View {
    let model: UsageModel

    var body: some View {
        // Ages and reset times move on by the minute.
        TimelineView(.everyMinute) { context in
            TidalList {
                Section {
                    if let quotas = model.quotas {
                        ForEach(ProviderQuota.all(quotas, now: context.date)) { quota in
                            ProviderCard(quota: quota)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else {
                        loading
                    }
                } header: {
                    Text("Account limits · \(model.host.name)")
                }
                Section {
                    LabeledContent {
                        Text(model.weekTotal ?? "Unavailable")
                            .monospacedDigit()
                            .foregroundStyle(Tidal.subtle)
                    } label: {
                        Text("Tokens this week")
                            .foregroundStyle(Tidal.text)
                        if let detail = model.weekDetail { Text(detail) }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .labelStyle(.tight)
                                .foregroundStyle(Tidal.red)
                        }
                        Text("From each provider's own reports on the Mac, across all its projects. Claude reports only during live turns, so it can read Unavailable.")
                    }
                }
            }
            .listSectionSpacing(8)
        }
    }

    @ViewBuilder
    private var loading: some View {
        if model.error == nil {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        } else {
            Text("Unavailable").foregroundStyle(Tidal.subtle)
        }
    }
}

/// A provider's windows: what is left of each, with a bar that turns yellow, with a warning glyph,
/// when the limit runs low.
private struct ProviderCard: View {
    let quota: ProviderQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(quota.title)
                .font(.headline)
                .foregroundStyle(Tidal.text)
            ForEach(quota.lines) { line in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(line.title)
                        Spacer()
                        if line.isLow {
                            Label(line.leftText, systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(.tight)
                                .foregroundStyle(Tidal.yellow)
                        } else {
                            Text(line.leftText)
                                .foregroundStyle(line.percentLeft == nil ? Tidal.subtle : Tidal.text)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    QuotaBar(percentLeft: line.percentLeft, isLow: line.isLow)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                    if let detail = line.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Tidal.subtle)
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
            }
            if let note = quota.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Tidal.subtle)
                    .padding(.top, 10)
            }
        }
        .card()
    }
}

/// What is left of a window; empty when the provider has not reported it.
private struct QuotaBar: View {
    let percentLeft: Double?
    let isLow: Bool

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(isLow ? Tidal.yellow : Tidal.cyan)
                .frame(width: geometry.size.width * (percentLeft ?? 0) / 100)
        }
        .frame(height: 6)
        .background(Tidal.overlay, in: .capsule)
        .clipShape(.capsule)
    }
}
