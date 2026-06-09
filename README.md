# Prophet

Prophet is a compact macOS menu-bar sparkline for one TradingView symbol. It
renders only the curve in the status bar, keeps the latest price in the native
hover tooltip, and uses TradingView-style green/red line colors.

The app requests one-minute TradingView chart bars with the `extended` session
flag, so the curve includes every extended-hours bar TradingView returns for the
symbol: pre-market, regular market, post-market, and any overnight bars available
from the data source.

## Default Symbol

The default symbol is `NASDAQ:RKLB` for Rocket Lab. The originally requested raw
spelling `RLKB` does not currently resolve as a U.S. listing in TradingView, so
the shippable default uses the valid Rocket Lab ticker.

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
