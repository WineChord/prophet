import AppKit
import Darwin
import Dispatch
import Foundation
import ProphetCore
import ServiceManagement

private let smokeFetchArgument = "--smoke-fetch"
private let measureQuoteIntervalsArgument = "--measure-quote-intervals"
private let menuPricePlaceholder = "Loading..."
private let refreshTitle = "Refresh"
private let openTradingViewTitle = "Open in TradingView"
private let alwaysShowPriceTitle = "Always Show Price"
private let showPercentOnHoverTitle = "Show Percent on Hover"
private let launchAtLoginTitle = "Launch at Login"
private let priceLabelSizeTitle = "Price Label Size"
private let colorSchemeTitle = "Color Scheme"
private let quitTitle = "Quit Prophet"
private let emptyKeyEquivalent = ""
private let quitKeyEquivalent = "q"
private let tooltipUnavailablePrice = "Price unavailable"
private let tradingViewChartURLPrefix = "https://www.tradingview.com/chart/?symbol="
private let alwaysShowPriceUserDefaultsKey = "alwaysShowPrice"
private let showPercentOnHoverUserDefaultsKey = "showPercentOnHover"
private let launchAtLoginUserDefaultsKey = "launchAtLogin"
private let priceLabelSizeUserDefaultsKey = "priceLabelSize"
private let colorSchemeUserDefaultsKey = "colorScheme"
private let hoverPollInterval: TimeInterval = 0.08
private let quoteStreamReconnectDelayNanoseconds: UInt64 = 2_000_000_000
private let quoteIntervalMeasureDurationNanoseconds: UInt64 = 20_000_000_000
private let quoteIntervalMeasureMaxUpdates = 25
private let initialIntervalText = "initial"
private let unavailableIntervalText = "-"

private var retainedDelegate: ProphetAppDelegate?

private enum PriceLabelSize: String, CaseIterable {
	case compact
	case regular
	case large

	static let defaultSize = PriceLabelSize.regular

	var title: String {
		switch self {
		case .compact:
			return "Compact"
		case .regular:
			return "Regular"
		case .large:
			return "Large"
		}
	}

	var fontSize: Double {
		switch self {
		case .compact:
			return 9.0
		case .regular:
			return ProphetDefaults.priceLabelFontSize
		case .large:
			return 12.0
		}
	}
}

private enum ColorSchemeOption: String, CaseIterable {
	case redUp
	case greenUp

	static let defaultOption = ColorSchemeOption.redUp

	var title: String {
		switch self {
		case .redUp:
			return "Red Up"
		case .greenUp:
			return "Green Up"
		}
	}

	var rendererScheme: MarketColorScheme {
		switch self {
		case .redUp:
			return .redUp
		case .greenUp:
			return .greenUp
		}
	}
}

@main
enum ProphetMain {
	static func main() {
		if CommandLine.arguments.contains(smokeFetchArgument) {
			SmokeFetchCommand.run()
		}
		if CommandLine.arguments.contains(measureQuoteIntervalsArgument) {
			QuoteIntervalMeasureCommand.run()
		}

		let application = NSApplication.shared
		let delegate = ProphetAppDelegate()
		retainedDelegate = delegate
		application.delegate = delegate
		application.setActivationPolicy(.accessory)
		application.run()
	}
}

private enum QuoteIntervalMeasureCommand {
	static func run() {
		_ = Task<Void, Never> {
			do {
				try await measure()
				Darwin.exit(EXIT_SUCCESS)
			} catch {
				fputs("\(error.localizedDescription)\n", stderr)
				Darwin.exit(EXIT_FAILURE)
			}
		}
		dispatchMain()
	}

