# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` points here.

## What this is

`wiffletree-ios` is the iPhone client of Wiffletree, Vyttle's agent workspace for the Mac. It drives the user's own Wiffletree host over the LAN or the user's VPN (Tailscale); there is no account and no hosted server. The host lives in Vyttle-LLC/wiffletree (locally `~/dev/vyttle/wiffletree`); its `docs/remote-protocol.md` and `docs/host-protocol.md` are the contract this app implements, and `crates/workspace-core/src/pairing.rs` is the reference for the pairing cryptography.

SwiftUI, Swift 6 strict concurrency, iOS 26+. One XcodeGen project; the app target `Wiffletree` is a thin composition root over local packages in `Packages/`.

## Layout

- **`WiffletreeKit`** — protocol, cryptography and storage. No UIKit or SwiftUI; keep it that way so it tests with `swift test` on the Mac.
  - `DeviceKey`, `KeyID` — the device's P-256 key and key ids (SHA-256 of the SEC1 uncompressed key, lowercase hex, 16-character short id).
  - `Pairing` — device-name normalisation, the transcript, HMAC confirmations (checked in constant time) and the `/v1` challenge message.
  - `QRPayload`, `QRPairing` — parsing the pairing QR code and the device's side of the `qr` method. The iPhone does not implement the `code` (SPAKE2) method.
  - `KeyStore` — `KeychainKeyStore` for the app, `InMemoryKeyStore` for tests.
  - `Connection/` — the network client. `NetworkDialer` opens TLS 1.3 pinned to the host's key and a WebSocket (Network.framework); `AddressRace` tries a host's addresses at once with the key-change rules; `HostPairer` pairs by `qr` on `/pair` and keeps the host in a `PairedHostStore`; `RemoteHostConnection` answers the `/v1` challenge, says `Hello`, sends typed `HostCommand`s, streams events and reconnects with the last cursor. `HostConnection` is the protocol a demo host can implement too. `HostModels` and `HostCommands` hold only what the first screens need; unknown fields, states and event kinds are tolerated.
  - `Demo/` — `DemoHostConnection`, the built-in "Demo Mac" (App Review's demo mode): `DemoSeed`'s workspace in memory, no network, canned replies after an injectable delay, events with the real cursor rules. Commands it cannot simulate fail with "Not available in the demo." Keep the seed telling the story of `design/mockups/`.
- **`Wiffletree/`** — the app. `Info.plist` and the entitlements are generated from `project.yml`; edit them there.
- **`WiffletreeTests/`** — tests that need the app as host (the Keychain needs a signed app's entitlements).
- **`design/`** — HTML mockups; not part of the build.

## Checks

```bash
cd Packages/WiffletreeKit && swift test
./scripts/generate.sh   # after adding, moving or deleting files; never bare `xcodegen generate`
xcodebuild build -scheme Wiffletree -destination 'generic/platform=iOS Simulator'
xcodebuild test -scheme Wiffletree -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

With several simulator runtimes installed, a destination by name alone matches nothing; name the `OS`, or pick a device by `id=` from `xcrun simctl list devices available`.

The package tests reach no network: `Tests/WiffletreeKitTests/Support/` has an in-process fake host. `scripts/e2e/host-e2e.sh [wiffletree checkout]` is the local end-to-end check against a real headless host (pair by QR code, list projects); it needs a host branch that offers pairing by `qr`, and port 47821 free.

CI (GitHub-hosted macOS) runs `swift test`, regenerates the project with XcodeGen 2.44.1 and fails on drift in `Wiffletree.xcodeproj`, then runs `xcodebuild build-for-testing`. Tests use Swift Testing (`@Test`, `#expect`).

## Conventions

- `Packages/WiffletreeKit/Tests/WiffletreeKitTests/Fixtures/pairing_vectors.json` is a byte-for-byte copy of the host's fixture; never edit it. If the host's vectors change, copy them again and update the source commit noted in `PairingVectorTests.swift`.
- Binary values in protocol JSON are standard base64 unless the protocol says hex.
- No secrets in the repository; the repository is public. The device key lives only in the Keychain, this device only.
- Commits: no `Co-Authored-By` trailers.
