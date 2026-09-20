// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VolumeFold",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VolumeFoldCore", targets: ["VolumeFoldCore"]),
        .executable(name: "volumefold-probe", targets: ["VolumeFoldProbe"])
    ],
    targets: [
        .target(name: "VolumeFoldCore"),
        .target(name: "VolumeFoldHardware", dependencies: ["VolumeFoldCore"]),
        .executableTarget(name: "VolumeFoldProbe", dependencies: ["VolumeFoldHardware"]),
        .testTarget(name: "VolumeFoldCoreTests", dependencies: ["VolumeFoldCore", "VolumeFoldHardware"])
    ]
)
