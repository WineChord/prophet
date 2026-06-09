import CoreGraphics
import Foundation

private let flatLinePosition = 0.5

public enum SparklineGeometry {
	public static func points(
		for values: [Double],
		in size: CGSize,
		padding: CGFloat
	) -> [CGPoint] {
		guard !values.isEmpty, size.width > 0, size.height > 0 else {
			return []
		}

		let minimumValue = values.min() ?? 0
		let maximumValue = values.max() ?? 0
		let valueRange = maximumValue - minimumValue
		let drawableWidth = max(size.width - padding * 2, 0)
		let drawableHeight = max(size.height - padding * 2, 0)
		let divisor = CGFloat(max(values.count - 1, 1))

		return values.enumerated().map { index, value in
			let xPosition = padding + drawableWidth * CGFloat(index) / divisor
			let normalizedValue: Double
			if valueRange == 0 {
				normalizedValue = flatLinePosition
			} else {
				normalizedValue = (value - minimumValue) / valueRange
			}
			let yPosition = padding + drawableHeight * CGFloat(1 - normalizedValue)
			return CGPoint(x: xPosition, y: yPosition)
		}
	}
}
