import AppKit
import Darwin
import Dispatch
import Foundation
import ProphetCore

private let smokeFetchArgument = "--smoke-fetch"
private let menuPricePlaceholder = "Loading..."
private let refreshTitle = "Refresh"
private let openTradingViewTitle = "Open in TradingView"
private let quitTitle = "Quit Prophet"
private let emptyKeyEquivalent = ""
private let quitKeyEquivalent = "q"
private let tooltipUnavailablePrice = "Price unavailable"
private let tradingViewChartURLPrefix = "https://www.tradingview.com/chart/?symbol="

private var retainedDelegate: ProphetAppDelegate?

@main
enum ProphetMain {
	static func main() {
		if CommandLine.arguments.contains(smokeFetchArgument) {
			SmokeFetchCommand.run()
		}

		let application = NSApplication.shared
		let delegate = ProphetAppDelegate()
		retainedDelegate = delegate
		application.delegate = delegate
		application.setActivationPolicy(.accessory)
		application.run()
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
	private let client: MarketDataFetching = TradingViewClient()
	private let renderer = SparklineRenderer()
	private let snapshotFormatter = MarketSnapshotFormatter()
	private let statusItem: NSStatusItem
	private let priceItem = NSMenuItem(
		title: menuPricePlaceholder,
		action: nil,
		keyEquivalent: emptyKeyEquivalent
	)
	private let sessionItem = NSMenuItem(
		title: emptyKeyEquivalent,
		action: nil,
		keyEquivalent: emptyKeyEquivalent
	)
	private var timer: Timer?
	private var refreshTask: Task<Void, Never>?
	private var latestSnapshot: MarketSnapshot?
	private var latestError: Error?

	override init() {
		statusItem = NSStatusBar.system.statusItem(withLength: AppConfiguration.load().statusItemWidth)
		super.init()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		configureStatusItem()
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

	@objc private func quit() {
		NSApplication.shared.terminate(nil)
	}

	private func configureStatusItem() {
		statusItem.length = configuration.statusItemWidth
		statusItem.button?.imagePosition = .imageOnly
		statusItem.button?.toolTip = "\(configuration.appName): \(menuPricePlaceholder)"
		statusItem.button?.image = renderer.image(
			for: nil,
			error: nil,
			width: configuration.statusItemWidth,
			height: ProphetDefaults.sparklineHeight
		)

		let menu = NSMenu()
		menu.delegate = self
		priceItem.isEnabled = false
		sessionItem.isEnabled = false
		menu.addItem(priceItem)
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
		latestSnapshot = snapshot
		latestError = nil
		statusItem.button?.image = renderer.image(
			for: snapshot,
			error: nil,
			width: configuration.statusItemWidth,
			height: ProphetDefaults.sparklineHeight
		)
		statusItem.button?.toolTip = tooltipText(for: snapshot)
		updateMenu()
	}

	private func apply(error: Error) {
		latestError = error
		statusItem.button?.image = renderer.image(
			for: latestSnapshot,
			error: error,
			width: configuration.statusItemWidth,
			height: ProphetDefaults.sparklineHeight
		)
		statusItem.button?.toolTip = "\(configuration.appName): \(error.localizedDescription)"
		updateMenu()
	}

	private func updateMenu() {
		if let snapshot = latestSnapshot {
			priceItem.title = tooltipText(for: snapshot)
			sessionItem.title = "\(snapshot.session.displayName) • \(snapshot.instrument.symbol)"
			return
		}
		if let latestError {
			priceItem.title = latestError.localizedDescription
			sessionItem.title = configuration.requestedSymbol
			return
		}
		priceItem.title = menuPricePlaceholder
		sessionItem.title = configuration.requestedSymbol
	}

	private func tooltipText(for snapshot: MarketSnapshot) -> String {
		snapshotFormatter.tooltipText(
			for: snapshot,
			unavailablePriceText: tooltipUnavailablePrice
		)
	}
}
