#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WEB_PROJECT="$REPOSITORY_ROOT/source/web"
WEB_WAR="$WEB_PROJECT/web/war"
IOS_ASSETS="$REPOSITORY_ROOT/ios/GeoGebraIOS/WebAssets"

echo "Building the GeoGebra web application (the first build can take several minutes)..."
"$REPOSITORY_ROOT/gradlew" -p "$WEB_PROJECT" \
  :web:gwtCompile :web:copyHtml \
  -Pgmodule=org.geogebra.web.SuperWeb

if [[ ! -f "$WEB_WAR/graphing-offline.html" || ! -f "$WEB_WAR/web3d/web3d.nocache.js" ]]; then
  echo "Expected GeoGebra web output was not produced in $WEB_WAR" >&2
  exit 1
fi

mkdir -p "$IOS_ASSETS"
find "$IOS_ASSETS" -mindepth 1 -maxdepth 1 \
  ! -name .keep ! -name missing-assets.html \
  -exec rm -rf -- {} +
cp -R "$WEB_WAR"/. "$IOS_ASSETS"/
touch "$IOS_ASSETS/.keep"

cat > "$IOS_ASSETS/platform.js" <<'EOF'
// Native iOS shell settings. The WKWebView injects GeoGebraJSNativeBridge.
module = "web3d";
defaultParams = Object.assign(defaultParams || {}, {
  app: true,
  enableFileFeatures: true,
  showMenuBar: true,
  showToolBar: true,
  allowStyleBar: true
});
EOF

echo "Prepared iOS web assets in $IOS_ASSETS"
