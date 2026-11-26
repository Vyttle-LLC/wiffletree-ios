import PhotosUI
import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// A project's conversation with its coordinator (mockup 4): ticket status pinned at the top,
/// the coordinator's Markdown full width, your messages as bubbles, agent traffic folded, and
/// the composer.
struct ProjectChatView: View {
    @Environment(LiveHost.self) private var host
    let projectID: String
    @State private var chat: ProjectChat?
    @State private var isShowingAgents = false

    var body: some View {
        Group {
            if let chat {
                ChatContent(chat: chat, isShowingAgents: $isShowingAgents)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tidal.base)
        .navigationTitle(chat?.overview?.project.name ?? "")
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if host.isDemo {
                ToolbarItem(placement: .topBarTrailing) { DemoTag(size: .small) }
            }
        }
        .sheet(isPresented: $isShowingAgents) { AgentsSheet(projectID: projectID) }
        .task { chat = chat ?? ProjectChat(host: host, projectID: projectID) }
        // Runs again once the snapshot names the coordinator, which a cold start may not yet.
        .task(id: [chat == nil ? "" : "chat", chat?.coordinator?.id ?? ""]) { await chat?.run() }
    }

    private var subtitle: String {
        guard let coordinator = chat?.coordinator else { return "" }
        return "Coordinator · \(coordinator.statusLabel.text.lowercased())"
    }
}

private struct ChatContent: View {
    @Environment(LiveHost.self) private var host
    @Bindable var chat: ProjectChat
    @Binding var isShowingAgents: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let overview = chat.overview, !overview.tickets.isEmpty {
                PinnedTickets(overview: overview)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(chat.entries) { entry in
                            EntryView(chat: chat, entry: entry, coordinatorName: chat.overview?.project.name ?? "Coordinator")
                        }
                        ForEach(chat.liveNarration) { step in
                            CoordinatorWords(name: chat.overview?.project.name ?? "Coordinator", time: nil, markdown: step.text)
                        }
                        Color.clear.frame(height: 1).id(bottom)
                    }
                    .padding(16)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: chat.messages.count) { proxy.scrollTo(bottom) }
                .onChange(of: chat.liveNarration.last?.text) { proxy.scrollTo(bottom) }
            }
            if let failure = chat.failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(Tidal.red)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            WorkingBar(projectID: chat.projectID, isShowingAgents: $isShowingAgents)
            Composer(chat: chat, isViewOnly: host.level == .viewOnly, isDemo: host.isDemo)
        }
    }

    private let bottom = "bottom"
}

private struct EntryView: View {
    @Environment(LiveHost.self) private var host
    let chat: ProjectChat
    let entry: ChatEntry
    let coordinatorName: String

    var body: some View {
        switch entry {
        case .reply(let message):
            CoordinatorWords(name: coordinatorName, time: message.date, markdown: message.body)
        case .human(let message):
            VStack(alignment: .trailing, spacing: 6) {
                if !message.attachments.isEmpty {
                    SentAttachments(chat: chat, attachments: message.attachments)
                }
                if !message.body.isEmpty {
                    Text(message.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(Tidal.onAccent)
                        .background(Tidal.accent, in: .rect(cornerRadius: 18))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 300, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .activity(let messages):
            ActivityLine(messages: messages, names: names)
        }
    }

    private func names(_ message: Message) -> String {
        guard let sender = message.sender, message.kind == .agent else { return "Wiffletree" }
        let name = host.snapshot?.sessions.first { $0.id == sender }?.name ?? "An agent"
        // "Reviewer · Correctness" reads as "Reviewer" in the folded line.
        return name.components(separatedBy: " · ").first ?? name
    }
}

/// A sent message's attachments: images as thumbnails, and any file the host cannot show as an
/// image as a paperclip line naming it.
private struct SentAttachments: View {
    let chat: ProjectChat
    let attachments: [Attachment]

    var body: some View {
        let images = attachments.filter { $0.image != nil && !chat.unreadable.contains($0.path) }
        let files = attachments.filter { !images.contains($0) }
        VStack(alignment: .trailing, spacing: 6) {
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(images, id: \.path) { attachment in
                        SentThumbnail(image: chat.thumbnails[attachment.path], name: attachment.name)
                            .task { await chat.loadThumbnail(of: attachment) }
                    }
                }
            }
            if !files.isEmpty {
                Label(files.map(\.name).joined(separator: ", "), systemImage: "paperclip")
                    .font(.footnote)
                    .foregroundStyle(Tidal.subtle)
                    .lineLimit(2)
            }
        }
    }
}

private struct SentThumbnail: View {
    let image: UIImage?
    let name: String

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Tidal.overlay.overlay(ProgressView())
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isImage)
    }
}

