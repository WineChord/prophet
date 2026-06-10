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
private let quotePremarketPriceKey = "premarket_close"
private let quotePremarketChangeKey = "premarket_change"
private let quotePremarketChangePercentKey = "premarket_change_percent"
private let quotePostmarketPriceKey = "postmarket_close"
private let quotePostmarketChangeKey = "postmarket_change"
private let quotePostmarketChangePercentKey = "postmarket_change_percent"
private let seriesValuesKey = "s"
private let barValuesKey = "v"
private let minimumBarFieldCount = 5
private let staleQuoteBarLeadThreshold: TimeInterval = 60
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
	public var preMarketPrice: Double?
	public var preMarketChange: Double?
	public var preMarketChangePercent: Double?
	public var postMarketPrice: Double?
	public var postMarketChange: Double?
	public var postMarketChangePercent: Double?
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
		preMarketPrice: Double? = nil,
		preMarketChange: Double? = nil,
		preMarketChangePercent: Double? = nil,
		postMarketPrice: Double? = nil,
		postMarketChange: Double? = nil,
		postMarketChangePercent: Double? = nil,
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
		self.preMarketPrice = preMarketPrice
		self.preMarketChange = preMarketChange
		self.preMarketChangePercent = preMarketChangePercent
		self.postMarketPrice = postMarketPrice
		self.postMarketChange = postMarketChange
		self.postMarketChangePercent = postMarketChangePercent
		self.session = session
		self.lastTradeTime = lastTradeTime
		self.currencyCode = currencyCode
		self.timeZoneIdentifier = timeZoneIdentifier
	}

	public func merging(_ quote: TradingViewQuote) -> TradingViewQuote {
		TradingViewQuote(
			symbol: quote.symbol ?? symbol,
			displaySymbol: quote.displaySymbol ?? displaySymbol,
			description: quote.description ?? description,
			exchange: quote.exchange ?? exchange,
			lastPrice: quote.lastPrice ?? lastPrice,
			change: quote.change ?? change,
			changePercent: quote.changePercent ?? changePercent,
			preMarketPrice: quote.preMarketPrice ?? preMarketPrice,
			preMarketChange: quote.preMarketChange ?? preMarketChange,
			preMarketChangePercent: quote.preMarketChangePercent ?? preMarketChangePercent,
			postMarketPrice: quote.postMarketPrice ?? postMarketPrice,
			postMarketChange: quote.postMarketChange ?? postMarketChange,
			postMarketChangePercent: quote.postMarketChangePercent ?? postMarketChangePercent,
			session: quote.session == .unknown ? session : quote.session,
			lastTradeTime: quote.lastTradeTime ?? lastTradeTime,
			currencyCode: quote.currencyCode ?? currencyCode,
			timeZoneIdentifier: quote.timeZoneIdentifier ?? timeZoneIdentifier
		)
	}

	public var effectiveLastPrice: Double? {
		switch session {
		case .preMarket:
			return preMarketPrice ?? lastPrice
		case .postMarket, .extended:
			return postMarketPrice ?? preMarketPrice ?? lastPrice
		case .regular:
			return lastPrice
		case .closed, .unknown:
			return postMarketPrice ?? preMarketPrice ?? lastPrice
		}
	}

	public var effectiveChange: Double? {
		switch session {
		case .preMarket:
			return preMarketChange ?? change
		case .postMarket, .extended:
			return postMarketChange ?? preMarketChange ?? change
		case .regular:
			return change
		case .closed, .unknown:
			return postMarketChange ?? preMarketChange ?? change
		}
	}

	public var effectiveChangePercent: Double? {
		switch session {
		case .preMarket:
			return preMarketChangePercent ?? changePercent
		case .postMarket, .extended:
			return postMarketChangePercent ?? preMarketChangePercent ?? changePercent
		case .regular:
			return changePercent
		case .closed, .unknown:
			return postMarketChangePercent ?? preMarketChangePercent ?? changePercent
		}
	}

	public var effectiveBaselinePrice: Double? {
		if let price = effectiveLastPrice, let change = effectiveChange {
			return price - change
		}
		if let price = effectiveLastPrice, let changePercent = effectiveChangePercent {
			let denominator = 1 + changePercent / 100
			if denominator != 0 {
				return price / denominator
			}
		}
		return regularBaselinePrice
	}

	public func resolvedValues(with bars: [PriceBar]) -> TradingViewResolvedQuote {
		guard shouldPreferLatestBar(from: bars),
		      let latestBar = bars.last else {
			return TradingViewResolvedQuote(
				lastPrice: effectiveLastPrice,
				change: effectiveChange,
				changePercent: effectiveChangePercent,
				lastTradeTime: lastTradeTime
			)
		}

		let baseline = regularBaselinePrice ?? effectiveBaselinePrice
		let resolvedChange = baseline.map { latestBar.close - $0 } ?? effectiveChange
		let resolvedChangePercent = percentageChange(
			change: resolvedChange,
			baseline: baseline
		) ?? effectiveChangePercent
		return TradingViewResolvedQuote(
			lastPrice: latestBar.close,
			change: resolvedChange,
			changePercent: resolvedChangePercent,
			lastTradeTime: Date(timeIntervalSince1970: latestBar.timestamp)
		)
	}

	private var regularBaselinePrice: Double? {
		if let lastPrice, let change {
			return lastPrice - change
		}
		if let lastPrice, let changePercent {
			let denominator = 1 + changePercent / 100
			if denominator != 0 {
				return lastPrice / denominator
			}
		}
		return nil
	}

	private func shouldPreferLatestBar(from bars: [PriceBar]) -> Bool {
		guard session != .regular,
		      let latestBar = bars.last,
		      latestBar.close != effectiveLastPrice else {
			return false
		}
		guard let lastTradeTime else {
			return true
		}
		return latestBar.timestamp > lastTradeTime.timeIntervalSince1970 + staleQuoteBarLeadThreshold
	}
}

public struct TradingViewResolvedQuote: Equatable {
	public let lastPrice: Double?
	public let change: Double?
	public let changePercent: Double?
	public let lastTradeTime: Date?
}

private func percentageChange(change: Double?, baseline: Double?) -> Double? {
	guard let change,
	      let baseline,
	      baseline != 0 else {
		return nil
	}
	return change / baseline * 100
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
			preMarketPrice: doubleValue(values[quotePremarketPriceKey]),
			preMarketChange: doubleValue(values[quotePremarketChangeKey]),
			preMarketChangePercent: doubleValue(values[quotePremarketChangePercentKey]),
			postMarketPrice: doubleValue(values[quotePostmarketPriceKey]),
			postMarketChange: doubleValue(values[quotePostmarketChangeKey]),
			postMarketChangePercent: doubleValue(values[quotePostmarketChangePercentKey]),
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