	private static func measure() async throws {
		let configuration = AppConfiguration.load()
		let recorder = QuoteIntervalRecorder()
		let measureTask = Task<Void, Error> {
			for try await quote in TradingViewClient().quoteStream(
				for: configuration.requestedSymbol
			) {
				let shouldStop = await recorder.record(quote)
				if shouldStop {
					break
				}
			}
		}
		let timeoutTask = Task<Void, Never> {
			try? await Task.sleep(nanoseconds: quoteIntervalMeasureDurationNanoseconds)
			measureTask.cancel()
		}

		do {
			try await measureTask.value
		} catch is CancellationError {
		}
		timeoutTask.cancel()
		print(await recorder.summary())
	}
}

private actor QuoteIntervalRecorder {
	private var previousAt: Date?
	private var previousPrice: Double?
	private var updateCount = 0
	private var priceChangeCount = 0
	private var intervals: [TimeInterval] = []

	func record(_ quote: TradingViewQuote) -> Bool {
		let now = Date()
		updateCount += 1

		let interval: TimeInterval?
		if let previousAt {
			interval = now.timeIntervalSince(previousAt)
			if let interval {
				intervals.append(interval)
			}
		} else {
			interval = nil
		}
		previousAt = now

		let price = quote.effectiveLastPrice
		if let price, price != previousPrice {
			priceChangeCount += 1
			previousPrice = price
		}

		print(
			[
				"quote",
				String(updateCount),
				"interval=\(interval.map(formatSeconds) ?? initialIntervalText)",
				"price=\(price.map(formatPrice) ?? unavailableIntervalText)",
				"session=\(quote.session.displayName)",
			].joined(separator: " ")
		)
		fflush(stdout)
		return updateCount >= quoteIntervalMeasureMaxUpdates
	}

	func summary() -> String {
		guard !intervals.isEmpty else {
			return "summary updates=\(updateCount) priceChanges=\(priceChangeCount) intervals=none"
		}

		let sortedIntervals = intervals.sorted()
		let average = intervals.reduce(0, +) / Double(intervals.count)
		return [
			"summary",
			"updates=\(updateCount)",
			"priceChanges=\(priceChangeCount)",
			"avg=\(formatSeconds(average))",
			"min=\(formatSeconds(sortedIntervals.first ?? 0))",
			"median=\(formatSeconds(sortedIntervals[sortedIntervals.count / 2]))",
			"max=\(formatSeconds(sortedIntervals.last ?? 0))",
		].joined(separator: " ")
	}

	private func formatSeconds(_ value: TimeInterval) -> String {
		String(format: "%.3fs", value)
	}

	private func formatPrice(_ value: Double) -> String {
		String(format: "%.2f", value)
	}
}

private enum SmokeFetchCommand {
	static func run() {
		_ = Task<Void, Never> {
			do {
				let configuration = AppConfiguration.load()
				let snapshot = try await TradingViewClient().fetchSnapshot(
					for: configuration.requestedSymbol,
					barCount: configuration.barCount
				)
				let price = snapshot.effectiveLastPrice.map { String($0) } ?? tooltipUnavailablePrice
				print("\(snapshot.instrument.symbol) \(snapshot.bars.count) bars \(price)")
				Darwin.exit(EXIT_SUCCESS)
			} catch {
				fputs("\(error.localizedDescription)\n", stderr)
				Darwin.exit(EXIT_FAILURE)
			}
		}
		dispatchMain()
	}
}

