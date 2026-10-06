#!/usr/bin/env bash
# Builds, signs, notarizes and packages Takt locally, then attaches the PKG to the GitHub release.
# Usage: TAKT_TEAM_ID=XXXXXXXXXX scripts/release-local.sh 0.1.0
# Setup: see docs/RELEASING.md
set -euo pipefail

VERSION="${1:?Usage: scripts/release-local.sh <version>, e.g. 0.1.0}"
TEAM_ID="${TAKT_TEAM_ID:?Set TAKT_TEAM_ID to your Apple Developer team ID}"
NOTARY_PROFILE="${TAKT_NOTARY_PROFILE:-takt-notary}"
APP_IDENTITY="${TAKT_APP_IDENTITY:-Developer ID Application}"
PKG_IDENTITY="${TAKT_INSTALLER_IDENTITY:-Developer ID Installer}"
TAG="v${VERSION}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ROOT}/build/release"
cd "${ROOT}"

for tool in xcodegen xcodebuild productbuild gh; do
  command -v "${tool}" >/dev/null || { echo "Missing tool: ${tool}" >&2; exit 1; }
done

git diff --quiet && git diff --cached --quiet || { echo "Working tree is not clean." >&2; exit 1; }
if [[ "$(git describe --tags --exact-match 2>/dev/null || true)" != "${TAG}" ]]; then
  echo "HEAD is not at tag ${TAG}. Run: git fetch --tags && git checkout ${TAG}" >&2
  exit 1
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"
APP="${BUILD}/export/Takt.app"
PKG="${BUILD}/Takt-${VERSION}.pkg"

rm -rf "${BUILD}"
mkdir -p "${BUILD}"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Archiving ${VERSION} (${BUILD_NUMBER})"
xcodebuild \
  -project Takt.xcodeproj \
  -scheme Takt \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${BUILD}/Takt.xcarchive" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${APP_IDENTITY}" \
  ENABLE_HARDENED_RUNTIME=YES \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  archive

cat > "${BUILD}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>${APP_IDENTITY}</string>
</dict>
</plist>
PLIST

echo "==> Exporting signed app"
xcodebuild -exportArchive \
  -archivePath "${BUILD}/Takt.xcarchive" \
  -exportOptionsPlist "${BUILD}/ExportOptions.plist" \
  -exportPath "${BUILD}/export"

codesign --verify --deep --strict --verbose=2 "${APP}"

echo "==> Building installer package"
productbuild --component "${APP}" /Applications --sign "${PKG_IDENTITY}" "${PKG}"

echo "==> Notarizing (this can take a few minutes)"
xcrun notarytool submit "${PKG}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${PKG}"
spctl --assess --type install --verbose=2 "${PKG}"

(cd "${BUILD}" && shasum -a 256 "$(basename "${PKG}")" > "$(basename "${PKG}").sha256")

echo "==> Uploading to GitHub release ${TAG}"
gh release upload "${TAG}" "${PKG}" "${PKG}.sha256" --clobber

echo "Done: ${PKG}"
