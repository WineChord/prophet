@testable import ProphetCore
import XCTest

final class TradingViewSymbolResolverTests: XCTestCase {
	func testCandidateSymbolsKeepExplicitExchange() {
		XCTAssertEqual(
			TradingViewSymbolResolver.candidateSymbols(for: " nasdaq:rklb "),
			["NASDAQ:RKLB"]
		)
	}

	func testCandidateSymbolsCoverMajorUSEquityVenues() {
		XCTAssertEqual(
			TradingViewSymbolResolver.candidateSymbols(for: "rklb"),
			[
				"NASDAQ:RKLB",
				"NYSE:RKLB",
				"AMEX:RKLB",
				"OTC:RKLB",
			]
		)
	}
}
