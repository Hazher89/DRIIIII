#!/usr/bin/env bash
# Cloudflare Pages / CI: installer Flutter og bygg web.
# Retrier Dart SDK-nedlasting — Cloudflare får ofte korrupt/truncated zip (f.eks. 193 bytes).
set -euo pipefail

echo "==== STARTER CLOUDFLARE BYGG ===="

# Pin nær lokal verktygskjede (3.44.x). Overstyr med Cloudflare env FLUTTER_VERSION.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.9}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [ ! -d "flutter/.git" ]; then
  rm -rf flutter
  echo "Cloning Flutter ($FLUTTER_VERSION)..."
  if ! git clone https://github.com/flutter/flutter.git \
      --branch "$FLUTTER_VERSION" --depth 1 flutter; then
    echo "Pin $FLUTTER_VERSION feilet — faller tilbake til stable"
    rm -rf flutter
    git clone https://github.com/flutter/flutter.git --branch stable --depth 1 flutter
  fi
fi

export PATH="$ROOT/flutter/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-$ROOT/.pub-cache}"

clear_flutter_cache() {
  rm -rf \
    flutter/bin/cache/dart-sdk \
    flutter/bin/cache/dart-sdk-linux-x64.zip \
    flutter/bin/cache/*.zip \
    flutter/bin/cache/flutter_tools.stamp \
    flutter/bin/cache/flutter_tools.snapshot \
    flutter/bin/cache/engine_stamp \
    flutter/bin/cache/engine.stamp \
    flutter/bin/cache/engine-dart-sdk.stamp 2>/dev/null || true
}

setup_flutter() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    echo "==== KONFIGURERING (forsøk $attempt) ===="
    clear_flutter_cache

    # --version trigger nedlasting av Dart SDK
    if ! flutter --version; then
      echo "flutter --version feilet (ofte korrupt SDK-zip)"
      sleep $((attempt * 6))
      continue
    fi

    flutter config --no-analytics || true
    flutter config --enable-web || true

    if flutter precache --web; then
      echo "Flutter klar."
      return 0
    fi

    echo "precache feilet — prøver igjen..."
    sleep $((attempt * 6))
  done

  echo "Flutter-oppsett feilet etter flere forsøk."
  return 1
}

setup_flutter

echo "==== PUB GET ===="
flutter pub get

echo "==== BYGGER WEB-VERSJON ===="
flutter build web --release

echo "==== BYGG FERDIG! ===="
