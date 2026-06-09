import Foundation

private let priceFormatterMinimumFractionDigits = 2
private let priceFormatterMaximumFractionDigits = 4
private let percentFormatterMinimumFractionDigits = 2
private let percentFormatterMaximumFractionDigits = 2

public final class MarketSnapshotFormatter {
	private let priceFormatter = NumberFormatter()
	private let percentFormatter = NumberFormatter()

	public init() {
		priceFormatter.numberStyle = .currency
		priceFormatter.minimumFractionDigits = priceFormatterMinimumFractionDigits
		priceFormatter.maximumFractionDigits = priceFormatterMaximumFractionDigits

		percentFormatter.numberStyle = .decimal
		percentFormatter.minimumFractionDigits = percentFormatterMinimumFractionDigits
		percentFormatter.maximumFractionDigits = percentFormatterMaximumFractionDigits
	}

	public func tooltipText(
		for snapshot: MarketSnapshot,
		unavailablePriceText: String = "Price unavailable"
	) -> String {
		guard let price = snapshot.effectiveLastPrice else {
			return "\(snapshot.instrument.displaySymbol) \(unavailablePriceText)"
		}

		priceFormatter.currencyCode = snapshot.currencyCode
		let formattedPrice = priceFormatter.string(from: NSNumber(value: price)) ?? String(price)
		guard let changePercent = snapshot.effectiveChangePercent,
		      let formattedPercent = percentFormatter.string(
		      	from: NSNumber(value: abs(changePercent))
		      ) else {
			return "\(snapshot.instrument.displaySymbol) \(formattedPrice)"
		}

		let sign = changePercent >= 0 ? "+" : "-"
		return "\(snapshot.instrument.displaySymbol) \(formattedPrice) \(sign)\(formattedPercent)%"
	}
}
