import AppKit
import CoreGraphics
import Foundation

private let sparklinePadding = 2.0
private let sparklineLineWidth = 1.35
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
		let values = snapshot.bars.map(\.close)
		let points = SparklineGeometry.points(
			for: values,
			in: CGSize(width: size.width, height: size.height),
			padding: sparklinePadding
		)
		guard let firstPoint = points.first else {
			return
		}

		let path = NSBezierPath()
		path.move(to: firstPoint)
		for point in points.dropFirst() {
			path.line(to: point)
		}
		path.lineWidth = sparklineLineWidth
		path.lineJoinStyle = .round
		path.lineCapStyle = .round

		lineColor(for: snapshot).setStroke()
		path.stroke()
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

	private func lineColor(for snapshot: MarketSnapshot) -> NSColor {
		guard let isUp = snapshot.isUp else {
			return NSColor.labelColor
		}
		return isUp ? tradingViewGreen : tradingViewRed
	}
}