@MainActor
private final class ProphetAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private let configuration = AppConfiguration.load()
	private let client = TradingViewClient()
	private let renderer = SparklineRenderer()
	private let snapshotFormatter = MarketSnapshotFormatter()
	private let statusItem: NSStatusItem
	private let priceItem = NSMenuItem(
		title: menuPricePlaceholder,
		action: nil,
		keyEquivalent: emptyKeyEquivalent
	)
	private let baselineItem = NSMenuItem(
		title: emptyKeyEquivalent,
		action: nil,
		keyEquivalent: emptyKeyEquivalent
	)
	private let sessionItem = NSMenuItem(
		title: emptyKeyEquivalent,
		action: nil,
		keyEquivalent: emptyKeyEquivalent
	)
	private let alwaysShowPriceItem = NSMenuItem(
		title: alwaysShowPriceTitle,
		action: #selector(toggleAlwaysShowPrice),
		keyEquivalent: emptyKeyEquivalent
	)
	private let showPercentOnHoverItem = NSMenuItem(
		title: showPercentOnHoverTitle,
		action: #selector(toggleShowPercentOnHover),
		keyEquivalent: emptyKeyEquivalent
	)
	private let launchAtLoginItem = NSMenuItem(
		title: launchAtLoginTitle,
		action: #selector(toggleLaunchAtLogin),
		keyEquivalent: emptyKeyEquivalent
	)
	private let priceLabelSizeItem = NSMenuItem(
		title: priceLabelSizeTitle,
		action: nil,
		keyEquivalent: emptyKeyEquivalent
	)
	private let colorSchemeItem = NSMenuItem(
		title: colorSchemeTitle,
		action: nil,
		keyEquivalent: emptyKeyEquivalent
	)
	private let priceLabelSizeMenu = NSMenu()
	private let colorSchemeMenu = NSMenu()
	private var priceLabelSizeItems: [NSMenuItem] = []
	private var colorSchemeItems: [NSMenuItem] = []
	private var timer: Timer?
	private var hoverPollTimer: Timer?
	private var refreshTask: Task<Void, Never>?
	private var quoteStreamTask: Task<Void, Never>?
	private var latestSnapshot: MarketSnapshot?
	private var latestQuote: TradingViewQuote?
	private var latestError: Error?
	private var isHoveringStatusItem = false
	private var alwaysShowPrice = UserDefaults.standard.bool(
		forKey: alwaysShowPriceUserDefaultsKey
	)
	private var showPercentOnHover = UserDefaults.standard.bool(
		forKey: showPercentOnHoverUserDefaultsKey
	)
	private var launchAtLogin = defaultEnabledPreference(
		forKey: launchAtLoginUserDefaultsKey
	)
	private var priceLabelSize = PriceLabelSize(
		rawValue: UserDefaults.standard.string(
			forKey: priceLabelSizeUserDefaultsKey
		) ?? emptyKeyEquivalent
	) ?? PriceLabelSize.defaultSize
	private var colorScheme = ColorSchemeOption(
		rawValue: UserDefaults.standard.string(
			forKey: colorSchemeUserDefaultsKey
		) ?? emptyKeyEquivalent
	) ?? ColorSchemeOption.defaultOption

	override init() {
		statusItem = NSStatusBar.system.statusItem(
			withLength: ProphetDefaults.statusItemWidth
		)
		super.init()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		configureStatusItem()
		syncLaunchAtLoginPreference()
		startHoverPolling()
		startQuoteStream()
		refresh()
		timer = Timer.scheduledTimer(
			withTimeInterval: configuration.updateInterval,
			repeats: true
		) { [weak self] _ in
			Task { @MainActor in
				self?.refresh()
			}
		}
	}

	func applicationWillTerminate(_ notification: Notification) {
		timer?.invalidate()
		hoverPollTimer?.invalidate()
		quoteStreamTask?.cancel()
		refreshTask?.cancel()
	}

	func menuWillOpen(_ menu: NSMenu) {
		updateMenu()
	}

	@objc private func refreshFromMenu() {
		refresh()
	}

	@objc private func openTradingView() {
		let symbol = latestSnapshot?.instrument.symbol ?? configuration.requestedSymbol
		guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
		      let url = URL(string: tradingViewChartURLPrefix + encodedSymbol) else {
			return
		}
		NSWorkspace.shared.open(url)
	}

	@objc private func toggleAlwaysShowPrice() {
		alwaysShowPrice.toggle()
		UserDefaults.standard.set(
			alwaysShowPrice,
			forKey: alwaysShowPriceUserDefaultsKey
		)
		renderStatusItem()
		updateMenu()
	}

	@objc private func toggleShowPercentOnHover() {
		showPercentOnHover.toggle()
		UserDefaults.standard.set(
			showPercentOnHover,
			forKey: showPercentOnHoverUserDefaultsKey
		)
		renderStatusItem()
		updateMenu()
	}

	@objc private func toggleLaunchAtLogin() {
		launchAtLogin = SMAppService.mainApp.status != .enabled
		UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginUserDefaultsKey)
		syncLaunchAtLoginPreference()
		updateMenu()
	}

	@objc private func selectPriceLabelSize(_ sender: NSMenuItem) {
		guard let rawValue = sender.representedObject as? String,
		      let size = PriceLabelSize(rawValue: rawValue) else {
			return
		}

		priceLabelSize = size
		UserDefaults.standard.set(size.rawValue, forKey: priceLabelSizeUserDefaultsKey)
		renderStatusItem()
		updateMenu()
	}

	@objc private func selectColorScheme(_ sender: NSMenuItem) {
		guard let rawValue = sender.representedObject as? String,
		      let scheme = ColorSchemeOption(rawValue: rawValue) else {
			return
		}

		colorScheme = scheme
		UserDefaults.standard.set(scheme.rawValue, forKey: colorSchemeUserDefaultsKey)
		renderStatusItem()
		updateMenu()
	}

	@objc private func quit() {
		NSApplication.shared.terminate(nil)
	}

	private func configureStatusItem() {
		statusItem.length = configuration.statusItemWidth
		statusItem.button?.imagePosition = .imageOnly
		statusItem.button?.toolTip = "\(configuration.appName): \(menuPricePlaceholder)"
		renderStatusItem()

		let menu = NSMenu()
		menu.delegate = self
		priceItem.isEnabled = false
		baselineItem.isEnabled = false
		sessionItem.isEnabled = false
		menu.addItem(priceItem)
		menu.addItem(baselineItem)
		menu.addItem(sessionItem)
		menu.addItem(.separator())
		menu.addItem(
			NSMenuItem(
				title: refreshTitle,
				action: #selector(refreshFromMenu),
				keyEquivalent: emptyKeyEquivalent
			)
		)
		menu.addItem(
			NSMenuItem(
				title: openTradingViewTitle,
				action: #selector(openTradingView),
				keyEquivalent: emptyKeyEquivalent
			)
		)
		alwaysShowPriceItem.target = self
		menu.addItem(alwaysShowPriceItem)
		showPercentOnHoverItem.target = self
		menu.addItem(showPercentOnHoverItem)
		launchAtLoginItem.target = self
		menu.addItem(launchAtLoginItem)
		configurePriceLabelSizeMenu()
		menu.addItem(priceLabelSizeItem)
		configureColorSchemeMenu()
		menu.addItem(colorSchemeItem)
		menu.addItem(.separator())
		menu.addItem(
			NSMenuItem(
				title: quitTitle,
				action: #selector(quit),
				keyEquivalent: quitKeyEquivalent
			)
		)
		statusItem.menu = menu
	}

	private func configurePriceLabelSizeMenu() {
		priceLabelSizeItems = PriceLabelSize.allCases.map { size in
			let item = NSMenuItem(
				title: size.title,
				action: #selector(selectPriceLabelSize(_:)),
				keyEquivalent: emptyKeyEquivalent
			)
			item.target = self
			item.representedObject = size.rawValue
			priceLabelSizeMenu.addItem(item)
			return item
		}
		priceLabelSizeItem.submenu = priceLabelSizeMenu
	}

	private func configureColorSchemeMenu() {
		colorSchemeItems = ColorSchemeOption.allCases.map { scheme in
			let item = NSMenuItem(
				title: scheme.title,
				action: #selector(selectColorScheme(_:)),
				keyEquivalent: emptyKeyEquivalent
			)
			item.target = self
			item.representedObject = scheme.rawValue
			colorSchemeMenu.addItem(item)
			return item
		}
		colorSchemeItem.submenu = colorSchemeMenu
	}

	private func refresh() {
		refreshTask?.cancel()
		let requestedSymbol = configuration.requestedSymbol
		let barCount = configuration.barCount
		let client = client

		refreshTask = Task {
			do {
				let snapshot = try await client.fetchSnapshot(
					for: requestedSymbol,
					barCount: barCount
				)
				await MainActor.run {
					apply(snapshot: snapshot)
				}
			} catch {
				await MainActor.run {
					apply(error: error)
				}
			}
		}
	}

	private func apply(snapshot: MarketSnapshot) {
		let snapshot = latestQuote.map { snapshot.applying(quote: $0) } ?? snapshot
		latestSnapshot = snapshot
		latestError = nil
		renderStatusItem()
		statusItem.button?.toolTip = tooltipText(for: snapshot)
		updateMenu()
	}

	private func apply(quote: TradingViewQuote) {
		latestQuote = latestQuote?.merging(quote) ?? quote
		guard let latestQuote, let snapshot = latestSnapshot else {
			return
		}

		let updatedSnapshot = snapshot.applying(quote: latestQuote)
		latestSnapshot = updatedSnapshot
		latestError = nil
		renderStatusItem()
		statusItem.button?.toolTip = tooltipText(for: updatedSnapshot)
		updateMenu()
	}

	private func apply(error: Error) {
		latestError = error
		renderStatusItem()
		statusItem.button?.toolTip = "\(configuration.appName): \(error.localizedDescription)"
		updateMenu()
	}

	private func applyQuoteStream(error: Error) {
		guard latestSnapshot == nil else {
			return
		}
		apply(error: error)
	}

	private func updateMenu() {
		if let snapshot = latestSnapshot {
			priceItem.title = tooltipText(for: snapshot)
			baselineItem.title = snapshotFormatter.baselineText(for: snapshot)
			sessionItem.title = "\(snapshot.session.displayName) • \(snapshot.instrument.symbol)"
			updatePreferenceMenuItems()
			return
		}
		if let latestError {
			priceItem.title = latestError.localizedDescription
			baselineItem.title = snapshotFormatter.baselineText(
				for: emptySnapshot()
			)
			sessionItem.title = configuration.requestedSymbol
			updatePreferenceMenuItems()
			return
		}
		priceItem.title = menuPricePlaceholder
		baselineItem.title = snapshotFormatter.baselineText(
			for: emptySnapshot()
		)
		sessionItem.title = configuration.requestedSymbol
		updatePreferenceMenuItems()
	}

	private func updatePreferenceMenuItems() {
		alwaysShowPriceItem.state = alwaysShowPrice ? .on : .off
		showPercentOnHoverItem.state = showPercentOnHover ? .on : .off
		launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
		for item in priceLabelSizeItems {
			let rawValue = item.representedObject as? String
			item.state = rawValue == priceLabelSize.rawValue ? .on : .off
		}
		for item in colorSchemeItems {
			let rawValue = item.representedObject as? String
			item.state = rawValue == colorScheme.rawValue ? .on : .off
		}
	}

	private func syncLaunchAtLoginPreference() {
		do {
			if launchAtLogin {
				if SMAppService.mainApp.status != .enabled {
					try SMAppService.mainApp.register()
				}
			} else if SMAppService.mainApp.status == .enabled {
				try SMAppService.mainApp.unregister()
			}
		} catch {
			statusItem.button?.toolTip = "\(configuration.appName): \(error.localizedDescription)"
		}
	}

	private func tooltipText(for snapshot: MarketSnapshot) -> String {
		snapshotFormatter.tooltipText(
			for: snapshot,
			unavailablePriceText: tooltipUnavailablePrice
		)
	}

	private func startHoverPolling() {
		let timer = Timer(timeInterval: hoverPollInterval, repeats: true) { [weak self] _ in
			Task { @MainActor in
				self?.updateHoverStateFromMouseLocation()
			}
		}
		RunLoop.main.add(timer, forMode: .common)
		hoverPollTimer = timer
		updateHoverStateFromMouseLocation()
	}

	private func startQuoteStream() {
		quoteStreamTask?.cancel()
		let requestedSymbol = configuration.requestedSymbol
		let client = client
		quoteStreamTask = Task { [weak self] in
			while !Task.isCancelled {
				do {
					for try await quote in client.quoteStream(for: requestedSymbol) {
						await MainActor.run {
							self?.apply(quote: quote)
						}
					}
				} catch {
					await MainActor.run {
						self?.applyQuoteStream(error: error)
					}
				}

				if !Task.isCancelled {
					try? await Task.sleep(nanoseconds: quoteStreamReconnectDelayNanoseconds)
				}
			}
		}
	}

	private func updateHoverStateFromMouseLocation() {
		guard let button = statusItem.button,
		      let window = button.window else {
			setHoveringStatusItem(false)
			return
		}

		let buttonRectInWindow = button.convert(button.bounds, to: nil)
		let buttonRectInScreen = window.convertToScreen(buttonRectInWindow)
		setHoveringStatusItem(buttonRectInScreen.contains(NSEvent.mouseLocation))
	}

	private func setHoveringStatusItem(_ isHovering: Bool) {
		guard isHoveringStatusItem != isHovering else {
			return
		}
		isHoveringStatusItem = isHovering
		renderStatusItem()
	}

	private func renderStatusItem() {
		let width = configuration.statusItemWidth
		statusItem.length = width
		statusItem.button?.image = renderer.image(
			for: latestSnapshot,
			error: latestError,
			width: width,
			height: ProphetDefaults.sparklineHeight,
			showsPrice: shouldShowInlinePrice(),
			priceLabelFontSize: priceLabelSize.fontSize,
			colorScheme: colorScheme.rendererScheme,
			showsPercent: shouldShowInlinePercent()
		)
	}

	private func shouldShowInlinePrice() -> Bool {
		latestSnapshot != nil && (alwaysShowPrice || isHoveringStatusItem)
	}

	private func shouldShowInlinePercent() -> Bool {
		latestSnapshot != nil && showPercentOnHover && isHoveringStatusItem
	}

	private func emptySnapshot() -> MarketSnapshot {
		MarketSnapshot(
			instrument: Instrument(symbol: configuration.requestedSymbol),
			bars: []
		)
	}
}

