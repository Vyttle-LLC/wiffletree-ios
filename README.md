# wiffletree-ios

The iPhone app for [Wiffletree](https://github.com/Vyttle-LLC/wiffletree): a native SwiftUI remote control for Wiffletree on your own Mac. It reaches the Mac over the local network or a VPN you already use, such as Tailscale, and pairs by scanning a QR code the Mac shows. There is no account and no Vyttle server.

The app speaks the host's [remote protocol](https://github.com/Vyttle-LLC/wiffletree/blob/main/docs/remote-protocol.md).

## Layout

- `Wiffletree/` — the app target, a thin composition root.
- `Packages/WiffletreeKit/` — everything that is not UI, with no UIKit or SwiftUI. Today: the pairing cryptography (keys and ids, the transcript, the `qr` method's proof and confirmation, the `/v1` challenge, device names), the pairing QR code's payload, and the Keychain store for the device's key.
- `WiffletreeTests/` — tests that need the app as host, such as the Keychain.
- `project.yml` — the XcodeGen source of `Wiffletree.xcodeproj`, which is committed.

## Checks

```bash
# Package tests, on the Mac
cd Packages/WiffletreeKit && swift test

# Regenerate the project after adding, moving or deleting files (XcodeGen 2.44.1)
./scripts/generate.sh

# Build the app for the simulator
xcodebuild build -scheme Wiffletree -destination 'generic/platform=iOS Simulator'

# All tests in a simulator, including the app-hosted Keychain test
xcodebuild test -scheme Wiffletree -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI runs the package tests, checks the project is in sync with `project.yml`, and builds the app and its tests for the simulator.
