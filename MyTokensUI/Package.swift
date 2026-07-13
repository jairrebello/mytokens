// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyTokensUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyTokensUI", targets: ["MyTokensUI"]),
    ],
    // O contrato mora no Core, e só lá. O ContractMirror foi deletado quando esta
    // dependência entrou — dois contratos é o jeito mais barato de o app mentir.
    dependencies: [
        .package(path: "../MyTokensCore"),
    ],
    targets: [
        .target(name: "MyTokensUI", dependencies: [.product(name: "MyTokensCore", package: "MyTokensCore")]),
        .executableTarget(name: "MyTokensGallery", dependencies: ["MyTokensUI"]),
        .testTarget(name: "MyTokensUITests", dependencies: ["MyTokensUI"]),
    ],
    swiftLanguageModes: [.v6]
)
