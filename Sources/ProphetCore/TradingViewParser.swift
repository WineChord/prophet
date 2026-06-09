import Foundation

private let quoteDataMethod = "qsd"
private let timescaleUpdateMethod = "timescale_update"
private let criticalErrorMethod = "critical_error"
private let symbolErrorMethod = "symbol_error"
private let seriesErrorMethod = "series_error"
private let seriesCompletedMethod = "series_completed"
private let quotePayloadValuesKey = "v"
private let quoteNameKey = "n"
private let quoteLastPriceKey = "lp"
private let quoteChangeKey = "ch"
private let quoteChangePercentKey = "chp"
private let quoteSessionKey = "current_session"
private let quoteLastPriceTimeKey = "lp_time"
private let quoteCurrencyCodeKey = "currency_code"
private let quoteShortNameKey = "short_name"
private let quoteDescriptionKey = "description"
private let quoteExchangeKey = "exchange"
private let quoteTimezoneKey = "timezone"
private let seriesValuesKey = "s"
private let barValuesKey = "v"
private let minimumBarFieldCount = 5
private let barTimestampIndex = 0
private let barOpenIndex = 1
private let barHighIndex = 2
private let barLowIndex = 3
private let barCloseIndex = 4
private let barVolumeIndex = 5

public struct TradingViewQuote: Equatable {
	public var symbol: String?
	public var displaySymbol: String?
	public var description: String?
	public var exchange: String?
	public var lastPrice: Double?
	public var change: Double?
	public var changePercent: Double?
	public var session: MarketSession
	public var lastTradeTime: Date?
	public var currencyCode: String?
	public var timeZoneIdentifier: String?

	public init(
		symbol: String? = nil,
		displaySymbol: String? = nil,
		description: String? = nil,
		exchange: String? = nil,
		lastPrice: Double? = nil,
		change: Double? = nil,
		changePercent: Double? = nil,
		session: MarketSession = .unknown,
		lastTradeTime: Date? = nil,
		currencyCode: String? = nil,
		timeZoneIdentifier: String? = nil
	) {
		self.symbol = symbol
		self.displaySymbol = displaySymbol
		self.description = description
		self.exchange = exchange
		self.lastPrice = lastPrice
		self.change = change
		self.changePercent = changePercent
		self.session = session
		self.lastTradeTime = lastTradeTime
		self.currencyCode = currencyCode
		self.timeZoneIdentifier = timeZoneIdentifier
	}
}

public enum TradingViewParser {
	public static func bars(from frame: TradingViewFrame) -> [PriceBar] {
		guard frame.method == timescaleUpdateMethod,
		      frame.parameters.count > 1,
		      let payload = frame.parameters[1] as? [String: Any] else {
			return []
		}

		var bars: [PriceBar] = []
		for value in payload.values {
			guard let series = value as? [String: Any],
			      let rows = series[seriesValuesKey] as? [[String: Any]] else {
				continue
			}
			bars.append(contentsOf: rows.compactMap(bar(from:)))
		}

		return bars.sorted { left, right in
			left.timestamp < right.timestamp
		}
	}

	public static func quote(from frame: TradingViewFrame) -> TradingViewQuote? {
		guard frame.method == quoteDataMethod,
		      frame.parameters.count > 1,
		      let payload = frame.parameters[1] as? [String: Any],
		      let values = payload[quotePayloadValuesKey] as? [String: Any] else {
			return nil
		}

		let lastPriceTime = doubleValue(values[quoteLastPriceTimeKey]).map(Date.init(timeIntervalSince1970:))
		return TradingViewQuote(
			symbol: payload[quoteNameKey] as? String,
			displaySymbol: values[quoteShortNameKey] as? String,
			description: values[quoteDescriptionKey] as? String,
			exchange: values[quoteExchangeKey] as? String,
			lastPrice: doubleValue(values[quoteLastPriceKey]),
			change: doubleValue(values[quoteChangeKey]),
			changePercent: doubleValue(values[quoteChangePercentKey]),
			session: MarketSession(tradingViewValue: values[quoteSessionKey] as? String),
			lastTradeTime: lastPriceTime,
			currencyCode: values[quoteCurrencyCodeKey] as? String,
			timeZoneIdentifier: values[quoteTimezoneKey] as? String
		)
	}

	public static func serverError(from frame: TradingViewFrame) -> String? {
		switch frame.method {
		case criticalErrorMethod, symbolErrorMethod, seriesErrorMethod:
			return frame.parameters.map(String.init(describing:)).joined(separator: " ")
		default:
			return nil
		}
	}

	public static func isSeriesCompleted(_ frame: TradingViewFrame) -> Bool {
		frame.method == seriesCompletedMethod
	}

	private static func bar(from row: [String: Any]) -> PriceBar? {
		guard let values = row[barValuesKey] as? [Any],
		      values.count >= minimumBarFieldCount,
		      let timestamp = doubleValue(values[barTimestampIndex]),
		      let open = doubleValue(values[barOpenIndex]),
		      let high = doubleValue(values[barHighIndex]),
		      let low = doubleValue(values[barLowIndex]),
		      let close = doubleValue(values[barCloseIndex]) else {
			return nil
		}

		return PriceBar(
			timestamp: timestamp,
			open: open,
			high: high,
			low: low,
			close: close,
			volume: values.count > barVolumeIndex ? doubleValue(values[barVolumeIndex]) : nil
		)
	}
}

private func doubleValue(_ value: Any?) -> Double? {
	switch value {
	case let value as Double:
		return value
	case let value as Float:
		return Double(value)
	case let value as Int:
		return Double(value)
	case let value as Int64:
		return Double(value)
	case let value as NSNumber:
		return value.doubleValue
	case let value as String:
		return Double(value)
	default:
		return nil
	}
}
