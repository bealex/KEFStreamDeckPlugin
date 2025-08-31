// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "KEFControlCore",

    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "KEFControl", targets: [ "KEFControl" ]),
        .executable(name: "kefcli", targets: [ "kefcli" ]),
    ],
    dependencies: [
        .package(url: "git@github.com:redmadrobot-spb/memoirs-ios.git", revision: "fc33c113628506ce8338c2a5216b7fff6af87e30"),
    ],
    targets: [
        .target(name: "KEFControl", dependencies: [ .product(name: "Memoirs", package: "memoirs-ios") ], path: "Sources"),
        .executableTarget(name: "kefcli", dependencies: [ "KEFControl", ], path: "CLI"),
        .testTarget(name: "TestKEFControl", dependencies: [ "KEFControl" ], path: "Tests"),
    ],
    swiftLanguageVersions: [ .v5 ]
)
