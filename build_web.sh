#!/bin/bash
set -e
echo "==== STARTER CLOUDFLARE BYGG ===="

# 1. Installer Flutter
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi
export PATH="$PATH:`pwd`/flutter/bin"

# 2. Konfigurer
echo "==== KONFIGURERING ===="
flutter config --no-analytics
flutter config --enable-web

# 3. Rydd og hent pakker
echo "==== PUB GET ===="
flutter pub get

# 4. Bygg (Forenklet uten --web-renderer for å unngå feil)
echo "==== BYGGER WEB-VERSJON ===="
flutter build web --release

echo "==== BYGG FERDIG! ===="
