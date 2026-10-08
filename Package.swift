// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shelf",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Shelf",
            path: "Sources/Shelf",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "ShelfTests",
            dependencies: ["Shelf"],
            path: "Tests/ShelfTests"
        )
    ]
)
