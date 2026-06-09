import Foundation
@testable import ProphetCore
import XCTest

final class TradingViewCodecTests: XCTestCase {
	func testEncodeAndDecodeFrame() throws {
		let encoded = try TradingViewCodec.encode(
			method: "quote_create_session",
			parameters: ["qs_test"]
		)

		let frames = try TradingViewCodec.decodeFrames(from: encoded)

		XCTAssertEqual(frames.count, 1)
		XCTAssertEqual(frames[0].method, "quote_create_session")
		XCTAssertEqual(frames[0].parameters.first as? String, "qs_test")
	}

	func testDecodeHeartbeatAndMessage() throws {
		let message = try TradingViewCodec.encode(
			method: "series_completed",
			parameters: ["cs_test", "series_1"]
		)

		let frames = try TradingViewCodec.decodeFrames(from: "~h~12345" + message)

		XCTAssertEqual(frames.count, 2)
		XCTAssertEqual(frames[0].heartbeat, "~h~12345")
		XCTAssertEqual(frames[1].method, "series_completed")
	}
}
