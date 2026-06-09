import Foundation

private let frameMarker = "~m~"
private let heartbeatMarker = "~h~"
private let messageMethodKey = "m"
private let messageParametersKey = "p"

public struct TradingViewFrame {
	public let method: String?
	public let parameters: [Any]
	public let rawMessage: [String: Any]?
	public let heartbeat: String?

	public init(
		method: String?,
		parameters: [Any],
		rawMessage: [String: Any]?,
		heartbeat: String? = nil
	) {
		self.method = method
		self.parameters = parameters
		self.rawMessage = rawMessage
		self.heartbeat = heartbeat
	}

	public static func heartbeat(_ value: String) -> TradingViewFrame {
		TradingViewFrame(
			method: nil,
			parameters: [],
			rawMessage: nil,
			heartbeat: value
		)
	}
}

public enum TradingViewCodec {
	public static func encode(method: String, parameters: [Any]) throws -> String {
		let payload: [String: Any] = [
			messageMethodKey: method,
			messageParametersKey: parameters,
		]
		let data = try JSONSerialization.data(withJSONObject: payload, options: [])
		let body = String(decoding: data, as: UTF8.self)
		return "\(frameMarker)\(data.count)\(frameMarker)\(body)"
	}

	public static func decodeFrames(from text: String) throws -> [TradingViewFrame] {
		var frames: [TradingViewFrame] = []
		var cursor = text.startIndex

		while cursor < text.endIndex {
			if text[cursor...].hasPrefix(heartbeatMarker) {
				let nextFrame = text[cursor...].range(of: frameMarker)?.lowerBound
				let endIndex = nextFrame ?? text.endIndex
				frames.append(.heartbeat(String(text[cursor..<endIndex])))
				cursor = endIndex
				continue
			}

			guard text[cursor...].hasPrefix(frameMarker) else {
				cursor = text.index(after: cursor)
				continue
			}

			let lengthStart = text.index(cursor, offsetBy: frameMarker.count)
			guard let lengthEndRange = text[lengthStart...].range(of: frameMarker) else {
				break
			}
			let lengthEnd = lengthEndRange.lowerBound
			guard let length = Int(text[lengthStart..<lengthEnd]) else {
				cursor = lengthEndRange.upperBound
				continue
			}

			let bodyStart = lengthEndRange.upperBound
			guard let bodyEnd = text.index(bodyStart, offsetBy: length, limitedBy: text.endIndex) else {
				break
			}
			let body = String(text[bodyStart..<bodyEnd])
			let data = Data(body.utf8)
			let object = try JSONSerialization.jsonObject(with: data, options: [])
			if let message = object as? [String: Any] {
				let frame = TradingViewFrame(
					method: message[messageMethodKey] as? String,
					parameters: message[messageParametersKey] as? [Any] ?? [],
					rawMessage: message
				)
				frames.append(frame)
			}
			cursor = bodyEnd
		}

		return frames
	}
}
