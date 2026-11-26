import Foundation

/// One connection a host accepted: the challenge answered and `Hello` exchanged. It matches
/// responses to requests by id and hands events on in the order they came. It ends when the
/// channel does; `RemoteHostConnection` then opens another.
actor HostSession {
    let welcome: Welcome
    let level: AccessLevel
    private let channel: any MessageChannel
    private let onEvent: @Sendable (HostEvent) -> Void
    private var pending: [String: CheckedContinuation<Data, any Error>] = [:]
    private var endedWith: ConnectionError?
    private var reader: Task<ConnectionError, Never>?

    private init(channel: any MessageChannel, welcome: Welcome, level: AccessLevel, onEvent: @escaping @Sendable (HostEvent) -> Void) {
        self.channel = channel
        self.welcome = welcome
        self.level = level
        self.onEvent = onEvent
    }

    /// Answers the host's challenge on a channel opened on `/v1`, then exchanges `Hello`.
    static func open(
        _ channel: any MessageChannel,
        host: PairedHost,
        deviceKey: DeviceKey,
        appVersion: String,
        onEvent: @escaping @Sendable (HostEvent) -> Void
    ) async throws(ConnectionError) -> HostSession {
        do throws(ConnectionError) {
            let level = try await answerChallenge(on: channel, host: host, deviceKey: deviceKey)
            try await channel.send(json: HelloLine(appVersion: appVersion), using: HostJSON.encoder)
            let answer = try await channel.receive(json: HelloAnswer.self, within: HostPairer.stepLimit, using: HostJSON.decoder)
            guard let welcome = answer.welcome else {
                throw .incompatible(hostVersion: answer.refused?.hostVersion ?? "unknown")
            }
            let session = HostSession(channel: channel, welcome: welcome, level: level, onEvent: onEvent)
            await session.startReading()
            return session
        } catch {
            channel.close()
            throw error
        }
    }

    /// Signs the host's challenge with the device key, after checking the host is the paired one.
    private static func answerChallenge(on channel: any MessageChannel, host: PairedHost, deviceKey: DeviceKey) async throws(ConnectionError) -> AccessLevel {
        let challenge = try await channel.receive(json: Challenge.self, within: HostPairer.stepLimit)
        guard KeyID(hex: challenge.hostID) == host.id else { throw .keyChanged }
        guard let bytes = Data(base64Encoded: challenge.challenge),
              let signature = try? deviceKey.sign(Pairing.challengeMessage(challenge: bytes, hostID: host.id, deviceID: deviceKey.id))
        else { throw .unexpectedMessage("a malformed challenge") }
        try await channel.send(json: ChallengeAnswer(deviceID: deviceKey.id.hex, signature: signature.base64EncodedString()))
        switch try await channel.receive(json: ChallengeVerdict.self, within: HostPairer.stepLimit) {
        case .accepted(let level): return level
        case .unpaired: throw .unpaired
        }
    }

    /// Sends `command` and waits for the response with its id.
    func request<Command: HostCommand>(_ command: Command) async throws(ConnectionError) -> Command.Reply {
        if let endedWith { throw endedWith }
        let id = UUID().uuidString
        guard let line = try? HostJSON.encoder.encode(RequestLine(version: welcome.protocol, id: id, command: command)) else {
            throw .unexpectedMessage("could not encode \(Command.type)")
        }
        let response: Data
        do {
            response = try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                Task { [channel] in
                    do throws(ConnectionError) {
                        try await channel.send(String(decoding: line, as: UTF8.self))
                    } catch {
                        self.resolve(id, with: .failure(error))
                    }
                }
            }
        } catch {
            throw error as? ConnectionError ?? .closed
        }
        guard let box = try? HostJSON.decoder.decode(ResultBox<Command.Reply>.self, from: response) else {
            throw .unexpectedMessage("the reply to \(Command.type)")
        }
        if let result = box.result { return result }
        if let nothing = NoReply() as? Command.Reply { return nothing }
        throw .unexpectedMessage("no result for \(Command.type)")
    }

    /// Waits until the connection ends, and says why.
    func ended() async -> ConnectionError {
        await reader?.value ?? endedWith ?? .closed
    }

    func close() {
        channel.close()
    }

    private func startReading() {
        reader = Task { await read() }
    }

    private func read() async -> ConnectionError {
        while true {
            do {
                deliver(try await channel.receive())
            } catch {
                endedWith = error
                for continuation in pending.values { continuation.resume(throwing: error) }
                pending = [:]
                return error
            }
        }
    }

    /// Routes one frame: an event to `onEvent`, a response to its request. Frames this client
    /// cannot read are skipped.
    private func deliver(_ text: String) {
        guard let frame = try? HostJSON.decoder.decode(InboundFrame.self, from: Data(text.utf8)) else { return }
        if let event = frame.event {
            onEvent(event)
        } else if let id = frame.id {
            resolve(id, with: frame.error.map { .failure(ConnectionError.commandFailed($0)) } ?? .success(Data(text.utf8)))
        }
    }

    private func resolve(_ id: String, with result: Result<Data, ConnectionError>) {
        pending.removeValue(forKey: id)?.resume(with: result.mapError { $0 })
    }
}
