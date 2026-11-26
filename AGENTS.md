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
- **`Wiffletree/`** — the app. `Info.plist` and the entitlements are generated from `project.yml`; edit them there.
- **`WiffletreeTests/`** — tests that need the app as host (the Keychain needs a signed app's entitlements).
- **`design/`** — HTML mockups; not part of the build.

## Checks

```bash
cd Packages/WiffletreeKit && swift test
./scripts/generate.sh   # after adding, moving or deleting files; never bare `xcodegen generate`
xcodebuild build -scheme Wiffletree -destination 'generic/platform=iOS Simulator'
xcodebuild test -scheme Wiffletree -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI (GitHub-hosted macOS) runs `swift test`, regenerates the project with XcodeGen 2.44.1 and fails on drift in `Wiffletree.xcodeproj`, then runs `xcodebuild build-for-testing`. Tests use Swift Testing (`@Test`, `#expect`).

## Conventions

- `Packages/WiffletreeKit/Tests/WiffletreeKitTests/Fixtures/pairing_vectors.json` is a byte-for-byte copy of the host's fixture; never edit it. If the host's vectors change, copy them again and update the source commit noted in `PairingVectorTests.swift`.
- Binary values in protocol JSON are standard base64 unless the protocol says hex.
- No secrets in the repository; the repository is public. The device key lives only in the Keychain, this device only.
- Commits: no `Co-Authored-By` trailers.
