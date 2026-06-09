import Foundation

private let priceFormatterMinimumFractionDigits = 2
private let priceFormatterMaximumFractionDigits = 4
private let percentFormatterMinimumFractionDigits = 2
private let percentFormatterMaximumFractionDigits = 2
private let statusPriceFormatterMinimumFractionDigits = 2
private let statusPriceFormatterMaximumFractionDigits = 2
private let baselineUnavailableText = "Baseline unavailable"

public final class MarketSnapshotFormatter {
	private let priceFormatter = NumberFormatter()
	private let percentFormatter = NumberFormatter()
	private let statusPriceFormatter = NumberFormatter()

	public init() {
		priceFormatter.numberStyle = .currency
		priceFormatter.minimumFractionDigits = priceFormatterMinimumFractionDigits
		priceFormatter.maximumFractionDigits = priceFormatterMaximumFractionDigits

		percentFormatter.numberStyle = .decimal
		percentFormatter.minimumFractionDigits = percentFormatterMinimumFractionDigits
		percentFormatter.maximumFractionDigits = percentFormatterMaximumFractionDigits

		statusPriceFormatter.numberStyle = .decimal
		statusPriceFormatter.minimumFractionDigits = statusPriceFormatterMinimumFractionDigits
		statusPriceFormatter.maximumFractionDigits = statusPriceFormatterMaximumFractionDigits
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

		let baselineSuffix = baselineSuffix(for: snapshot)
		let sign = signText(for: changePercent)
		return "\(snapshot.instrument.displaySymbol) \(formattedPrice) \(sign)\(formattedPercent)%\(baselineSuffix)"
	}

	public func baselineText(for snapshot: MarketSnapshot) -> String {
		priceFormatter.currencyCode = snapshot.currencyCode
		guard let baseline = snapshot.effectiveBaselinePrice,
		      let formattedBaseline = priceFormatter.string(
			from: NSNumber(value: baseline)
		      ) else {
			return baselineUnavailableText
		}
		return "Baseline \(formattedBaseline)"
	}

	public func statusPriceText(
		for snapshot: MarketSnapshot,
		includesPercent: Bool = false
	) -> String? {
		guard let price = snapshot.effectiveLastPrice else {
			return nil
		}
		let formattedPrice = statusPriceFormatter.string(from: NSNumber(value: price)) ?? String(price)
		guard includesPercent,
		      let changePercent = snapshot.effectiveChangePercent,
		      let formattedPercent = percentFormatter.string(
			from: NSNumber(value: abs(changePercent))
		      ) else {
			return formattedPrice
		}
		return "\(formattedPrice) \(signText(for: changePercent))\(formattedPercent)%"
	}

	private func baselineSuffix(for snapshot: MarketSnapshot) -> String {
		let text = baselineText(for: snapshot)
		guard text != baselineUnavailableText else {
			return ""
		}
		return " • \(text)"
	}

	private func signText(for value: Double) -> String {
		value >= 0 ? "+" : "-"
	}
}
