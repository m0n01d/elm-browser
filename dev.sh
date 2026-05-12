#!/usr/bin/env bash
# dev.sh — sync modified debugger source into the elm package cache.
#
# Usage:
#   ./dev.sh                     → sync + rebuild the toy test app
#   ./dev.sh --app /path/to/app  → sync + clear that app's elm-stuff (then start it yourself)
#   ./dev.sh --test              → sync + rebuild toy test app (explicit)

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CACHE=~/.elm/0.19.1/packages/elm/browser/1.0.2/src/Debugger
TEST_APP="$REPO/test-app"
APP_DIR=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_DIR="$2"; shift 2 ;;
    --test) shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "→ Copying modified debugger files to elm package cache..."
cp "$REPO/src/Debugger/Expando.elm" "$CACHE/Expando.elm"
cp "$REPO/src/Debugger/Main.elm"    "$CACHE/Main.elm"

echo "→ Busting precompiled artifacts cache (artifacts.dat)..."
rm -f ~/.elm/0.19.1/packages/elm/browser/1.0.2/artifacts.dat

if [[ -n "$APP_DIR" ]]; then
  echo "→ Clearing elm-stuff in $APP_DIR ..."
  rm -rf "$APP_DIR/elm-stuff"
  echo ""
  echo "✓ Done. Now start your app in debug mode:"
  echo ""
  echo "  cd $APP_DIR"
  echo "  npx elm-watch hot"
  echo ""
  echo "  Then in the elm-watch browser UI, click the compilation mode button"
  echo "  and switch to 'debug' to enable the Elm debugger."
  echo ""
  echo "  Or for a one-shot debug build:"
  echo "  npx elm-watch make --debug"
else
  echo "→ Clearing elm-stuff in test app..."
  rm -rf "$TEST_APP/elm-stuff"

  echo "→ Building test app with --debug..."
  cd "$TEST_APP"
  npx elm make src/Main.elm --debug --output=index.html

  echo ""
  echo "✓ Done. Open the test app with:"
  echo "  open $TEST_APP/index.html"
fi
