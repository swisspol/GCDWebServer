// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "GCDWebServers",
    products: [
        .library(
            name: "GCDWebServers",
            targets: ["GCDWebServers"]),
    ],
    targets: [
        .target(
            name: "GCDWebServers"),
    ])
