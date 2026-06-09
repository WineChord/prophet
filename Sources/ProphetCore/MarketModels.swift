import Foundation

private let symbolSeparator = ":"

public struct Instrument: Equatable {
	public let symbol: String
	public let displaySymbol: String
	public let description: String?
	public let exchange: String?

	public init(
		symbol: String,
		displaySymbol: String? = nil,
		description: String? = nil,
		exchange: String? = nil
	) {
		self.symbol = symbol
		self.displaySymbol = displaySymbol ?? Instrument.displaySymbol(from: symbol)
		self.description = description
		self.exchange = exchange
	}

	public static func displaySymbol(from symbol: String) -> String {
		guard let separatorRange = symbol.range(of: symbolSeparator) else {
			return symbol
		}
		return String(symbol[separatorRange.upperBound...])
	}
}

public struct PriceBar: Equatable {
	public let timestamp: TimeInterval
	public let open: Double
	public let high: Double
	public let low: Double
	public let close: Double
	public let volume: Double?

	public init(
		timestamp: TimeInterval,
		open: Double,
		high: Double,
		low: Double,
		close: Double,
		volume: Double? = nil
	) {
		self.timestamp = timestamp
		self.open = open
		self.high = high
		self.low = low
		self.close = close
		self.volume = volume
	}
}

public enum MarketSession: String, Equatable {
	case regular
	case preMarket
	case postMarket
	case extended
	case closed
	case unknown

	public init(tradingViewValue: String?) {
		switch tradingViewValue {
		case "regular":
			self = .regular
		case "pre_market":
			self = .preMarket
		case "post_market":
			self = .postMarket
		case "extended":
			self = .extended
		case "market_closed":
			self = .closed
		default:
			self = .unknown
		}
	}

	public var displayName: String {
		switch self {
		case .regular:
			return "Regular"
		case .preMarket:
			return "Pre-market"
		case .postMarket:
			return "Post-market"
		case .extended:
			return "Extended"
		case .closed:
			return "Closed"
		case .unknown:
			return "Unknown"
		}
	}
}

public struct MarketSnapshot: Equatable {
	public let instrument: Instrument
	public let bars: [PriceBar]
	public let lastPrice: Double?
	public let change: Double?
	public let changePercent: Double?
	public let session: MarketSession
	public let lastTradeTime: Date?
	public let receivedAt: Date
	public let currencyCode: String
	public let timeZoneIdentifier: String

	public init(
		instrument: Instrument,
		bars: [PriceBar],
		lastPrice: Double? = nil,
		change: Double? = nil,
		changePercent: Double? = nil,
		session: MarketSession = .unknown,
		lastTradeTime: Date? = nil,
		receivedAt: Date = Date(),
		currencyCode: String = ProphetDefaults.currencyCode,
		timeZoneIdentifier: String = ProphetDefaults.exchangeTimeZoneIdentifier
	) {
		self.instrument = instrument
		self.bars = bars
		self.lastPrice = lastPrice
		self.change = change
		self.changePercent = changePercent
		self.session = session
		self.lastTradeTime = lastTradeTime
		self.receivedAt = receivedAt
		self.currencyCode = currencyCode
		self.timeZoneIdentifier = timeZoneIdentifier
	}

	public var effectiveLastPrice: Double? {
		bars.last?.close ?? lastPrice
	}

	public var effectiveChange: Double? {
		if let change {
			return change
		}
		guard let firstClose = bars.first?.close, let lastClose = bars.last?.close else {
			return nil
		}
		return lastClose - firstClose
	}

	public var effectiveChangePercent: Double? {
		if let changePercent {
			return changePercent
		}
		guard let firstClose = bars.first?.close, firstClose != 0, let change = effectiveChange else {
			return nil
		}
		return change / firstClose * 100
	}

	public var isUp: Bool? {
		guard let change = effectiveChange else {
			return nil
		}
		return change >= 0
	}
}
