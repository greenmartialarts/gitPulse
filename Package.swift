// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitPulse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "GitPulse", targets: ["GitPulse"])],
    targets: [.executableTarget(name: "GitPulse")]
)
