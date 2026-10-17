#!/usr/bin/env bash
# open-url.sh <url>: the "browser" for an attempt. BROWSER_DRIVER=playwright: a real headless Chromium (Playwright,
# browser-playwright.js, screenshots); otherwise the scripted stand-in (browser-driver.py).
T=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$T/.." && pwd)
CLIENTS=${CLIENTS_DIR:-$ROOT/lab/.runtime/real-clients/clients}
if [ "${BROWSER_DRIVER:-}" = playwright ]; then
  NODE_PATH=$CLIENTS/pw/node_modules PLAYWRIGHT_BROWSERS_PATH=$CLIENTS/pw/browsers \
  PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=${PLAYWRIGHT_HOST_PLATFORM_OVERRIDE:-ubuntu24.04-x64} node "$T/browser-playwright.js" "$1"
else
  python3 "$T/browser-driver.py" "$1"
fi
