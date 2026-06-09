import CoreGraphics
import Foundation

private let regularOpenMinute = 9 * 60 + 30
private let regularCloseMinute = 16 * 60
private let weekdayMonday = 2
private let weekdayFriday = 6
private let minimumTimelineRange: TimeInterval = 60
private let maximumContinuousGap: TimeInterval = 20 * 60
private let compressedGapWidth = 7.0
private let maximumBreakWidthShare = 0.35

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
	public static func layout(
		for bars: [PriceBar],
		in size: CGSize,
		padding: CGFloat,
		timeline: MarketTimeline = MarketTimeline()
	) -> TimelineLayout {
		guard !bars.isEmpty, size.width > 0, size.height > 0 else {
			return TimelineLayout(points: [], breaks: [])
		}

		let drawableWidth = max(size.width - padding * 2, 0)
		let drawableHeight = max(size.height - padding * 2, 0)
		let breakCount = gapCount(in: bars, timeline: timeline)
		let breakWidth = compressedBreakWidth(
			drawableWidth: drawableWidth,
			breakCount: breakCount
		)
		let continuousWidth = max(drawableWidth - breakWidth * CGFloat(breakCount), 0)
		let continuousDuration = max(
			connectableDuration(in: bars, timeline: timeline),
			minimumTimelineRange
		)
		let durationScale = continuousWidth / CGFloat(continuousDuration)

		let values = bars.map(\.close)
		let minimumValue = values.min() ?? 0
		let maximumValue = values.max() ?? 0
		let valueRange = maximumValue - minimumValue
		var points = [
			point(
				for: bars[0],
				xPosition: padding,
				minimumValue: minimumValue,
				valueRange: valueRange,
				drawableHeight: drawableHeight,
				padding: padding
			),
		]
		var breaks: [TimelineBreak] = []
		var xPosition = padding

		for index in 1..<bars.count {
			let leftBar = bars[index - 1]
			let rightBar = bars[index]
			let gapDuration = max(rightBar.timestamp - leftBar.timestamp, 0)
			if timeline.canConnect(leftBar, rightBar) {
				xPosition += CGFloat(gapDuration) * durationScale
			} else {
				let startX = xPosition
				xPosition += breakWidth
				breaks.append(
					TimelineBreak(
						leftIndex: index - 1,
						rightIndex: index,
						startX: startX,
						endX: xPosition
					)
				)
			}
			points.append(
				point(
					for: rightBar,
					xPosition: xPosition,
					minimumValue: minimumValue,
					valueRange: valueRange,
					drawableHeight: drawableHeight,
					padding: padding
				)
			)
		}

		return TimelineLayout(points: points, breaks: breaks)
	}

	public static func points(
		for bars: [PriceBar],
		in size: CGSize,
		padding: CGFloat
	) -> [CGPoint] {
		layout(for: bars, in: size, padding: padding).points
	}
}

public struct TimelineLayout: Equatable {
	public let points: [CGPoint]
	public let breaks: [TimelineBreak]
}

public struct TimelineBreak: Equatable {
	public let leftIndex: Int
	public let rightIndex: Int
	public let startX: CGFloat
	public let endX: CGFloat

	public var midX: CGFloat {
		(startX + endX) / 2
	}
}

private func gapCount(
	in bars: [PriceBar],
	timeline: MarketTimeline
) -> Int {
	guard bars.count > 1 else {
		return 0
	}

	return (1..<bars.count).reduce(0) { count, index in
		timeline.canConnect(bars[index - 1], bars[index]) ? count : count + 1
	}
}

private func compressedBreakWidth(
	drawableWidth: CGFloat,
	breakCount: Int
) -> CGFloat {
	guard breakCount > 0 else {
		return 0
	}
	let maximumTotalWidth = drawableWidth * maximumBreakWidthShare
	let maximumSingleWidth = maximumTotalWidth / CGFloat(breakCount)
	return min(compressedGapWidth, maximumSingleWidth)
}

private func connectableDuration(
	in bars: [PriceBar],
	timeline: MarketTimeline
) -> TimeInterval {
	guard bars.count > 1 else {
		return minimumTimelineRange
	}

	return (1..<bars.count).reduce(0) { duration, index in
		let leftBar = bars[index - 1]
		let rightBar = bars[index]
		guard timeline.canConnect(leftBar, rightBar) else {
			return duration
		}
		return duration + max(rightBar.timestamp - leftBar.timestamp, 0)
	}
}

private func point(
	for bar: PriceBar,
	xPosition: CGFloat,
	minimumValue: Double,
	valueRange: Double,
	drawableHeight: CGFloat,
	padding: CGFloat
) -> CGPoint {
	let normalizedValue: Double
	if valueRange == 0 {
		normalizedValue = flatLinePosition
	} else {
		normalizedValue = (bar.close - minimumValue) / valueRange
	}
	let yPosition = padding + drawableHeight * CGFloat(normalizedValue)
	return CGPoint(x: xPosition, y: yPosition)
}
