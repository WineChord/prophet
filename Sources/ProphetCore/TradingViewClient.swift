import Foundation

private let webSocketEndpoint = "wss://data.tradingview.com/socket.io/websocket"
private let originHeaderName = "Origin"
private let originHeaderValue = "https://www.tradingview.com"
private let userAgentHeaderName = "User-Agent"
private let userAgentHeaderValue = "Prophet/1.0"
private let unauthorizedUserToken = "unauthorized_user_token"
private let chartSessionPrefix = "cs_"
private let quoteSessionPrefix = "qs_"
private let chartSessionLength = 12
private let symbolAlias = "symbol_1"
private let seriesName = "series_1"
private let minuteResolution = "1"
private let emptySession = ""
private let exchangeTimezone = "exchange"
private let symbolAdjustmentKey = "adjustment"
private let symbolSessionKey = "session"
private let symbolSymbolKey = "symbol"
private let splitsAdjustment = "splits"
private let extendedSession = "extended"
private let chartCreateSessionMethod = "chart_create_session"
private let createSeriesMethod = "create_series"
private let quoteAddSymbolsMethod = "quote_add_symbols"
private let quoteCreateSessionMethod = "quote_create_session"
private let quoteFastSymbolsMethod = "quote_fast_symbols"
private let quoteSetFieldsMethod = "quote_set_fields"
private let resolveSymbolMethod = "resolve_symbol"
private let setAuthTokenMethod = "set_auth_token"
private let switchTimezoneMethod = "switch_timezone"
private let quoteChangeField = "ch"
private let quoteChangePercentField = "chp"
private let quoteCurrencyCodeField = "currency_code"
private let quoteCurrentSessionField = "current_session"
private let quoteDescriptionField = "description"
private let quoteExchangeField = "exchange"
private let quoteLastPriceField = "lp"
private let quoteLastPriceTimeField = "lp_time"
private let quotePostmarketCloseField = "postmarket_close"
private let quotePostmarketChangeField = "postmarket_change"
private let quotePostmarketChangePercentField = "postmarket_change_percent"
private let quotePremarketCloseField = "premarket_close"
private let quotePremarketChangeField = "premarket_change"
private let quotePremarketChangePercentField = "premarket_change_percent"
private let quoteShortNameField = "short_name"
private let quoteTimezoneField = "timezone"
private let quoteVolumeField = "volume"
private let fetchTimeoutNanoseconds: UInt64 = 10_000_000_000

public enum TradingViewError: Error, LocalizedError {
	case invalidURL(String)
	case unresolvedSymbol(String)
	case server(String)
	case timeout
	case emptyBars(String)

	public var errorDescription: String? {
		switch self {
		case .invalidURL(let value):
			return "Invalid TradingView URL: \(value)"
		case .unresolvedSymbol(let value):
			return "Unable to resolve TradingView symbol: \(value)"
		case .server(let value):
			return "TradingView returned an error: \(value)"
		case .timeout:
			return "Timed out while waiting for TradingView data"
		case .emptyBars(let value):
			return "TradingView returned no chart bars for \(value)"
		}
	}
}

public protocol MarketDataFetching {
	func fetchSnapshot(
		for requestedSymbol: String,
		barCount: Int
	) async throws -> MarketSnapshot
}

public final class TradingViewClient: MarketDataFetching {
	private let urlSession: URLSession
	private let symbolResolver: TradingViewSymbolResolving

	public init(
		urlSession: URLSession = .shared,
		symbolResolver: TradingViewSymbolResolving = TradingViewSymbolResolver()
	) {
		self.urlSession = urlSession
		self.symbolResolver = symbolResolver
	}

	public func fetchSnapshot(
		for requestedSymbol: String,
		barCount: Int
	) async throws -> MarketSnapshot {
		let instrument = try await symbolResolver.resolve(requestedSymbol)
		return try await withThrowingTaskGroup(of: MarketSnapshot.self) { group in
			group.addTask {
				try await self.fetchSnapshot(for: instrument, barCount: barCount)
			}
			group.addTask {
				try await Task.sleep(nanoseconds: fetchTimeoutNanoseconds)
				throw TradingViewError.timeout
			}

			guard let snapshot = try await group.next() else {
				throw TradingViewError.timeout
			}
			group.cancelAll()
			return snapshot
		}
	}

