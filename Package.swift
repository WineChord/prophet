// swift-tools-version: 5.10

import PackageDescription

let package = Package(
	name: "Prophet",
	platforms: [
		.macOS(.v13),
	],
	products: [
		.executable(
			name: "Prophet",
			targets: ["Prophet"]
		),
	],
	targets: [
		.target(
			name: "ProphetCore"
		),
		.executableTarget(
			name: "Prophet",
			dependencies: ["ProphetCore"]
		),
		.testTarget(
			name: "ProphetCoreTests",
			dependencies: ["ProphetCore"]
		),
	]
)
