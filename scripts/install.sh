#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Prophet"
INSTALL_DIR="${PROPHET_INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"

"$ROOT_DIR/scripts/package_app.sh" >/dev/null

mkdir -p "$INSTALL_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$APP_PATH"
ditto "$ROOT_DIR/dist/$APP_NAME.app" "$APP_PATH"
open "$APP_PATH"
printf '%s\n' "$APP_PATH"
