import CryptoKit
import Foundation
@testable import WiffletreeKit

/// An in-process host speaking the remote protocol's host side: `qr` pairing on `/pair`, the
/// challenge on `/v1`, `Hello`, a few commands and events with a replayable log.
actor FakeHost {
    nonisolated let publicKey: Data
    nonisolated let name = "Studio Mac"
    nonisolated let secret = Data((0..<16).map { UInt8($0) })
    nonisolated var id: KeyID { KeyID(publicKey: publicKey) }

    /// A wrong confirmation, as a host that does not hold the secret would send.
    var confirmsWrongly = false
    /// Holds replies until this many requests came, then answers them newest first.
    var replyInReverseAfter: Int?
    /// Leaves `ping` unanswered, as a host that has gone away.
    var ignoresPings = false

    private(set) var devices: [KeyID: Data] = [:]
    private(set) var deviceNames: [String] = []
    private(set) var commands: [String] = []
    private(set) var subscribedAfter: [Cursor?] = []
    private var epoch = "epoch-1"
    private var log: [HostEvent] = []
    private var subscribers: [PipeEnd] = []
    private var connections: [PipeEnd] = []
    private var held: [(PipeEnd, String)] = []

    init() {
        publicKey = P256.Signing.PrivateKey().publicKey.x963Representation
    }

    func set(confirmsWrongly: Bool = false, replyInReverseAfter: Int? = nil, ignoresPings: Bool = false) {
        self.confirmsWrongly = confirmsWrongly
        self.replyInReverseAfter = replyInReverseAfter
        self.ignoresPings = ignoresPings
    }

    /// A QR code for this host, as its Remote access page would show it.
    nonisolated func qrCode(addresses: [String], secret: Data? = nil) throws -> QRPayload {
        let json: [String: Any] = [
            "host_key": publicKey.base64EncodedString(),
            "host_name": name,
            "addresses": addresses,
            "port": 47821,
            "secret": (secret ?? self.secret).base64EncodedString()
        ]
        return try QRPayload(scanned: String(decoding: JSONSerialization.data(withJSONObject: json), as: UTF8.self))
    }

    func pairDevice(_ key: DeviceKey) {
        devices[key.id] = key.publicKey
    }

    nonisolated func serve(_ channel: PipeEnd, path: String) {
        Task { await run(channel, path: path) }
    }

    /// Records an event and sends it to every subscriber.
    func emit(_ kind: String, _ fields: [String: Any] = [:]) async {
        let event = HostEvent(cursor: Cursor(epoch: epoch, seq: UInt64(log.count + 1)), kind: Self.kind(kind, fields))
        log.append(event)
        for subscriber in subscribers {
            try? await subscriber.send(Self.line(["event": Self.json(event)]))
        }
    }

    /// Drops every connection, as a network change would.
    func dropConnections() {
        for connection in connections { connection.close() }
        connections = []
        subscribers = []
    }

    /// Drops every connection, then records events no device is subscribed to see.
    func dropConnections(thenRecord kinds: [String]) {
        dropConnections()
        for kind in kinds {
            log.append(HostEvent(cursor: Cursor(epoch: epoch, seq: UInt64(log.count + 1)), kind: Self.kind(kind, [:])))
        }
    }

    /// Restarts: a new epoch whose log holds none of the old events.
    func restart() {
        dropConnections()
        epoch = "epoch-2"
        log = []
    }

    /// Forgets the device and closes its connections with the reason `unpaired`.
    func remove(_ id: KeyID) {
        devices[id] = nil
        for connection in connections { connection.close(with: .unpaired) }
        connections = []
        subscribers = []
    }

    private func run(_ channel: PipeEnd, path: String) async {
        connections.append(channel)
        do {
            switch path {
            case ChannelPath.pair: try await pair(on: channel)
            case ChannelPath.v1: try await serveDevice(on: channel)
            default: channel.close()
            }
        } catch {
            channel.close()
        }
    }

    private func pair(on channel: PipeEnd) async throws {
        let start = try JSONDecoder().decode(PairStart.self, from: Data(try await channel.receive().utf8))
        let deviceKey = Data(base64Encoded: start.deviceKey)!
        deviceNames.append(start.deviceName)
        let transcript = Pairing.transcript(hostKey: publicKey, deviceKey: deviceKey, deviceName: start.deviceName, hostName: name)
        guard start.method == "qr", Pairing.confirms(Data(base64Encoded: start.proof)!, key: secret, side: .device, transcript: transcript) else {
            try await channel.send(Self.line(["refused": ["reason": "The code did not match"]]))
            return channel.close()
        }
        devices[KeyID(publicKey: deviceKey)] = deviceKey
        let key = confirmsWrongly ? Data(repeating: 9, count: 16) : secret
        let confirm = Pairing.confirmation(key: key, side: .host, transcript: transcript)
        try await channel.send(Self.line(["paired": ["confirm": confirm.base64EncodedString(), "host_id": id.hex]]))
    }

    private func serveDevice(on channel: PipeEnd) async throws {
        let challenge = Data(SHA256.hash(data: Data(UUID().uuidString.utf8)))
        try await channel.send(Self.line(["challenge": challenge.base64EncodedString(), "host_id": id.hex]))
        let answer = try JSONDecoder().decode(ChallengeAnswer.self, from: Data(try await channel.receive().utf8))
        guard let deviceID = KeyID(hex: answer.deviceID), let deviceKey = devices[deviceID],
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: Data(base64Encoded: answer.signature)!),
              try P256.Signing.PublicKey(x963Representation: deviceKey).isValidSignature(
                  signature, for: Pairing.challengeMessage(challenge: challenge, hostID: id, deviceID: deviceID))
        else {
            try await channel.send("\"unpaired\"")
            return channel.close(with: .unpaired)
        }
        try await channel.send(Self.line(["accepted": ["level": "control"]]))
        let hello = try JSONSerialization.jsonObject(with: Data(try await channel.receive().utf8)) as! [String: Any]
        precondition(hello["hello"] != nil)
        try await channel.send(Self.line(["welcome": [
            "protocol": 2, "host_id": id.hex, "host_version": "0.9.0", "epoch": epoch,
            "capabilities": ["events", "files"], "binary": "/usr/local/bin/wiffletree-host", "added_later": true
        ]]))
        while true {
            let request = try JSONSerialization.jsonObject(with: Data(try await channel.receive().utf8)) as! [String: Any]
            try await handle(request, on: channel)
        }
    }

    private func handle(_ request: [String: Any], on channel: PipeEnd) async throws {
        let id = request["id"] as! String
        let command = request["command"] as! [String: Any]
        let type = command["type"] as! String
        commands.append(type)
        let reply: [String: Any]
        switch type {
        case "subscribe":
            return try await subscribe(after: command["after"] as? [String: Any], id: id, on: channel)
        case "ping":
            if ignoresPings { return }
            reply = ["version": 2, "id": id, "result": NSNull(), "error": NSNull()]
        case "snapshot":
            reply = ["version": 2, "id": id, "result": Self.snapshot, "error": NSNull(), "host_ms": 3]
        case "messages":
            reply = ["version": 2, "id": id, "result": [Self.message(sessionId: command["session_id"] as! String)], "error": NSNull()]
        default:
            reply = ["version": 2, "id": id, "result": NSNull(), "error": "Unknown command \(type)"]
        }
        guard let count = replyInReverseAfter else { return try await channel.send(Self.line(reply)) }
        held.append((channel, Self.line(reply)))
        guard held.count == count else { return }
        for (channel, line) in held.reversed() { try await channel.send(line) }
        held = []
    }

    private func subscribe(after: [String: Any]?, id: String, on channel: PipeEnd) async throws {
        subscribedAfter.append(after.map { Cursor(epoch: $0["epoch"] as! String, seq: ($0["seq"] as! NSNumber).uint64Value) })
        let latest = Cursor(epoch: epoch, seq: UInt64(log.count))
        var lines = [Self.line(["version": 2, "id": id, "result": ["cursor": Self.json(latest)], "error": NSNull()])]
        if let cursor = subscribedAfter.last!, cursor.epoch == epoch, cursor.seq <= log.count {
            lines += log.dropFirst(Int(cursor.seq)).map { Self.line(["event": Self.json($0)]) }
        } else if subscribedAfter.last! != nil {
            lines.append(Self.line(["event": ["cursor": Self.json(latest), "kind": "resync"]]))
        }
        // Subscribed before the first await, so no event emitted meanwhile is missed.
        subscribers.append(channel)
        for line in lines { try await channel.send(line) }
    }

    private static func kind(_ name: String, _ fields: [String: Any]) -> HostEvent.Kind {
        switch name {
        case "state": .state
        case "usage": .usage
        case "attention": .attention(count: fields["count"] as! Int)
        default: .unknown(name)
        }
    }

    private static func json(_ cursor: Cursor) -> [String: Any] {
        ["epoch": cursor.epoch, "seq": cursor.seq]
    }

    private static func json(_ event: HostEvent) -> [String: Any] {
        var json: [String: Any] = ["cursor": json(event.cursor)]
        switch event.kind {
        case .attention(let count): json["kind"] = "attention"; json["count"] = count
        case .state: json["kind"] = "state"
        case .usage: json["kind"] = "usage"
        case .unknown(let name): json["kind"] = name
        default: fatalError("not sent by the fake")
        }
        return json
    }

    private static func line(_ value: Any) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    static var snapshot: [String: Any] { [
        "projects": [["id": "p1", "name": "iOS app", "space": "s1", "added_repositories": []]],
        "repositories": [],
        "sessions": [[
            "id": "c1", "project_id": "p1", "parent_id": NSNull(), "repository_id": NSNull(), "name": "Coordinator",
            "role": "project_orchestrator", "provider": "claude", "status": "working", "archived": false
        ]],
        "attention": [[
            "id": "a1", "project_id": "p1", "session_id": "c1", "host": "local", "operation_id": "question:1",
            "prompt": "Ship it?", "options": ["Yes", "No"], "answer": NSNull()
        ]],
        "tickets": [[
            "id": "t1", "coordinator_id": "c1", "repository_id": "r1", "title": "Client", "brief": "…",
            "worktree": "/w", "branch": "wiffletree/client", "state": "a_state_from_the_future",
            "pull_request": [
                "number": 7, "url": "https://github.com/o/r/pull/7", "state": "open", "draft": false, "base": "main",
                "head": "abc", "merge_state": "clean", "checks": "success", "unresolved_threads": 0,
                "comments": ["issue": NSNull(), "review": NSNull(), "inline": NSNull()]
            ]
        ]],
        "a_field_from_the_future": ["anything": 1]
    ] }

    private static func message(sessionId: String) -> [String: Any] {
        [
            "sequence": 4, "id": "m1", "project_id": "p1", "sender": NSNull(), "recipient": sessionId,
            "body": "**Hi**", "receipt": "delivered", "created_at": 1_795_000_000_000
        ]
    }
}
