#!/usr/bin/env bash
# Generates ios/Runner/GoogleService-Info.plist from ios/Firebase.env (local, gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="$ROOT/ios/Firebase.env"
OUT="$ROOT/ios/Runner/GoogleService-Info.plist"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f "$OUT" ]]; then
    exit 0
  fi
  echo "warning: $ENV_FILE mangler — kopier ios/Firebase.env.example og fyll inn Firebase-verdier." >&2
  exit 0
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${FIREBASE_API_KEY:?FIREBASE_API_KEY mangler i ios/Firebase.env}"
: "${FIREBASE_APP_ID:?FIREBASE_APP_ID mangler i ios/Firebase.env}"
: "${FIREBASE_MESSAGING_SENDER_ID:?FIREBASE_MESSAGING_SENDER_ID mangler i ios/Firebase.env}"
: "${FIREBASE_PROJECT_ID:?FIREBASE_PROJECT_ID mangler i ios/Firebase.env}"

STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET:-${FIREBASE_PROJECT_ID}.appspot.com}"

cat > "$OUT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>${FIREBASE_API_KEY}</string>
	<key>GCM_SENDER_ID</key>
	<string>${FIREBASE_MESSAGING_SENDER_ID}</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>no.driftpro.driftpro</string>
	<key>PROJECT_ID</key>
	<string>${FIREBASE_PROJECT_ID}</string>
	<key>STORAGE_BUCKET</key>
	<string>${STORAGE_BUCKET}</string>
	<key>IS_ADS_ENABLED</key>
	<false/>
	<key>IS_ANALYTICS_ENABLED</key>
	<false/>
	<key>IS_APPINVITE_ENABLED</key>
	<true/>
	<key>IS_GCM_ENABLED</key>
	<true/>
	<key>IS_SIGNIN_ENABLED</key>
	<true/>
	<key>GOOGLE_APP_ID</key>
	<string>${FIREBASE_APP_ID}</string>
</dict>
</plist>
EOF

echo "Generated $OUT from ios/Firebase.env"
