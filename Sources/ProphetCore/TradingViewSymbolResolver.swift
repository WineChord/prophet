import Foundation

private let scannerEndpoint = "https://scanner.tradingview.com/america/scan"
private let contentTypeHeaderName = "Content-Type"
private let jsonContentType = "application/json"
private let symbolSeparatorCharacter: Character = ":"
private let nasdaqExchange = "NASDAQ"
private let nyseExchange = "NYSE"
private let amexExchange = "AMEX"
private let otcExchange = "OTC"
private let scannerSymbolsKey = "symbols"
private let scannerTickersKey = "tickers"
private let scannerQueryKey = "query"
private let scannerTypesKey = "types"
private let scannerColumnsKey = "columns"
private let scannerDataKey = "data"
private let scannerSymbolKey = "s"
private let scannerValuesKey = "d"
private let scannerNameColumn = "name"
private let scannerExchangeColumn = "exchange"
private let scannerDescriptionColumn = "description"

public protocol TradingViewSymbolResolving {
	func resolve(_ requestedSymbol: String) async throws -> Instrument
}

public final class TradingViewSymbolResolver: TradingViewSymbolResolving {
	private let urlSession: URLSession

	public init(urlSession: URLSession = .shared) {
		self.urlSession = urlSession
	}

	public func resolve(_ requestedSymbol: String) async throws -> Instrument {
		let candidates = TradingViewSymbolResolver.candidateSymbols(for: requestedSymbol)
		guard !candidates.isEmpty else {
			throw TradingViewError.unresolvedSymbol(requestedSymbol)
		}

		let instruments = try await scan(candidates: candidates)
		if let instrument = preferredInstrument(from: instruments, candidates: candidates) {
			return instrument
		}

		if requestedSymbol.contains(symbolSeparatorCharacter) {
			return Instrument(symbol: requestedSymbol.uppercased())
		}
		return Instrument(symbol: candidates[0])
	}

	public static func candidateSymbols(for requestedSymbol: String) -> [String] {
		let trimmedSymbol = requestedSymbol
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.uppercased()
		guard !trimmedSymbol.isEmpty else {
			return []
		}
		if trimmedSymbol.contains(symbolSeparatorCharacter) {
			return [trimmedSymbol]
		}
		return [
			"\(nasdaqExchange):\(trimmedSymbol)",
			"\(nyseExchange):\(trimmedSymbol)",
			"\(amexExchange):\(trimmedSymbol)",
			"\(otcExchange):\(trimmedSymbol)",
		]
	}

	private func scan(candidates: [String]) async throws -> [Instrument] {
		guard let url = URL(string: scannerEndpoint) else {
			throw TradingViewError.invalidURL(scannerEndpoint)
		}

		let payload: [String: Any] = [
			scannerSymbolsKey: [
				scannerTickersKey: candidates,
				scannerQueryKey: [
					scannerTypesKey: [],
				],
			],
			scannerColumnsKey: [
				scannerNameColumn,
				scannerExchangeColumn,
				scannerDescriptionColumn,
			],
		]
		let body = try JSONSerialization.data(withJSONObject: payload, options: [])

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(jsonContentType, forHTTPHeaderField: contentTypeHeaderName)
		request.httpBody = body

		let (data, _) = try await urlSession.data(for: request)
		let object = try JSONSerialization.jsonObject(with: data, options: [])
		guard let response = object as? [String: Any],
		      let rows = response[scannerDataKey] as? [[String: Any]] else {
			return []
		}

		return rows.compactMap { row in
			guard let symbol = row[scannerSymbolKey] as? String else {
				return nil
			}
			let values = row[scannerValuesKey] as? [Any] ?? []
			return Instrument(
				symbol: symbol,
				displaySymbol: values.first as? String,
				description: string(at: 2, in: values),
				exchange: string(at: 1, in: values)
			)
		}
	}

	private func preferredInstrument(
		from instruments: [Instrument],
		candidates: [String]
	) -> Instrument? {
		for candidate in candidates {
			if let instrument = instruments.first(where: { $0.symbol == candidate }) {
				return instrument
			}
		}
		return instruments.first
	}
}

private func string(at index: Int, in values: [Any]) -> String? {
	guard values.indices.contains(index) else {
		return nil
	}
	return values[index] as? String
}
