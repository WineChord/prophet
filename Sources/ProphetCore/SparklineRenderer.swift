import AppKit
import CoreGraphics
import Foundation

private let sparklinePadding = 2.0
private let sparklineLineWidth = 1.35
private let regularFillAlpha = 0.11
private let extendedLineAlpha = 0.75
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
	public init() {}

	public func image(
		for snapshot: MarketSnapshot?,
		error: Error?,
		width: Double,
		height: Double = ProphetDefaults.sparklineHeight
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
			drawSparkline(snapshot: snapshot, size: size)
			image.isTemplate = false
			return image
		}

		drawLoadingLine(size: size, hasError: error != nil)
		image.isTemplate = false
		return image
	}

	private func drawSparkline(snapshot: MarketSnapshot, size: NSSize) {
		let points = TimelineGeometry.points(
			for: snapshot.bars,
			in: CGSize(width: size.width, height: size.height),
			padding: sparklinePadding
		)
		guard points.count > 1 else {
			return
		}

		let timeline = MarketTimeline(timeZoneIdentifier: snapshot.timeZoneIdentifier)
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
}