private extension MarketSnapshot {
	func applying(quote: TradingViewQuote) -> MarketSnapshot {
		MarketSnapshot(
			instrument: instrument.applying(quote: quote),
			bars: bars,
			lastPrice: quote.effectiveLastPrice ?? lastPrice,
			change: quote.effectiveChange ?? change,
			changePercent: quote.effectiveChangePercent ?? changePercent,
			session: quote.session == .unknown ? session : quote.session,
			lastTradeTime: quote.lastTradeTime ?? lastTradeTime,
			receivedAt: Date(),
			currencyCode: quote.currencyCode ?? currencyCode,
			timeZoneIdentifier: quote.timeZoneIdentifier ?? timeZoneIdentifier
		)
	}
}

private extension Instrument {
	func applying(quote: TradingViewQuote) -> Instrument {
		Instrument(
			symbol: quote.symbol ?? symbol,
			displaySymbol: quote.displaySymbol ?? displaySymbol,
			description: quote.description ?? description,
			exchange: quote.exchange ?? exchange
		)
	}
}

private func defaultEnabledPreference(forKey key: String) -> Bool {
	if UserDefaults.standard.object(forKey: key) == nil {
		UserDefaults.standard.set(true, forKey: key)
		return true
	}
	return UserDefaults.standard.bool(forKey: key)
}
