// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "am",
  platforms: [.macOS("26.0")],
  targets: [
    .executableTarget(name: "am", path: "Sources/am")
  ]
)
