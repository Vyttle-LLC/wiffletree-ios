// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WiffletreeKit",
    // macOS so `swift test` runs on the Mac and in CI without a simulator.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WiffletreeKit", targets: ["WiffletreeKit"])
    ],
    targets: [
        .target(name: "WiffletreeKit"),
        .testTarget(
            name: "WiffletreeKitTests",
            dependencies: ["WiffletreeKit"],
            resources: [.copy("Fixtures/pairing_vectors.json"), .copy("Fixtures/host_certificate.der")]
        )
    ]
)
