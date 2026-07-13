// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyTokensCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyTokensCore", targets: ["MyTokensCore"]),
        .executable(name: "mtcore-bench", targets: ["MyTokensCoreBench"]),
    ],
    targets: [
        .target(
            name: "MyTokensCore",
            // Cópia de data/pricing.json (symlink não sobrevive ao .copy do SwiftPM).
            // O teste `bundledDoesNotDriftFromCanonical` compara os bytes e quebra se
            // as duas divergirem — a fonte da verdade continua sendo data/pricing.json.
            resources: [.copy("Resources/pricing.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "MyTokensCoreBench",
            dependencies: ["MyTokensCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MyTokensCoreTests",
            dependencies: ["MyTokensCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
