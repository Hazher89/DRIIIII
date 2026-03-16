#!/bin/bash

# 1. Last ned Flutter hvis den ikke finnes
if [ ! -d "flutter" ]; then
  echo "Laster ned Flutter SDK..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

# 2. Legg til Flutter i PATH
export PATH="$PATH:`pwd`/flutter/bin"

# 3. Klargjør Flutter
echo "Klargjør Flutter..."
flutter config --enable-web
flutter doctor

# 4. Bygg web-versjonen
echo "Starter bygging av web..."
flutter build web --release --web-renderer canvaskit

# 5. Flytt resultatet slik at Cloudflare finner det
# (Cloudflare builder ofte i en undermappe, så vi sikrer oss)
echo "Bygg ferdig!"
