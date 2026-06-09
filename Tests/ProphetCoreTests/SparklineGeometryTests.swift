import CoreGraphics
@testable import ProphetCore
import XCTest

final class SparklineGeometryTests: XCTestCase {
	func testPointsFitInsideSize() {
		let points = SparklineGeometry.points(
			for: [10, 12, 11, 15],
			in: CGSize(width: 72, height: 18),
			padding: 2
		)

		XCTAssertEqual(points.count, 4)
		for point in points {
			XCTAssertGreaterThanOrEqual(point.x, 2)
			XCTAssertLessThanOrEqual(point.x, 70)
			XCTAssertGreaterThanOrEqual(point.y, 2)
			XCTAssertLessThanOrEqual(point.y, 16)
		}
	}

	func testFlatValuesStayCentered() {
		let points = SparklineGeometry.points(
			for: [7, 7, 7],
			in: CGSize(width: 48, height: 18),
			padding: 2
		)

		XCTAssertEqual(points.map(\.y), [9, 9, 9])
	}

	func testHigherValuesRenderHigher() {
		let points = SparklineGeometry.points(
			for: [10, 12],
			in: CGSize(width: 20, height: 20),
			padding: 2
		)

		XCTAssertLessThan(points[0].y, points[1].y)
	}

	func testTimelinePointsPreserveTimeGaps() {
		let points = TimelineGeometry.points(
			for: [
				PriceBar(timestamp: 0, open: 10, high: 10, low: 10, close: 10),
				PriceBar(timestamp: 60, open: 11, high: 11, low: 11, close: 11),
				PriceBar(timestamp: 600, open: 12, high: 12, low: 12, close: 12),
			],
			in: CGSize(width: 100, height: 20),
			padding: 0
		)

		XCTAssertEqual(points.map(\.x), [0, 10, 100])
	}

	func testTimelineLayoutCompressesLargeGaps() {
		let layout = TimelineGeometry.layout(
			for: [
				PriceBar(timestamp: 0, open: 10, high: 10, low: 10, close: 10),
				PriceBar(timestamp: 60, open: 11, high: 11, low: 11, close: 11),
				PriceBar(timestamp: 60 * 60 * 8, open: 12, high: 12, low: 12, close: 12),
				PriceBar(timestamp: 60 * 60 * 8 + 60, open: 13, high: 13, low: 13, close: 13),
			],
			in: CGSize(width: 100, height: 20),
			padding: 0
		)

		XCTAssertEqual(layout.breaks.count, 1)
		XCTAssertEqual(layout.breaks[0].endX - layout.breaks[0].startX, 7, accuracy: 0.001)
		XCTAssertEqual(layout.points[0].x, 0, accuracy: 0.001)
		XCTAssertEqual(layout.points[1].x, 46.5, accuracy: 0.001)
		XCTAssertEqual(layout.points[2].x, 53.5, accuracy: 0.001)
		XCTAssertEqual(layout.points[3].x, 100, accuracy: 0.001)
	}

	func testTimelineHigherPricesRenderHigher() {
		let points = TimelineGeometry.points(
			for: [
				PriceBar(timestamp: 0, open: 10, high: 10, low: 10, close: 10),
				PriceBar(timestamp: 60, open: 12, high: 12, low: 12, close: 12),
			],
			in: CGSize(width: 20, height: 20),
			padding: 2
		)

		XCTAssertLessThan(points[0].y, points[1].y)
	}
}
