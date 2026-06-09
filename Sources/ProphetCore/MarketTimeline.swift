import CoreGraphics
import Foundation

private let regularOpenMinute = 9 * 60 + 30
private let regularCloseMinute = 16 * 60
private let weekdayMonday = 2
private let weekdayFriday = 6
private let minimumTimelineRange: TimeInterval = 60
private let maximumContinuousGap: TimeInterval = 20 * 60

public enum BarTradingSession: Equatable {
	case regular
	case extended
}

public struct MarketTimeline {
	public let timeZone: TimeZone

	public init(timeZoneIdentifier: String = ProphetDefaults.exchangeTimeZoneIdentifier) {
		timeZone = TimeZone(identifier: timeZoneIdentifier)
			?? TimeZone(identifier: ProphetDefaults.exchangeTimeZoneIdentifier)
			?? .current
	}

	public func overviewBars(from bars: [PriceBar]) -> [PriceBar] {
		let sortedBars = bars.sorted { left, right in
			left.timestamp < right.timestamp
		}
		guard let startTimestamp = overviewStartTimestamp(for: sortedBars) else {
			return sortedBars
		}
		return sortedBars.filter { bar in
			bar.timestamp >= startTimestamp
		}
	}

	public func session(for timestamp: TimeInterval) -> BarTradingSession {
		let components = calendar.dateComponents(
			[.weekday, .hour, .minute],
			from: Date(timeIntervalSince1970: timestamp)
		)
		guard let weekday = components.weekday,
		      let hour = components.hour,
		      let minute = components.minute,
		      isTradingWeekday(weekday) else {
			return .extended
		}

		let dayMinute = hour * 60 + minute
		if dayMinute >= regularOpenMinute && dayMinute < regularCloseMinute {
			return .regular
		}
		return .extended
	}

	public func canConnect(_ left: PriceBar, _ right: PriceBar) -> Bool {
		right.timestamp - left.timestamp <= maximumContinuousGap
	}

	public var calendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = timeZone
		return calendar
	}

	private func overviewStartTimestamp(for bars: [PriceBar]) -> TimeInterval? {
		guard !bars.isEmpty else {
			return nil
		}
		for bar in bars.reversed() where session(for: bar.timestamp) == .regular {
			return regularOpenTimestamp(onSameDayAs: bar.timestamp)
		}
		return bars.first?.timestamp
	}

	private func regularOpenTimestamp(onSameDayAs timestamp: TimeInterval) -> TimeInterval {
		let date = Date(timeIntervalSince1970: timestamp)
		let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
		var openComponents = DateComponents()
		openComponents.calendar = calendar
		openComponents.timeZone = timeZone
		openComponents.year = dayComponents.year
		openComponents.month = dayComponents.month
		openComponents.day = dayComponents.day
		openComponents.hour = regularOpenMinute / 60
		openComponents.minute = regularOpenMinute % 60
		return calendar.date(from: openComponents)?.timeIntervalSince1970 ?? timestamp
	}

	private func isTradingWeekday(_ weekday: Int) -> Bool {
		weekday >= weekdayMonday && weekday <= weekdayFriday
	}
}

public enum TimelineGeometry {
	public static func points(
		for bars: [PriceBar],
		in size: CGSize,
		padding: CGFloat
	) -> [CGPoint] {
		guard !bars.isEmpty, size.width > 0, size.height > 0 else {
			return []
		}

		let values = bars.map(\.close)
		let minimumValue = values.min() ?? 0
		let maximumValue = values.max() ?? 0
		let valueRange = maximumValue - minimumValue
		let startTimestamp = bars.first?.timestamp ?? 0
		let endTimestamp = bars.last?.timestamp ?? startTimestamp
		let timeRange = max(endTimestamp - startTimestamp, minimumTimelineRange)
		let drawableWidth = max(size.width - padding * 2, 0)
		let drawableHeight = max(size.height - padding * 2, 0)

		return bars.map { bar in
			let xRatio = CGFloat((bar.timestamp - startTimestamp) / timeRange)
			let xPosition = padding + drawableWidth * xRatio
			let normalizedValue: Double
			if valueRange == 0 {
				normalizedValue = flatLinePosition
			} else {
				normalizedValue = (bar.close - minimumValue) / valueRange
			}
			let yPosition = padding + drawableHeight * CGFloat(1 - normalizedValue)
			return CGPoint(x: xPosition, y: yPosition)
		}
	}
}