	public func quoteStream(
		for requestedSymbol: String
	) -> AsyncThrowingStream<TradingViewQuote, Error> {
		AsyncThrowingStream { continuation in
			let streamTask = Task {
				do {
					let instrument = try await symbolResolver.resolve(requestedSymbol)
					try await streamQuotes(
						for: instrument,
						continuation: continuation
					)
					continuation.finish()
				} catch {
					if Task.isCancelled {
						continuation.finish()
					} else {
						continuation.finish(throwing: error)
					}
				}
			}

			continuation.onTermination = { _ in
				streamTask.cancel()
			}
		}
	}

	private func fetchSnapshot(
		for instrument: Instrument,
		barCount: Int
	) async throws -> MarketSnapshot {
		guard let url = URL(string: webSocketEndpoint) else {
			throw TradingViewError.invalidURL(webSocketEndpoint)
		}

		var request = URLRequest(url: url)
		request.setValue(originHeaderValue, forHTTPHeaderField: originHeaderName)
		request.setValue(userAgentHeaderValue, forHTTPHeaderField: userAgentHeaderName)

		let task = urlSession.webSocketTask(with: request)
		task.resume()
		defer {
			task.cancel(with: .normalClosure, reason: nil)
		}

		let chartSession = randomSession(prefix: chartSessionPrefix)
		let quoteSession = randomSession(prefix: quoteSessionPrefix)
		for message in try setupMessages(
			instrument: instrument,
			barCount: barCount,
			chartSession: chartSession,
			quoteSession: quoteSession
		) {
			try await task.send(.string(message))
		}

		var bars: [PriceBar] = []
		var quote = TradingViewQuote()
		while !Task.isCancelled {
			let message = try await task.receive()
			let text = try textMessage(from: message)
			let frames = try TradingViewCodec.decodeFrames(from: text)

			for frame in frames {
				if let heartbeat = frame.heartbeat {
					try await task.send(.string(heartbeat))
					continue
				}
				if let serverError = TradingViewParser.serverError(from: frame) {
					throw TradingViewError.server(serverError)
				}
				if let nextQuote = TradingViewParser.quote(from: frame) {
					quote = nextQuote
					continue
				}
				let nextBars = TradingViewParser.bars(from: frame)
				if !nextBars.isEmpty {
					bars = nextBars
					continue
				}
				if TradingViewParser.isSeriesCompleted(frame) {
					return try snapshot(
						instrument: instrument,
						bars: bars,
						quote: quote
					)
				}
			}
		}

		throw TradingViewError.timeout
	}

	private func streamQuotes(
		for instrument: Instrument,
		continuation: AsyncThrowingStream<TradingViewQuote, Error>.Continuation
	) async throws {
		guard let url = URL(string: webSocketEndpoint) else {
			throw TradingViewError.invalidURL(webSocketEndpoint)
		}

		var request = URLRequest(url: url)
		request.setValue(originHeaderValue, forHTTPHeaderField: originHeaderName)
		request.setValue(userAgentHeaderValue, forHTTPHeaderField: userAgentHeaderName)

		let task = urlSession.webSocketTask(with: request)
		task.resume()
		defer {
			task.cancel(with: .normalClosure, reason: nil)
		}

		let quoteSession = randomSession(prefix: quoteSessionPrefix)
		for message in try quoteSetupMessages(
			symbol: instrument.symbol,
			quoteSession: quoteSession
		) {
			try await task.send(.string(message))
		}

		var quote = TradingViewQuote()
		while !Task.isCancelled {
			let message = try await task.receive()
			let text = try textMessage(from: message)
			let frames = try TradingViewCodec.decodeFrames(from: text)

			for frame in frames {
				if let heartbeat = frame.heartbeat {
					try await task.send(.string(heartbeat))
					continue
				}
				if let serverError = TradingViewParser.serverError(from: frame) {
					throw TradingViewError.server(serverError)
				}
				if let nextQuote = TradingViewParser.quote(from: frame) {
					quote = quote.merging(nextQuote)
					continuation.yield(quote)
				}
			}
		}
	}

