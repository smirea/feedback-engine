// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Feedback",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Feedback", targets: ["Feedback"])],
    targets: [
        .target(name: "Feedback", path: "packages/ios/Sources/Feedback"),
        .testTarget(name: "FeedbackTests", dependencies: ["Feedback"], path: "packages/ios/Tests/FeedbackTests"),
    ]
)
