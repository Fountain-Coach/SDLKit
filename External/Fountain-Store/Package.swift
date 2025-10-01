// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Fountain-Store",
    platforms: [ .macOS(.v13) ],
    products: [ .library(name: "FountainStore", targets: ["FountainStore"]) ],
    targets: [ .target(name: "FountainStore", path: "Sources") ]
)

