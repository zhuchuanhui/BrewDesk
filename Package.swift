// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrewDesk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BrewDesk", targets: ["BrewDesk"])],
    targets: [.executableTarget(name: "BrewDesk")]
)
