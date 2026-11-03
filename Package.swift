// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Feetback",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Feetback", targets: ["Feetback"])],
    targets: [
        .target(name: "Feetback", path: "packages/ios/Sources/Feetback"),
        .testTarget(name: "FeetbackTests", dependencies: ["Feetback"], path: "packages/ios/Tests/FeetbackTests"),
    ]
)