/// The coordinator's words: a small avatar with its name and time, then full-width Markdown.
private struct CoordinatorWords: View {
    let name: String
    /// Nil while the turn still runs.
    let time: Date?
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tidal.onAccent)
                    .frame(width: 20, height: 20)
                    .background(Tidal.focus, in: .circle)
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Tidal.text)
                if let time {
                    Text(time, format: .dateTime.hour().minute()).font(.footnote).foregroundStyle(Tidal.muted)
                } else {
                    Text("working…").font(.footnote).foregroundStyle(Tidal.muted)
                }
            }
            .accessibilityElement(children: .combine)
            MarkdownText(source: markdown)
                .foregroundStyle(Tidal.text)
        }
    }
}

/// One burst of agent messages and notices, folded to a line that expands to show them.
private struct ActivityLine: View {
    let messages: [Message]
    let names: (Message) -> String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Text(summary).lineLimit(1)
                    Spacer(minLength: 8)
                    if let last = messages.last {
                        Text(last.date, format: .dateTime.hour().minute()).monospacedDigit()
                    }
                }
                .font(.footnote)
                .foregroundStyle(Tidal.subtle)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Tidal.overlay, in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the messages" : "Shows the messages")
            if isExpanded {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(names(message)).font(.footnote.weight(.semibold)).foregroundStyle(Tidal.subtle)
                        MarkdownText(source: message.body).font(.subheadline).foregroundStyle(Tidal.text)
                    }
                    .padding(.leading, 12)
                }
            }
        }
    }

    /// Such as "2 agent messages, 1 notice · Implementer, Reviewer".
    private var summary: String {
        let agents = messages.filter { $0.kind == .agent }
        let notices = messages.count - agents.count
        var counts: [String] = []
        if !agents.isEmpty { counts.append(agents.count == 1 ? "1 agent message" : "\(agents.count) agent messages") }
        if notices > 0 { counts.append(notices == 1 ? "1 notice" : "\(notices) notices") }
        var senders: [String] = []
        for name in agents.map(names) where !senders.contains(name) { senders.append(name) }
        let line = counts.joined(separator: ", ")
        return senders.isEmpty ? line : "\(line) · \(senders.joined(separator: ", "))"
    }
}

