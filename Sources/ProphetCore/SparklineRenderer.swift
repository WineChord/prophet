import AppKit
import CoreGraphics
import Foundation

private let sparklinePadding = 2.0
private let sparklineLineWidth = 1.35
private let regularFillAlpha = 0.11
private let extendedLineAlpha = 0.75
private let breakMarkerAlpha = 0.82
private let breakMarkerHeight = 5.5
private let breakMarkerLean = 2.0
private let breakMarkerLineWidth = 0.95
private let minimumPriceTextFontSize = 7.0
private let priceTextHorizontalPadding = 2.0
private let priceBadgeHorizontalPadding = 3.0
private let priceBadgeVerticalPadding = 1.0
private let minimumPriceBadgeHeight = 12.0
private let priceBadgeCornerRadius = 3.0
private let priceBadgeAlpha = 0.94
private let priceBadgeBorderAlpha = 0.28
private let priceTextAlpha = 0.98
private let loadingLineWidth = 1.0
private let loadingLineAlpha = 0.45
private let tradingViewGreen = NSColor(
	red: 8.0 / 255.0,
	green: 153.0 / 255.0,
	blue: 129.0 / 255.0,
	alpha: 1
)
private let tradingViewRed = NSColor(
	red: 242.0 / 255.0,
	green: 54.0 / 255.0,
	blue: 69.0 / 255.0,
	alpha: 1
)
private let tradingViewGray = NSColor(
	red: 178.0 / 255.0,
	green: 181.0 / 255.0,
	blue: 185.0 / 255.0,
	alpha: 1
)

public enum MarketColorScheme: String {
	case redUp
	case greenUp

	public static let defaultScheme = MarketColorScheme.redUp
}

public struct SparklineRenderer {
	private let snapshotFormatter = MarketSnapshotFormatter()

	public init() {}

	public func image(
		for snapshot: MarketSnapshot?,
		error: Error?,
		width: Double,
		height: Double = ProphetDefaults.sparklineHeight,
		showsPrice: Bool = false,
		priceLabelFontSize: Double = ProphetDefaults.priceLabelFontSize,
		colorScheme: MarketColorScheme = .defaultScheme
	) -> NSImage {
		let size = NSSize(width: width, height: height)
		let image = NSImage(size: size)
		image.lockFocus()
		defer {
			image.unlockFocus()
		}

		NSColor.clear.setFill()
		NSRect(origin: .zero, size: size).fill()

		if let snapshot, snapshot.bars.count > 1 {
			drawSparkline(
				snapshot: snapshot,
				size: size,
				showsPrice: showsPrice,
				priceLabelFontSize: priceLabelFontSize,
				colorScheme: colorScheme
			)
			image.isTemplate = false
			return image
		}

		drawLoadingLine(size: size, hasError: error != nil)
		image.isTemplate = false
		return image
	}

	private func drawSparkline(
		snapshot: MarketSnapshot,
		size: NSSize,
		showsPrice: Bool,
		priceLabelFontSize: Double,
		colorScheme: MarketColorScheme
	) {
		let priceTextLayout: PriceTextLayout?
		if showsPrice {
			priceTextLayout = makePriceTextLayout(
				for: snapshot,
				size: size,
				priceLabelFontSize: priceLabelFontSize
			)
		} else {
			priceTextLayout = nil
		}
		let timeline = MarketTimeline(timeZoneIdentifier: snapshot.timeZoneIdentifier)
		let layout = TimelineGeometry.layout(
			for: snapshot.bars,
			in: CGSize(width: size.width, height: size.height),
			padding: sparklinePadding,
			timeline: timeline
		)
		let points = layout.points
		guard points.count > 1 else {
			return
		}

		for index in 1..<points.count {
			let leftBar = snapshot.bars[index - 1]
			let rightBar = snapshot.bars[index]
			guard timeline.canConnect(leftBar, rightBar) else {
				continue
			}

			let color = lineColor(
				for: timeline.session(for: rightBar.timestamp),
				snapshot: snapshot,
				colorScheme: colorScheme
			)
			if timeline.session(for: rightBar.timestamp) == .regular {
				drawFill(
					from: points[index - 1],
					to: points[index],
					bottom: sparklinePadding,
					color: color
				)
			}
			drawLine(from: points[index - 1], to: points[index], color: color)
		}

		for timelineBreak in layout.breaks {
			drawBreakMarker(timelineBreak, size: size)
		}
		if let priceTextLayout {
			drawPriceText(
				priceTextLayout,
				snapshot: snapshot,
				colorScheme: colorScheme
			)
		}
	}

