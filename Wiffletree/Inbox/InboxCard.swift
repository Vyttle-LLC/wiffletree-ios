import SwiftUI
import WiffletreeDesignSystem

/// One open item: where it comes from, what it asks, and its actions. The glyph and words say
/// the kind, so the accent is only on the actions.
struct InboxCard: View {
    let item: InboxItem
    let model: InboxModel
    @State private var ownWords = ""

    private var isSending: Bool { model.sending.contains(item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("\(item.projectName) · \(item.kindTitle)", systemImage: item.systemImage)
                .labelStyle(.tight)
                .font(.footnote)
                .foregroundStyle(Tidal.subtle)
                .padding(.bottom, 6)
            Text(item.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Tidal.text)
                .padding(.bottom, 4)
            if let detail = item.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Tidal.subtle)
            }
            if model.canAnswer {
                actions
                    .padding(.top, 12)
                    .disabled(isSending)
                    .opacity(isSending ? 0.5 : 1)
            }
            if isSending {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Sending to \(model.host.name)…")
                }
                .font(.footnote)
                .foregroundStyle(Tidal.subtle)
                .padding(.top, 8)
            }
            if let error = model.errors[item.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .labelStyle(.tight)
                    .font(.footnote)
                    .foregroundStyle(Tidal.red)
                    .padding(.top, 8)
            }
        }
        .card()
    }

    @ViewBuilder
    private var actions: some View {
        switch item.kind {
        case .question:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.attention.options, id: \.self) { option in
                    Button(option) { Task { await model.answer(item, with: option) } }
                        .buttonStyle(OptionButtonStyle())
                }
                ownWordsField
            }
        case .merge(isProtected: true, let url):
            VStack(alignment: .leading, spacing: 6) {
                if let url {
                    Link("Open in GitHub", destination: url)
                        .buttonStyle(SmallButtonStyle(kind: .filled))
                }
                Text("It merges into a protected branch, so only you merge it, on GitHub.")
                    .font(.footnote)
                    .foregroundStyle(Tidal.subtle)
            }
        case .publish, .merge, .approval:
            HStack(spacing: 8) {
                Button("Deny") { Task { await model.deny(item) } }
                    .buttonStyle(SmallButtonStyle(kind: .gray))
                Button(item.approveTitle) { Task { await model.approve(item) } }
                    .buttonStyle(SmallButtonStyle(kind: .filled))
            }
        }
    }

    private var ownWordsField: some View {
        HStack(spacing: 8) {
            TextField(
                "Answer in your own words",
                text: $ownWords,
                prompt: Text("Answer in your own words…").foregroundStyle(Tidal.accent)
            )
                .font(.subheadline)
                .foregroundStyle(Tidal.text)
                .submitLabel(.send)
                .onSubmit(sendOwnWords)
            if !ownWords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Send", systemImage: "arrow.up.circle.fill", action: sendOwnWords)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(Tidal.accent)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private func sendOwnWords() {
        let words = ownWords
        Task { await model.answer(item, with: words) }
    }
}

/// A question's choice: the accent on its tint, full width.
private struct OptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(Tidal.accent)
            .background(Tidal.tintAccent, in: .rect(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The mockups' small capsule button, sharing its row equally.
private struct SmallButtonStyle: ButtonStyle {
    enum Kind { case filled, gray }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(kind == .filled ? Tidal.onAccent : Tidal.text)
            .background(kind == .filled ? Tidal.accent : Tidal.overlay, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
