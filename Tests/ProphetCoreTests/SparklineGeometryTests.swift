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
}
