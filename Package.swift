// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GitPulse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "GitPulse", targets: ["GitPulse"])],
    targets: [.executableTarget(name: "GitPulse")]
)
