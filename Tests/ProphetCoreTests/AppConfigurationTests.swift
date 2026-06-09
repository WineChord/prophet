import Foundation
@testable import ProphetCore
import XCTest

final class AppConfigurationTests: XCTestCase {
	func testLoadUsesCompactDefaultStatusWidth() {
		let configuration = AppConfiguration.load(environment: [:], configURL: nil)

		XCTAssertEqual(configuration.statusItemWidth, ProphetDefaults.compactStatusItemWidth)
	}

	func testLoadUsesEnvironmentOverrides() {
		let configuration = AppConfiguration.load(
			environment: [
				"PROPHET_SYMBOL": "NYSE:IBM",
				"PROPHET_UPDATE_INTERVAL": "8",
				"PROPHET_BAR_COUNT": "120",
				"PROPHET_STATUS_WIDTH": "96",
			],
			configURL: nil
		)

		XCTAssertEqual(configuration.requestedSymbol, "NYSE:IBM")
		XCTAssertEqual(configuration.updateInterval, 8)
		XCTAssertEqual(configuration.barCount, 120)
		XCTAssertEqual(configuration.statusItemWidth, 96)
	}

	func testLoadClampsSmallValues() {
		let configuration = AppConfiguration.load(
			environment: [
				"PROPHET_UPDATE_INTERVAL": "1",
				"PROPHET_BAR_COUNT": "20",
				"PROPHET_STATUS_WIDTH": "12",
			],
			configURL: nil
		)

		XCTAssertEqual(configuration.updateInterval, 5)
		XCTAssertEqual(configuration.barCount, 60)
		XCTAssertEqual(configuration.statusItemWidth, 48)
	}

	func testLoadReadsConfigFile() throws {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let url = directory.appendingPathComponent("config.json")
		try Data(
			"""
			{
			  "symbol": "NASDAQ:AAPL",
			  "updateInterval": 30,
			  "barCount": 390,
			  "statusItemWidth": 108
			}
			""".utf8
		).write(to: url)

		let configuration = AppConfiguration.load(environment: [:], configURL: url)

		XCTAssertEqual(configuration.requestedSymbol, "NASDAQ:AAPL")
		XCTAssertEqual(configuration.updateInterval, 30)
		XCTAssertEqual(configuration.barCount, 390)
		XCTAssertEqual(configuration.statusItemWidth, 108)
	}
}