	private func drawLine(from startPoint: CGPoint, to endPoint: CGPoint, color: NSColor) {
		let path = NSBezierPath()
		path.move(to: startPoint)
		path.line(to: endPoint)
		path.lineWidth = sparklineLineWidth
		path.lineJoinStyle = .round
		path.lineCapStyle = .round
		color.setStroke()
		path.stroke()
	}

	private func drawFill(
		from startPoint: CGPoint,
		to endPoint: CGPoint,
		bottom: CGFloat,
		color: NSColor
	) {
		let path = NSBezierPath()
		path.move(to: NSPoint(x: startPoint.x, y: bottom))
		path.line(to: startPoint)
		path.line(to: endPoint)
		path.line(to: NSPoint(x: endPoint.x, y: bottom))
		path.close()
		color.withAlphaComponent(regularFillAlpha).setFill()
		path.fill()
	}

	private func drawBreakMarker(_ timelineBreak: TimelineBreak, size: NSSize) {
		let centerY = size.height / 2
		let color = tradingViewGray.withAlphaComponent(breakMarkerAlpha)
		drawSlash(centerX: timelineBreak.midX, centerY: centerY, color: color)
	}

	private func drawSlash(centerX: CGFloat, centerY: CGFloat, color: NSColor) {
		let path = NSBezierPath()
		path.move(
			to: NSPoint(
				x: centerX - breakMarkerLean / 2,
				y: centerY + breakMarkerHeight / 2
			)
		)
		path.line(
			to: NSPoint(
				x: centerX + breakMarkerLean / 2,
				y: centerY - breakMarkerHeight / 2
			)
		)
		path.lineWidth = breakMarkerLineWidth
		path.lineCapStyle = .round
		color.setStroke()
		path.stroke()
	}

	private func makePriceTextLayout(
		for snapshot: MarketSnapshot,
		size: NSSize,
		priceLabelFontSize: Double
	) -> PriceTextLayout? {
		guard let text = snapshotFormatter.statusPriceText(for: snapshot) else {
			return nil
		}

		let font = priceTextFont(
			for: text,
			size: size,
			priceLabelFontSize: priceLabelFontSize
		)
		let attributes: [NSAttributedString.Key: Any] = [.font: font]
		let textSize = NSString(string: text).size(withAttributes: attributes)
		let badgeSize = NSSize(
			width: min(textSize.width + priceBadgeHorizontalPadding * 2, size.width),
			height: min(
				max(textSize.height + priceBadgeVerticalPadding * 2, minimumPriceBadgeHeight),
				size.height
			)
		)
		let badgeOrigin = NSPoint(
			x: centeredOrigin(contentLength: badgeSize.width, containerLength: size.width),
			y: centeredOrigin(contentLength: badgeSize.height, containerLength: size.height)
		)
		let textOrigin = NSPoint(
			x: badgeOrigin.x + centeredOrigin(
				contentLength: textSize.width,
				containerLength: badgeSize.width
			),
			y: badgeOrigin.y + centeredOrigin(
				contentLength: textSize.height,
				containerLength: badgeSize.height
			)
		)
		return PriceTextLayout(
			text: text,
			textOrigin: textOrigin,
			badgeRect: NSRect(origin: badgeOrigin, size: badgeSize),
			font: font
		)
	}

