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
private let priceTextFontSize = 8.5
private let minimumPriceTextFontSize = 6.5
private let priceTextHorizontalPadding = 2.0
private let priceTextAlpha = 0.96
private let priceTextShadowBlur = 1.4
private let priceTextShadowAlpha = 0.82
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

public struct SparklineRenderer {
	private let snapshotFormatter = MarketSnapshotFormatter()

	public init() {}

	public func image(
		for snapshot: MarketSnapshot?,
		error: Error?,
		width: Double,
		height: Double = ProphetDefaults.sparklineHeight,
		showsPrice: Bool = false
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
			drawSparkline(snapshot: snapshot, size: size, showsPrice: showsPrice)
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
		showsPrice: Bool
	) {
		let priceTextLayout = showsPrice ? priceTextLayout(for: snapshot, size: size) : nil
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
				snapshot: snapshot
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
			drawPriceText(priceTextLayout, snapshot: snapshot)
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

	private func priceTextLayout(
		for snapshot: MarketSnapshot,
		size: NSSize
	) -> PriceTextLayout? {
		guard let text = snapshotFormatter.statusPriceText(for: snapshot) else {
			return nil
		}

		let font = priceTextFont(for: text, size: size)
		let attributes: [NSAttributedString.Key: Any] = [.font: font]
		let textSize = NSString(string: text).size(withAttributes: attributes)
		let originX = centeredOrigin(
			contentLength: textSize.width,
			containerLength: size.width
		)
		let originY = max((size.height - textSize.height) / 2, 0)
		return PriceTextLayout(
			text: text,
			origin: NSPoint(x: originX, y: originY),
			font: font
		)
	}

	private func drawPriceText(
		_ layout: PriceTextLayout,
		snapshot: MarketSnapshot
	) {
		let color = priceTextColor(for: snapshot)
		let attributes: [NSAttributedString.Key: Any] = [
			.font: layout.font,
			.foregroundColor: color,
			.shadow: priceTextShadow(),
		]
		NSString(string: layout.text).draw(at: layout.origin, withAttributes: attributes)
	}

	private func priceTextFont(for text: String, size: NSSize) -> NSFont {
		let maximumTextWidth = max(size.width - priceTextHorizontalPadding * 2, 1)
		var fontSize = priceTextFontSize
		while fontSize > minimumPriceTextFontSize {
			let font = NSFont.monospacedDigitSystemFont(
				ofSize: fontSize,
				weight: .semibold
			)
			let textWidth = NSString(string: text).size(withAttributes: [.font: font]).width
			if textWidth <= maximumTextWidth {
				return font
			}
			fontSize -= 0.5
		}
		return NSFont.monospacedDigitSystemFont(
			ofSize: minimumPriceTextFontSize,
			weight: .semibold
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

	private func priceTextShadow() -> NSShadow {
		let shadow = NSShadow()
		shadow.shadowOffset = .zero
		shadow.shadowBlurRadius = priceTextShadowBlur
		shadow.shadowColor = NSColor.windowBackgroundColor.withAlphaComponent(priceTextShadowAlpha)
		return shadow
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
		snapshot: MarketSnapshot
	) -> NSColor {
		if session == .extended {
			return tradingViewGray.withAlphaComponent(extendedLineAlpha)
		}
		guard let isUp = snapshot.isUp else {
			return NSColor.labelColor
		}
		return isUp ? tradingViewGreen : tradingViewRed
	}

	private func priceTextColor(for snapshot: MarketSnapshot) -> NSColor {
		guard let isUp = snapshot.isUp else {
			return NSColor.labelColor.withAlphaComponent(priceTextAlpha)
		}
		let color = isUp ? tradingViewGreen : tradingViewRed
		return color.withAlphaComponent(priceTextAlpha)
	}
}

private struct PriceTextLayout {
	let text: String
	let origin: NSPoint
	let font: NSFont
}
