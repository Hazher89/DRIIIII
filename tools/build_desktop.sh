#!/usr/bin/env bash
# Bygg DriftPro Ruteplan (Mac/PC) — kun ruteplanlegging, data fra DriftPro Supabase.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-macos}"
ENTRY="lib/main_dispatch.dart"

case "$TARGET" in
  macos)
    flutter build macos --release -t "$ENTRY"
    echo "→ build/macos/Build/Products/Release/DriftPro Ruteplan.app"
    ;;
  windows)
    flutter build windows --release -t "$ENTRY"
    echo "→ build/windows/x64/runner/Release/"
    ;;
  *)
    echo "Usage: $0 macos|windows"
    exit 1
    ;;
esac
