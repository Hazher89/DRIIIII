#!/bin/bash
set -e
echo "==== STARTER CLOUDFLARE BYGG ===="
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:`pwd`/flutter/bin"

echo "==== KONFIGURERER FLUTTER ===="
flutter config --no-analytics
flutter config --enable-web
flutter doctor -v

echo "==== HENTER PAKKER ===="
flutter pub get

echo "==== BYGGER WEB ===="
flutter build web --release --web-renderer canvaskit

echo "==== BYGG VELLYKKET ===="
