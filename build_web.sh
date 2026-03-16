#!/bin/bash
echo "Klargjør Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1
./flutter/bin/flutter build web --release --web-renderer canvaskit
echo "Bygg ferdig!"
