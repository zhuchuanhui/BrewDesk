// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrewDesk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BrewDesk", targets: ["BrewDesk"])],
    targets: [.executableTarget(name: "BrewDesk")]
)
