import Foundation
import Observation
import WiffletreeKit

/// A row of the conversation: the human's message, the coordinator's reply, or one burst of
/// agent-to-agent traffic and notices folded into one line (design call 4).
enum ChatEntry: Identifiable {
    case human(Message)
    case reply(Message)
    case activity([Message])

    var id: String {
        switch self {
        case .human(let message), .reply(let message): message.id
        case .activity(let messages): "activity-\(messages[0].id)"
        }
    }

    /// The conversation's messages in order, each unbroken run of agent messages and notices
    /// folded into one entry.
    static func fold(_ messages: [Message]) -> [ChatEntry] {
        var entries: [ChatEntry] = []
        for message in messages {
            switch message.kind {
            case .human: entries.append(.human(message))
            case .reply: entries.append(.reply(message))
            case .agent, .notice:
                if case .activity(let burst) = entries.last {
                    entries[entries.count - 1] = .activity(burst + [message])
                } else {
                    entries.append(.activity([message]))
                }
            }
        }
        return entries
    }
}

/// A project's conversation with its coordinator: the latest page of messages, the running
/// turn's narration, and sending. `run()` keeps both current from the host's events.
@MainActor
@Observable
final class ProjectChat {
    let projectID: String
    private(set) var messages: [Message] = []
    /// The coordinator's latest run; its narration shows while it runs.
    private(set) var turn: StepPage?
    /// Why the last load or send failed, until one succeeds.
    private(set) var failure: String?
    private(set) var isSending = false
    var draft = ""

    @ObservationIgnored private let host: LiveHost

    init(host: LiveHost, projectID: String) {
        self.host = host
        self.projectID = projectID
    }

    var overview: ProjectOverview? { host.snapshot?.overview(of: projectID) }
    var coordinator: Session? { overview?.coordinator }
    var entries: [ChatEntry] { ChatEntry.fold(messages) }

    /// What the coordinator has said so far in a turn that is still running.
    var liveNarration: [Step] {
        guard let turn, turn.running else { return [] }
        return turn.narration
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && coordinator != nil
    }

    /// Loads the conversation, then follows the host's events until the task is cancelled.
    func run() async {
        let events = host.events()
        await reloadAll()
        for await event in events {
            switch event.kind {
            case .steps(let sessions) where sessions.contains(coordinator?.id ?? ""):
                await refreshTurn()
            case .state:
                await reloadMessages()
            case .resync:
                await reloadAll()
            default:
                break
            }
        }
    }

    /// Sends the draft to the coordinator. The message shows as soon as the host stores it; the
    /// reply follows with the turn it starts.
    func send() async {
        guard canSend, let coordinator else { return }
        let command = SendCommand(recipient: coordinator.id, body: draft.trimmingCharacters(in: .whitespacesAndNewlines))
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await host.connection.request(command)
            draft = ""
            failure = nil
            if !messages.contains(where: { $0.id == sent.id }) { messages.append(sent) }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// The latest messages and the whole latest turn: on opening, and after events were lost.
    private func reloadAll() async {
        await load { coordinator in
            messages = try await host.connection.request(MessagesCommand(sessionID: coordinator))
            turn = try await host.connection.request(StepsCommand(sessionID: coordinator))
        }
    }

    private func reloadMessages() async {
        await load { coordinator in
            messages = try await host.connection.request(MessagesCommand(sessionID: coordinator))
        }
    }

    /// Only the steps changed since the turn last read, merged into it.
    private func refreshTurn() async {
        await load { coordinator in
            let newer = try await host.connection.request(StepsCommand(sessionID: coordinator, after: turn?.revision ?? 0))
            turn = turn.map { $0.merging(newer) } ?? newer
        }
    }

    private func load(_ fetch: (_ coordinator: String) async throws -> Void) async {
        guard let coordinator else { return }
        do {
            try await fetch(coordinator.id)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
