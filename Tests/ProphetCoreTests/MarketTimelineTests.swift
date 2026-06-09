@testable import ProphetCore
import XCTest

final class MarketTimelineTests: XCTestCase {
	func testOverviewBarsStartAtMostRecentRegularOpen() throws {
		let timeline = MarketTimeline(timeZoneIdentifier: "America/New_York")
		let bars = [
			bar("2026-06-08T08:00:00-04:00", close: 1),
			bar("2026-06-08T09:30:00-04:00", close: 2),
			bar("2026-06-08T16:00:00-04:00", close: 3),
			bar("2026-06-09T04:00:00-04:00", close: 4),
		]

		let overviewBars = timeline.overviewBars(from: bars)

		XCTAssertEqual(overviewBars.map(\.close), [2, 3, 4])
	}

	func testOverviewBarsUseCurrentRegularOpenDuringRegularSession() throws {
		let timeline = MarketTimeline(timeZoneIdentifier: "America/New_York")
		let bars = [
			bar("2026-06-08T09:30:00-04:00", close: 1),
			bar("2026-06-09T04:00:00-04:00", close: 2),
			bar("2026-06-09T09:30:00-04:00", close: 3),
			bar("2026-06-09T10:00:00-04:00", close: 4),
		]

		let overviewBars = timeline.overviewBars(from: bars)

		XCTAssertEqual(overviewBars.map(\.close), [3, 4])
	}

	func testSessionClassification() throws {
		let timeline = MarketTimeline(timeZoneIdentifier: "America/New_York")

		XCTAssertEqual(timeline.session(for: timestamp("2026-06-09T08:00:00-04:00")), .extended)
		XCTAssertEqual(timeline.session(for: timestamp("2026-06-09T09:30:00-04:00")), .regular)
		XCTAssertEqual(timeline.session(for: timestamp("2026-06-09T16:00:00-04:00")), .extended)
	}

	func testLargeGapsAreNotConnected() throws {
		let timeline = MarketTimeline(timeZoneIdentifier: "America/New_York")
		let left = bar("2026-06-09T07:59:00-04:00", close: 1)
		let right = bar("2026-06-09T16:00:00-04:00", close: 2)

		XCTAssertFalse(timeline.canConnect(left, right))
	}

	private func bar(_ value: String, close: Double) -> PriceBar {
		PriceBar(
			timestamp: timestamp(value),
			open: close,
			high: close,
			low: close,
			close: close
		)
	}

	private func timestamp(_ value: String) -> TimeInterval {
		ISO8601DateFormatter().date(from: value)?.timeIntervalSince1970 ?? 0
	}
}