	private func setupMessages(
		instrument: Instrument,
		barCount: Int,
		chartSession: String,
		quoteSession: String
	) throws -> [String] {
		let resolvedSymbol = try resolvedSymbolPayload(for: instrument.symbol)
		return try [
			TradingViewCodec.encode(
				method: setAuthTokenMethod,
				parameters: [unauthorizedUserToken]
			),
			TradingViewCodec.encode(
				method: chartCreateSessionMethod,
				parameters: [chartSession, emptySession]
			),
			TradingViewCodec.encode(
				method: quoteCreateSessionMethod,
				parameters: [quoteSession]
			),
			TradingViewCodec.encode(
				method: quoteSetFieldsMethod,
				parameters: [quoteSession] + quoteFields()
			),
			TradingViewCodec.encode(
				method: quoteAddSymbolsMethod,
				parameters: [quoteSession, instrument.symbol]
			),
			TradingViewCodec.encode(
				method: quoteFastSymbolsMethod,
				parameters: [quoteSession, instrument.symbol]
			),
			TradingViewCodec.encode(
				method: resolveSymbolMethod,
				parameters: [chartSession, symbolAlias, resolvedSymbol]
			),
			TradingViewCodec.encode(
				method: createSeriesMethod,
				parameters: [
					chartSession,
					seriesName,
					seriesName,
					symbolAlias,
					minuteResolution,
					barCount,
				]
			),
			TradingViewCodec.encode(
				method: switchTimezoneMethod,
				parameters: [chartSession, exchangeTimezone]
			),
		]
	}

	private func quoteSetupMessages(
		symbol: String,
		quoteSession: String
	) throws -> [String] {
		try [
			TradingViewCodec.encode(
				method: setAuthTokenMethod,
				parameters: [unauthorizedUserToken]
			),
			TradingViewCodec.encode(
				method: quoteCreateSessionMethod,
				parameters: [quoteSession]
			),
			TradingViewCodec.encode(
				method: quoteSetFieldsMethod,
				parameters: [quoteSession] + quoteFields()
			),
			TradingViewCodec.encode(
				method: quoteAddSymbolsMethod,
				parameters: [quoteSession, symbol]
			),
			TradingViewCodec.encode(
				method: quoteFastSymbolsMethod,
				parameters: [quoteSession, symbol]
			),
		]
	}

	private func snapshot(
		instrument: Instrument,
		bars: [PriceBar],
		quote: TradingViewQuote
	) throws -> MarketSnapshot {
		guard !bars.isEmpty else {
			throw TradingViewError.emptyBars(instrument.symbol)
		}

		let mergedInstrument = Instrument(
			symbol: quote.symbol ?? instrument.symbol,
			displaySymbol: quote.displaySymbol ?? instrument.displaySymbol,
			description: quote.description ?? instrument.description,
			exchange: quote.exchange ?? instrument.exchange
		)
		let timeZoneIdentifier = quote.timeZoneIdentifier ?? ProphetDefaults.exchangeTimeZoneIdentifier
		let overviewBars = MarketTimeline(timeZoneIdentifier: timeZoneIdentifier)
			.overviewBars(from: bars)
		return MarketSnapshot(
			instrument: mergedInstrument,
			bars: overviewBars,
			lastPrice: quote.lastPrice,
			change: quote.change,
			changePercent: quote.changePercent,
			session: quote.session,
			lastTradeTime: quote.lastTradeTime,
			currencyCode: quote.currencyCode ?? ProphetDefaults.currencyCode,
			timeZoneIdentifier: timeZoneIdentifier
		)
	}
}

private func resolvedSymbolPayload(for symbol: String) throws -> String {
	let payload: [String: Any] = [
		symbolSymbolKey: symbol,
		symbolAdjustmentKey: splitsAdjustment,
		symbolSessionKey: extendedSession,
	]
	let data = try JSONSerialization.data(withJSONObject: payload, options: [])
	return "=" + String(decoding: data, as: UTF8.self)
}

private func quoteFields() -> [String] {
	[
		quoteChangeField,
		quoteChangePercentField,
		quoteCurrencyCodeField,
		quoteCurrentSessionField,
		quoteDescriptionField,
		quoteExchangeField,
		quoteLastPriceField,
		quoteLastPriceTimeField,
		quotePostmarketCloseField,
		quotePostmarketChangeField,
		quotePostmarketChangePercentField,
		quotePremarketCloseField,
		quotePremarketChangeField,
		quotePremarketChangePercentField,
		quoteShortNameField,
		quoteTimezoneField,
		quoteVolumeField,
	]
}

private func randomSession(prefix: String) -> String {
	let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
	let randomSuffix = (0..<chartSessionLength)
		.map { _ in String(alphabet.randomElement() ?? "a") }
		.joined()
	return prefix + randomSuffix
}

private func textMessage(
	from message: URLSessionWebSocketTask.Message
) throws -> String {
	switch message {
	case .string(let text):
		return text
	case .data(let data):
		return String(decoding: data, as: UTF8.self)
	@unknown default:
		throw TradingViewError.server("unknown websocket message")
	}
}