/// Ticket status pinned above the conversation, as on the desktop; it expands to every ticket.
private struct PinnedTickets: View {
    let overview: ProjectOverview
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(overview.phase).font(.subheadline.weight(.semibold)).foregroundStyle(Tidal.text)
                        Spacer()
                        Text("\(overview.accepted) of \(overview.tickets.count) accepted")
                            .font(.footnote)
                            .foregroundStyle(Tidal.subtle)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Tidal.muted)
                    }
                    TicketProgressBar(overview: overview)
                    if !isExpanded, let active = overview.activeTicket {
                        Text(active.progressLine).font(.footnote).foregroundStyle(Tidal.subtle).lineLimit(1)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the tickets" : "Lists the tickets")
            if isExpanded {
                ForEach(overview.tickets) { ticket in
                    NavigationLink(value: ProjectRoute.ticket(id: ticket.id)) {
                        HStack {
                            Text(ticket.title).font(.subheadline).foregroundStyle(Tidal.text).lineLimit(1)
                            Spacer()
                            let label = ticket.shortStateLabel
                            Chip(label.text, tone: label.tone)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Tidal.surface, in: .rect(cornerRadius: 14))
    }
}

/// "2 agents working on 2 tickets", with the Agents sheet.
private struct WorkingBar: View {
    @Environment(LiveHost.self) private var host
    let projectID: String
    @Binding var isShowingAgents: Bool

    var body: some View {
        let working = host.snapshot?.workingAgents.filter { $0.projectID == projectID && $0.role != .projectOrchestrator } ?? []
        if !working.isEmpty {
            let tickets = Set(working.compactMap { host.snapshot?.runtime(of: $0.id)?.ticketID }).count
            HStack {
                Label(
                    "\(working.count == 1 ? "1 agent" : "\(working.count) agents") working on \(tickets == 1 ? "1 ticket" : "\(tickets) tickets")",
                    systemImage: "circle.dotted.circle"
                )
                .labelStyle(.tight)
                .foregroundStyle(Tidal.cyan)
                Spacer()
                Button("Agents") { isShowingAgents = true }
                    .fontWeight(.semibold)
                    .tint(Tidal.accent)
            }
            .font(.footnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Tidal.tintCyan)
        }
    }
}

/// The reply field with photos, dictation and send. Send is dimmed until there is text or a
/// photo; the + is there only when the host takes photos from this iPhone.
private struct Composer: View {
    @Bindable var chat: ProjectChat
    let isViewOnly: Bool
    let isDemo: Bool
    @State private var dictation = Dictation()
    @State private var isChoosingPhotos = false
    @State private var isTakingPhoto = false
    @State private var chosen: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 6) {
            if let failure = chat.sendFailure {
                SendFailure(text: failure) {
                    dictation.cancel()
                    Task { await chat.send() }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                if chat.canAttach {
                    attachMenu
                }
                field
                buttons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Tidal.base)
        .alert("Dictation", isPresented: Binding(get: { dictation.problem != nil }, set: { if !$0 { dictation.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dictation.problem ?? "")
        }
        .photosPicker(isPresented: $isChoosingPhotos, selection: $chosen, maxSelectionCount: 10, matching: .images)
        .onChange(of: chosen) { _, items in
            guard !items.isEmpty else { return }
            chosen = []
            Task { await attach(items) }
        }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { image in
                if let photo = Photo(image: image) { chat.attach(photo) }
            }
            .ignoresSafeArea()
        }
        .onDisappear { dictation.cancel() }
    }

    private var attachMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button("Take photo", systemImage: "camera") { isTakingPhoto = true }
            }
            Button("Choose photos", systemImage: "photo.on.rectangle") { isChoosingPhotos = true }
        } label: {
            RoundIcon(systemImage: "plus", filled: false)
        }
        .disabled(chat.isSending)
        .accessibilityLabel("Attach photos")
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !chat.photos.isEmpty {
                ComposerPhotos(chat: chat)
            }
            if let progress = chat.uploadProgress {
                ProgressView(value: progress)
                    .tint(Tidal.accent)
                    .accessibilityLabel("Uploading photos")
            }
            TextField(placeholder, text: $chat.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .disabled(isViewOnly)
            if dictation.isListening {
                Waveform(levels: dictation.levels)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Tidal.surface, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Tidal.edge, lineWidth: 1))
    }

    @ViewBuilder private var buttons: some View {
        RoundButton(
            systemImage: dictation.isListening ? "stop.fill" : "mic.fill",
            filled: dictation.isListening,
            label: dictation.isListening ? "Stop dictating" : "Dictate"
        ) {
            if dictation.isListening {
                dictation.stop()
            } else {
                let before = chat.draft
                Task {
                    await dictation.start { heard in
                        chat.draft = before.isEmpty ? heard : "\(before) \(heard)"
                    }
                }
            }
        }
        .disabled(isViewOnly)

        RoundButton(systemImage: "arrow.up", filled: chat.canSend, label: "Send") {
            dictation.cancel()
            Task { await chat.send() }
        }
        .disabled(!chat.canSend || isViewOnly)
    }

    /// Converts each chosen photo off the main actor, keeping the order chosen.
    private func attach(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let photo = await Task.detached { Photo(data: data) }.value
            if let photo { chat.attach(photo) }
        }
    }

    private var placeholder: String {
        if isViewOnly { return "View only: reply on your Mac" }
        return isDemo ? "Reply to the demo coordinator" : "Reply to your coordinator"
    }
}

/// The chosen photos above the text field, each with a remove ×.
private struct ComposerPhotos: View {
    let chat: ProjectChat

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chat.photos) { photo in
                    Image(uiImage: photo.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                        .accessibilityLabel(photo.upload.name)
                        .overlay(alignment: .topTrailing) {
                            if !chat.isSending {
                                Button { withAnimation(.snappy) { chat.remove(photo.id) } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                                .accessibilityLabel("Remove \(photo.upload.name)")
                            }
                        }
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
    }
}

/// Why the last send failed, with a retry that resumes it.
private struct SendFailure: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(text, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Tidal.red)
            Spacer(minLength: 8)
            Button("Retry", action: retry)
                .font(.footnote.weight(.semibold))
                .tint(Tidal.accent)
        }
        .padding(.horizontal, 4)
    }
}

private struct RoundButton: View {
    let systemImage: String
    let filled: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundIcon(systemImage: systemImage, filled: filled)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct RoundIcon: View {
    let systemImage: String
    let filled: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(filled ? Tidal.onAccent : Tidal.accent)
            .frame(width: 38, height: 38)
            .background(filled ? Tidal.accent : Tidal.tintAccent, in: .circle)
    }
}

/// The live input level while dictating.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Tidal.accent)
                    .frame(width: 3, height: 4 + CGFloat(levels[index]) * 16)
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

extension Message {
    var date: Date { Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000) }
}
