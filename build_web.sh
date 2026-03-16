#!/bin/bash
set -e
echo "Klargjør Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:`pwd`/flutter/bin"
flutter config --enable-web
flutter precache --web
flutter pub get
flutter build web --release --web-renderer canvaskit
echo "Bygg ferdig!"
