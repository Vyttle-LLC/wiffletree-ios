// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WiffletreeDesignSystem",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "WiffletreeDesignSystem", targets: ["WiffletreeDesignSystem"])
    ],
    targets: [
        .target(name: "WiffletreeDesignSystem")
    ]
)
