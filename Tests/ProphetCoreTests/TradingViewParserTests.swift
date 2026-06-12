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
						"premarket_close": 118.19,
						"premarket_change": 4.54,
						"premarket_change_percent": 3.99,
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
		XCTAssertEqual(quote?.preMarketPrice, 118.19)
		XCTAssertEqual(quote?.preMarketChange, 4.54)
		XCTAssertEqual(quote?.preMarketChangePercent, 3.99)
		XCTAssertEqual(quote?.effectiveLastPrice, 118.19)
		XCTAssertEqual(quote?.effectiveChange, 4.54)
		XCTAssertEqual(quote?.effectiveChangePercent, 3.99)
		XCTAssertEqual(quote?.session, .preMarket)
		XCTAssertEqual(quote?.currencyCode, "USD")
		XCTAssertEqual(quote?.timeZoneIdentifier, "America/New_York")
	}

	func testMarketSessionParsesTradingViewMarketAlias() {
		XCTAssertEqual(MarketSession(tradingViewValue: "market"), .regular)
	}

	func testMarketSessionParsesTradingViewOutOfSessionAlias() {
		XCTAssertEqual(MarketSession(tradingViewValue: "out_of_session"), .closed)
	}

	func testQuoteUsesRegularLastPriceDuringRegularSession() {
		let quote = TradingViewQuote(
			lastPrice: 115.37,
			change: 1.72,
			changePercent: 1.51,
			preMarketPrice: 115.48,
			postMarketPrice: 115.37,
			session: .regular
		)

		XCTAssertEqual(quote.effectiveLastPrice, 115.37)
		XCTAssertEqual(quote.effectiveChange, 1.72)
		XCTAssertEqual(quote.effectiveChangePercent, 1.51)
	}

	func testQuoteUsesPremarketPriceDuringPremarketSession() {
		let quote = TradingViewQuote(
			lastPrice: 113.65,
			change: 3.57,
			changePercent: 3.24,
			preMarketPrice: 118.19,
			preMarketChange: 4.54,
			preMarketChangePercent: 3.99,
			session: .preMarket
		)

		XCTAssertEqual(quote.effectiveLastPrice, 118.19)
		XCTAssertEqual(quote.effectiveChange, 4.54)
		XCTAssertEqual(quote.effectiveChangePercent, 3.99)
	}

	func testQuoteUsesPostmarketPriceDuringPostmarketSession() {
		let quote = TradingViewQuote(
			lastPrice: 113.65,
			change: 3.57,
			changePercent: 3.24,
			postMarketPrice: 117.81,
			postMarketChange: 4.16,
			postMarketChangePercent: 3.66,
			session: .postMarket
		)

		XCTAssertEqual(quote.effectiveLastPrice, 117.81)
		XCTAssertEqual(quote.effectiveChange, 4.16)
		XCTAssertEqual(quote.effectiveChangePercent, 3.66)
	}

	func testMergedPremarketQuoteUsesExtendedPrice() {
		let baseQuote = TradingViewQuote(
			lastPrice: 113.65,
			change: 3.57,
			changePercent: 3.24,
			session: .preMarket
		)
		let extendedQuote = TradingViewQuote(
			preMarketPrice: 118.19,
			preMarketChange: 4.54,
			preMarketChangePercent: 3.99
		)

		let mergedQuote = baseQuote.merging(extendedQuote)

		XCTAssertEqual(mergedQuote.effectiveLastPrice, 118.19)
		XCTAssertEqual(mergedQuote.effectiveChange, 4.54)
		XCTAssertEqual(mergedQuote.effectiveChangePercent, 3.99)
		XCTAssertEqual(mergedQuote.lastPrice, 113.65)
	}

	func testClosedQuoteUsesNewerChartBarPrice() {
		let quote = TradingViewQuote(
			lastPrice: 108.23,
			change: -5.42,
			changePercent: -4.77,
			postMarketPrice: 108.17,
			session: .closed,
			lastTradeTime: Date(timeIntervalSince1970: 1_199)
		)
		let bars = [
			PriceBar(timestamp: 1_000, open: 108.17, high: 108.17, low: 108.17, close: 108.17),
			PriceBar(timestamp: 1_180, open: 104.36, high: 104.4, low: 104.28, close: 104.28),
		]

		let resolvedQuote = quote.resolvedValues(with: bars)

		XCTAssertEqual(resolvedQuote.lastPrice, 104.28)
		XCTAssertEqual(resolvedQuote.change ?? 0, -9.37, accuracy: 0.001)
		XCTAssertEqual(resolvedQuote.changePercent ?? 0, -8.2446, accuracy: 0.001)
	}

	func testRegularQuoteKeepsLiveQuotePriceOverChartBarPrice() {
		let quote = TradingViewQuote(
			lastPrice: 115.37,
			change: 1.72,
			changePercent: 1.51,
			session: .regular,
			lastTradeTime: Date(timeIntervalSince1970: 1_000)
		)
		let bars = [
			PriceBar(timestamp: 1_180, open: 114.36, high: 114.4, low: 114.28, close: 114.28),
		]

		let resolvedQuote = quote.resolvedValues(with: bars)

		XCTAssertEqual(resolvedQuote.lastPrice, 115.37)
		XCTAssertEqual(resolvedQuote.change, 1.72)
		XCTAssertEqual(resolvedQuote.changePercent, 1.51)
	}

	func testSnapshotPrefersLiveQuoteForDisplayedPrice() {
		let snapshot = MarketSnapshot(
			instrument: Instrument(symbol: "NASDAQ:RKLB"),
			bars: [
				PriceBar(timestamp: 1000, open: 10, high: 10, low: 10, close: 10),
				PriceBar(timestamp: 1060, open: 12, high: 12, low: 12, close: 12),
			],
			lastPrice: 11
		)

		XCTAssertEqual(snapshot.effectiveLastPrice, 11)
	}

	func testSnapshotBaselineUsesLiveQuoteChange() {
		let snapshot = MarketSnapshot(
			instrument: Instrument(symbol: "NASDAQ:RKLB"),
			bars: [
				PriceBar(timestamp: 1000, open: 10, high: 10, low: 10, close: 10),
				PriceBar(timestamp: 1060, open: 12, high: 12, low: 12, close: 12),
			],
			lastPrice: 11,
			change: 1
		)

		XCTAssertEqual(snapshot.effectiveBaselinePrice, 10)
		XCTAssertEqual(snapshot.effectiveChange, 1)
	}

	func testSnapshotFallsBackToLatestChartBarForDisplayedPrice() {
		let snapshot = MarketSnapshot(
			instrument: Instrument(symbol: "NASDAQ:RKLB"),
			bars: [
				PriceBar(timestamp: 1000, open: 10, high: 10, low: 10, close: 10),
				PriceBar(timestamp: 1060, open: 12, high: 12, low: 12, close: 12),
			]
		)

		XCTAssertEqual(snapshot.effectiveLastPrice, 12)
		XCTAssertEqual(snapshot.effectiveBaselinePrice, 10)
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
