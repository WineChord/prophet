import Foundation
@testable import ProphetCore
import XCTest

final class TradingViewParserTests: XCTestCase {
	func testParseTimescaleUpdateBars() throws {
		let frame = try frame(
			method: "timescale_update",
			parameters: [
				"cs_test",
				[
					"series_1": [
						"s": [
							["i": 0, "v": [1000, 10.0, 12.0, 9.5, 11.0, 1200]],
							["i": 1, "v": [1060, 11.0, 13.0, 10.5, 12.5, 1300]],
						],
					],
				],
			]
		)

		let bars = TradingViewParser.bars(from: frame)

		XCTAssertEqual(bars.count, 2)
		XCTAssertEqual(bars[0].timestamp, 1000)
		XCTAssertEqual(bars[1].close, 12.5)
		XCTAssertEqual(bars[1].volume, 1300)
	}

	func testParseQuote() throws {
		let frame = try frame(
			method: "qsd",
			parameters: [
				"qs_test",
				[
					"n": "NASDAQ:RKLB",
					"v": [
						"lp": 113.65,
						"ch": 3.57,
						"chp": 3.24,
						"current_session": "pre_market",
						"lp_time": 1_781_000_000,
						"currency_code": "USD",
						"short_name": "RKLB",
						"description": "Rocket Lab Corporation",
						"exchange": "Cboe One",
						"timezone": "America/New_York",
					],
				],
			]
		)

		let quote = TradingViewParser.quote(from: frame)

		XCTAssertEqual(quote?.symbol, "NASDAQ:RKLB")
		XCTAssertEqual(quote?.displaySymbol, "RKLB")
		XCTAssertEqual(quote?.lastPrice, 113.65)
		XCTAssertEqual(quote?.session, .preMarket)
		XCTAssertEqual(quote?.currencyCode, "USD")
		XCTAssertEqual(quote?.timeZoneIdentifier, "America/New_York")
	}

	func testSnapshotPrefersLatestChartBarForDisplayedPrice() {
		let snapshot = MarketSnapshot(
			instrument: Instrument(symbol: "NASDAQ:RKLB"),
			bars: [
				PriceBar(timestamp: 1000, open: 10, high: 10, low: 10, close: 10),
				PriceBar(timestamp: 1060, open: 12, high: 12, low: 12, close: 12),
			],
			lastPrice: 11
		)

		XCTAssertEqual(snapshot.effectiveLastPrice, 12)
	}

	private func frame(
		method: String,
		parameters: [Any]
	) throws -> TradingViewFrame {
		let encoded = try TradingViewCodec.encode(
			method: method,
			parameters: parameters
		)
		return try XCTUnwrap(TradingViewCodec.decodeFrames(from: encoded).first)
	}
}