	private func drawPriceText(
		_ layout: PriceTextLayout,
		snapshot: MarketSnapshot,
		colorScheme: MarketColorScheme
	) {
		drawPriceBadge(
			layout,
			snapshot: snapshot,
			colorScheme: colorScheme
		)
		let color = priceTextColor()
		let attributes: [NSAttributedString.Key: Any] = [
			.font: layout.font,
			.foregroundColor: color,
		]
		NSString(string: layout.text).draw(at: layout.textOrigin, withAttributes: attributes)
	}

	private func drawPriceBadge(
		_ layout: PriceTextLayout,
		snapshot: MarketSnapshot,
		colorScheme: MarketColorScheme
	) {
		let path = NSBezierPath(
			roundedRect: layout.badgeRect,
			xRadius: priceBadgeCornerRadius,
			yRadius: priceBadgeCornerRadius
		)
		priceBadgeColor(for: snapshot, colorScheme: colorScheme).setFill()
		path.fill()
		NSColor.white.withAlphaComponent(priceBadgeBorderAlpha).setStroke()
		path.lineWidth = 0.5
		path.stroke()
	}

	private func priceTextFont(
		for text: String,
		size: NSSize,
		priceLabelFontSize: Double
	) -> NSFont {
		let maximumTextWidth = max(
			size.width - (priceBadgeHorizontalPadding + priceTextHorizontalPadding) * 2,
			1
		)
		var fontSize = max(priceLabelFontSize, minimumPriceTextFontSize)
		while fontSize > minimumPriceTextFontSize {
			let font = NSFont.monospacedDigitSystemFont(
				ofSize: fontSize,
				weight: .bold
			)
			let textWidth = NSString(string: text).size(withAttributes: [.font: font]).width
			if textWidth <= maximumTextWidth {
				return font
			}
			fontSize -= 0.5
		}
		return NSFont.monospacedDigitSystemFont(
			ofSize: minimumPriceTextFontSize,
			weight: .bold
		)
	}

	private func centeredOrigin(
		contentLength: CGFloat,
		containerLength: CGFloat
	) -> CGFloat {
		min(
			max((containerLength - contentLength) / 2, 0),
			max(containerLength - contentLength, 0)
		)
	}

	private func drawLoadingLine(size: NSSize, hasError: Bool) {
		let path = NSBezierPath()
		let yPosition = size.height / 2
		path.move(to: NSPoint(x: sparklinePadding, y: yPosition))
		path.line(to: NSPoint(x: size.width - sparklinePadding, y: yPosition))
		path.lineWidth = loadingLineWidth
		path.lineCapStyle = .round

		let color = hasError ? tradingViewRed : NSColor.secondaryLabelColor
		color.withAlphaComponent(loadingLineAlpha).setStroke()
		path.stroke()
	}

	private func lineColor(
		for session: BarTradingSession,
		snapshot: MarketSnapshot,
		colorScheme: MarketColorScheme
	) -> NSColor {
		if session == .extended {
			return tradingViewGray.withAlphaComponent(extendedLineAlpha)
		}
		guard let isUp = snapshot.isUp else {
			return NSColor.labelColor
		}
		return directionColor(isUp: isUp, colorScheme: colorScheme)
	}

	private func priceBadgeColor(
		for snapshot: MarketSnapshot,
		colorScheme: MarketColorScheme
	) -> NSColor {
		guard let isUp = snapshot.isUp else {
			return tradingViewGray.withAlphaComponent(priceBadgeAlpha)
		}
		let color = directionColor(isUp: isUp, colorScheme: colorScheme)
		return color.withAlphaComponent(priceBadgeAlpha)
	}

	private func directionColor(
		isUp: Bool,
		colorScheme: MarketColorScheme
	) -> NSColor {
		switch colorScheme {
		case .redUp:
			return isUp ? tradingViewRed : tradingViewGreen
		case .greenUp:
			return isUp ? tradingViewGreen : tradingViewRed
		}
	}

	private func priceTextColor() -> NSColor {
		NSColor.white.withAlphaComponent(priceTextAlpha)
	}
}

private struct PriceTextLayout {
	let text: String
	let textOrigin: NSPoint
	let badgeRect: NSRect
	let font: NSFont
}
