#!/bin/bash
# Formats or lints the Swift sources with SwiftFormat and SwiftLint (Airbnb Swift Style Guide).
# Usage: scripts/format.sh          # autocorrect
#        scripts/format.sh --lint   # check only, non-zero exit on violations
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/BuildTools"

# A lint run must not trust results cached by an earlier autocorrect run.
if [[ " $* " == *" --lint "* ]]; then
  rm -rf .build/plugins/FormatSwift/outputs/swiftformat.cache .build/plugins/FormatSwift/outputs/swiftlint.cache
fi

swift package --allow-writing-to-package-directory --allow-writing-to-directory "$root" \
  format "$@" \
  --paths \
  "$root/App" \
  "$root/Packages/TaktKit/Sources" \
  "$root/Packages/TaktKit/Tests" \
  "$root/Packages/TaktKit/Package.swift" \
  "$root/BuildTools/Package.swift" \
  "$root/scripts"

# Project rules the Airbnb configuration does not cover, with the SwiftLint binary the plugin downloaded.
swiftlint="$(find "$root/BuildTools/.build/artifacts" -type f -name swiftlint -perm +111 | head -n 1)"
cd "$root"
"$swiftlint" lint --strict --quiet --config BuildTools/takt.swiftlint.yml App Packages/TaktKit/Sources
