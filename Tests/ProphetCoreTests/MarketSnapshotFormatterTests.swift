@testable import ProphetCore
import XCTest

final class MarketSnapshotFormatterTests: XCTestCase {
	func testPositiveChangeUsesSinglePlusSign() {
		let text = formatterText(changePercent: 3.24)

		XCTAssertTrue(text.contains(" +3.24%"), text)
		XCTAssertFalse(text.contains("++"), text)
	}

	func testNegativeChangeUsesSingleMinusSign() {
		let text = formatterText(changePercent: -4.96)

		XCTAssertTrue(text.contains(" -4.96%"), text)
		XCTAssertFalse(text.contains("-+"), text)
	}

	func testStatusPriceTextUsesCompactDecimalPrice() {
		let snapshot = MarketSnapshot(
			instrument: Instrument(symbol: "NASDAQ:RKLB"),
			bars: [
				PriceBar(
					timestamp: 0,
					open: 118.284,
					high: 118.284,
					low: 118.284,
					close: 118.284
				),
			]
		)

		XCTAssertEqual(MarketSnapshotFormatter().statusPriceText(for: snapshot), "118.28")
	}

	private func formatterText(changePercent: Double) -> String {
		let snapshot = MarketSnapshot(
			instrument: Instrument(symbol: "NASDAQ:RKLB"),
			bars: [
				PriceBar(
					timestamp: 0,
					open: 117.81,
					high: 117.81,
					low: 117.81,
					close: 117.81
				),
			],
			changePercent: changePercent
		)
		return MarketSnapshotFormatter().tooltipText(for: snapshot)
	}
}
