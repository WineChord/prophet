# Prophet

Prophet is a compact macOS menu-bar sparkline for one TradingView symbol. It
renders the curve in the status bar, overlays a high-contrast latest-price label
at the center on hover without changing its menu-bar width, and keeps the native
hover tooltip as a secondary detail view.

The app requests one-minute TradingView chart bars with the `extended` session
flag, so the curve includes every extended-hours bar TradingView returns for the
symbol: pre-market, regular market, post-market, and any overnight bars available
from the data source.

The visible curve follows TradingView's overview chart behavior: it starts at the
most recent regular-session open, keeps the real timestamp spacing between bars,
compresses long no-trade gaps into compact single-slash break markers, uses TradingView
green/red for the regular session, and uses a TradingView-style gray line for
extended-hours segments.

## Default Symbol

The default symbol is `NASDAQ:RKLB` for Rocket Lab.

To change the symbol, create:

```json
{
  "symbol": "NASDAQ:AAPL",
  "updateInterval": 15,
  "barCount": 1440,
  "statusItemWidth": 72
}
```

at:

```text
~/Library/Application Support/Prophet/config.json
```

Environment variables can override the same settings when launching from a
shell:

```text
PROPHET_SYMBOL=NASDAQ:TSLA
PROPHET_UPDATE_INTERVAL=15
PROPHET_BAR_COUNT=1440
PROPHET_STATUS_WIDTH=72
```

## Build

```sh
swift test
swift build --configuration release --arch arm64
```

## Package and Install

```sh
scripts/package_app.sh
scripts/install.sh
```

`scripts/install.sh` installs the app to `~/Applications/Prophet.app` by default
and launches it immediately. Set `PROPHET_INSTALL_DIR` to choose another
installation directory.

## Menu

Use `Always Show Price` to keep the latest price visible in the status bar.
When it is off, the status item keeps the same width and only overlays the price
while hovered.

Use `Price Label Size` to choose the centered label size. `Regular` is the
default, with `Compact` and `Large` available from the menu.
