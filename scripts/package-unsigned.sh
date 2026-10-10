#!/usr/bin/env bash
# Builds an unsigned (ad-hoc signed) Apple Silicon release of Takt and packages it as DMG and ZIP.
# Used by the Release-Build workflow for release PRs and GitHub releases; also runs locally.
# Usage: scripts/package-unsigned.sh 0.1.0
set -euo pipefail

VERSION="${1:?Usage: scripts/package-unsigned.sh <version>, e.g. 0.1.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ROOT}/build/unsigned"
DIST="${BUILD}/dist"
APP="${BUILD}/DerivedData/Build/Products/Release/Takt.app"
NAME="Takt-${VERSION}-arm64"
cd "${ROOT}"

for tool in xcodegen xcodebuild hdiutil ditto dmgbuild; do
  command -v "${tool}" >/dev/null || { echo "Missing tool: ${tool} (dmgbuild: pipx install dmgbuild)" >&2; exit 1; }
done

BUILD_NUMBER="$(git rev-list --count HEAD)"

rm -rf "${BUILD}"
mkdir -p "${DIST}"

echo "==> Generating Xcode project"
xcodegen generate --quiet

# Ad-hoc signature without hardened runtime: the runtime only matters for notarization,
# and library validation would reject an ad-hoc signed app without a team ID.
echo "==> Building ${VERSION} (${BUILD_NUMBER}) for arm64"
xcodebuild \
  -project Takt.xcodeproj \
  -scheme Takt \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${BUILD}/DerivedData" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  build -quiet

codesign --verify --deep --strict --verbose=2 "${APP}"
lipo -archs "${APP}/Contents/MacOS/Takt" | grep -qx arm64 || { echo "Expected an arm64-only binary." >&2; exit 1; }
lipo -archs "${APP}/Contents/Helpers/takt" | grep -qx arm64 || { echo "Expected the arm64-only command line tool." >&2; exit 1; }

echo "==> Packaging"
ditto -c -k --keepParent "${APP}" "${DIST}/${NAME}.zip"

# Styled window: background, icon layout and volume icon come from scripts/dmg/settings.py.
dmgbuild \
  -s "${ROOT}/scripts/dmg/settings.py" \
  -D app="${APP}" \
  -D background="${ROOT}/scripts/dmg/background.png" \
  -D icon="${APP}/Contents/Resources/AppIcon.icns" \
  Takt "${DIST}/${NAME}.dmg"
hdiutil verify -quiet "${DIST}/${NAME}.dmg"

(cd "${DIST}" && shasum -a 256 "${NAME}.dmg" "${NAME}.zip" > "${NAME}.sha256")

echo "Done:"
ls -1 "${DIST}"
