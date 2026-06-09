import Foundation

public enum ProphetDefaults {
	public static let appName = "Prophet"
	public static let requestedSymbol = "NASDAQ:RKLB"
	public static let updateInterval: TimeInterval = 15
	public static let barCount = 1440
	public static let statusItemWidth = 72.0
	public static let sparklineHeight = 18.0
	public static let currencyCode = "USD"
}

private let minimumUpdateInterval: TimeInterval = 5
private let minimumBarCount = 60
private let maximumBarCount = 3000
private let minimumStatusItemWidth = 48.0
private let maximumStatusItemWidth = 120.0
private let environmentSymbolKey = "PROPHET_SYMBOL"
private let environmentUpdateIntervalKey = "PROPHET_UPDATE_INTERVAL"
private let environmentBarCountKey = "PROPHET_BAR_COUNT"
private let environmentStatusItemWidthKey = "PROPHET_STATUS_WIDTH"
private let configurationDirectoryName = "Prophet"
private let configurationFileName = "config.json"

public struct AppConfiguration: Equatable {
	public let appName: String
	public let requestedSymbol: String
	public let updateInterval: TimeInterval
	public let barCount: Int
	public let statusItemWidth: Double

	public init(
		appName: String = ProphetDefaults.appName,
		requestedSymbol: String = ProphetDefaults.requestedSymbol,
		updateInterval: TimeInterval = ProphetDefaults.updateInterval,
		barCount: Int = ProphetDefaults.barCount,
		statusItemWidth: Double = ProphetDefaults.statusItemWidth
	) {
		self.appName = appName
		self.requestedSymbol = requestedSymbol
		self.updateInterval = updateInterval
		self.barCount = barCount
		self.statusItemWidth = statusItemWidth
	}

	public static func load(
		environment: [String: String] = ProcessInfo.processInfo.environment,
		configURL: URL? = defaultConfigURL()
	) -> AppConfiguration {
		let fileValues = configURL.flatMap { AppConfigurationFile.load(from: $0) } ?? AppConfigurationFile()

		let requestedSymbol = nonEmpty(environment[environmentSymbolKey])
			?? nonEmpty(fileValues.symbol)
			?? ProphetDefaults.requestedSymbol
		let updateInterval = boundedTimeInterval(
			environment[environmentUpdateIntervalKey],
			fileValue: fileValues.updateInterval,
			defaultValue: ProphetDefaults.updateInterval,
			minimumValue: minimumUpdateInterval
		)
		let barCount = boundedInteger(
			environment[environmentBarCountKey],
			fileValue: fileValues.barCount,
			defaultValue: ProphetDefaults.barCount,
			minimumValue: minimumBarCount,
			maximumValue: maximumBarCount
		)
		let statusItemWidth = boundedDouble(
			environment[environmentStatusItemWidthKey],
			fileValue: fileValues.statusItemWidth,
			defaultValue: ProphetDefaults.statusItemWidth,
			minimumValue: minimumStatusItemWidth,
			maximumValue: maximumStatusItemWidth
		)

		return AppConfiguration(
			requestedSymbol: requestedSymbol,
			updateInterval: updateInterval,
			barCount: barCount,
			statusItemWidth: statusItemWidth
		)
	}

	public static func defaultConfigURL() -> URL? {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
			.first?
			.appendingPathComponent(configurationDirectoryName, isDirectory: true)
			.appendingPathComponent(configurationFileName, isDirectory: false)
	}
}

private struct AppConfigurationFile: Decodable {
	let symbol: String?
	let updateInterval: TimeInterval?
	let barCount: Int?
	let statusItemWidth: Double?

	init(
		symbol: String? = nil,
		updateInterval: TimeInterval? = nil,
		barCount: Int? = nil,
		statusItemWidth: Double? = nil
	) {
		self.symbol = symbol
		self.updateInterval = updateInterval
		self.barCount = barCount
		self.statusItemWidth = statusItemWidth
	}

	static func load(from url: URL) -> AppConfigurationFile? {
		guard let data = try? Data(contentsOf: url) else {
			return nil
		}
		return try? JSONDecoder().decode(AppConfigurationFile.self, from: data)
	}
}

private func nonEmpty(_ value: String?) -> String? {
	guard let value else {
		return nil
	}
	let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
	return trimmedValue.isEmpty ? nil : trimmedValue
}

private func boundedTimeInterval(
	_ environmentValue: String?,
	fileValue: TimeInterval?,
	defaultValue: TimeInterval,
	minimumValue: TimeInterval
) -> TimeInterval {
	let parsedValue = environmentValue.flatMap(TimeInterval.init) ?? fileValue ?? defaultValue
	return max(parsedValue, minimumValue)
}

private func boundedInteger(
	_ environmentValue: String?,
	fileValue: Int?,
	defaultValue: Int,
	minimumValue: Int,
	maximumValue: Int
) -> Int {
	let parsedValue = environmentValue.flatMap(Int.init) ?? fileValue ?? defaultValue
	return min(max(parsedValue, minimumValue), maximumValue)
}

private func boundedDouble(
	_ environmentValue: String?,
	fileValue: Double?,
	defaultValue: Double,
	minimumValue: Double,
	maximumValue: Double
) -> Double {
	let parsedValue = environmentValue.flatMap(Double.init) ?? fileValue ?? defaultValue
	return min(max(parsedValue, minimumValue), maximumValue)
}
