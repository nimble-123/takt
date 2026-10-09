#!/usr/bin/env bash
# Builds Takt (Debug, ad-hoc signed) and starts it, optionally with a separate test data folder.
# Usage: scripts/run-local.sh [--test [DIR]] [--seed] [--clean] [--no-build] [--logs]
set -euo pipefail

usage() {
  cat <<'HELP'
Baut Takt (Debug) und startet die App aus der Menüleiste.

  --test [ORDNER]  Eigener Datenordner statt ~/Library/Application Support/Takt
                   (Default ~/takt-test). Deine echten Einträge bleiben unberührt.
  --seed           Füllt den Testordner mit zwei Wochen Beispieleinträgen und einem
                   Projekt, falls er noch leer ist. Nur zusammen mit --test.
  --clean          Leert den Testordner vor dem Start. Nur zusammen mit --test.
  --no-build       Startet den zuletzt gebauten Stand ohne neu zu bauen.
  --logs           Zeigt danach das Log der App (Strg-C beendet nur die Anzeige).
  -h, --help       Diese Hilfe.

Hinweis: Auch im Testmodus teilt Takt Einstellungen, Azure-DevOps-Verbindungen und
Schlüsselbund mit der echten App (gleiche Bundle-ID de.nilslutz.takt). Eine laufende
Takt-Instanz wird vor dem Start beendet.
HELP
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${ROOT}/build/DerivedData"
APP="${DERIVED}/Build/Products/Debug/Takt.app"
TEST_DIR=""
SEED=false
CLEAN=false
BUILD=true
LOGS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test)
      TEST_DIR="${HOME}/takt-test"
      if [[ $# -gt 1 && "$2" != --* ]]; then TEST_DIR="$2"; shift; fi
      ;;
    --seed) SEED=true ;;
    --clean) CLEAN=true ;;
    --no-build) BUILD=false ;;
    --logs) LOGS=true ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unbekannte Option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [[ -z "${TEST_DIR}" ]] && { ${SEED} || ${CLEAN}; }; then
  echo "--seed und --clean gehen nur mit --test, damit echte Daten sicher bleiben." >&2
  exit 1
fi

cd "${ROOT}"

if ${BUILD}; then
  command -v xcodegen >/dev/null || { echo "XcodeGen fehlt: brew install xcodegen" >&2; exit 1; }
  echo "==> Xcode-Projekt erzeugen"
  xcodegen generate --quiet
  echo "==> Bauen (Debug)"
  xcodebuild -project Takt.xcodeproj -scheme Takt -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED}" build -quiet
fi
[[ -d "${APP}" ]] || { echo "Keine gebaute App unter ${APP}; ohne --no-build starten." >&2; exit 1; }

quit_takt() {
  osascript -e 'tell application id "de.nilslutz.takt" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    pgrep -x Takt >/dev/null || return 0
    sleep 0.1
  done
  pkill -x Takt || true
}

launch() {
  if [[ -n "${TEST_DIR}" ]]; then
    open -n "${APP}" --env "TAKT_DATA_DIR=${TEST_DIR}" "$@"
  else
    open -n "${APP}" "$@"
  fi
}

quit_takt

if [[ -n "${TEST_DIR}" ]]; then
  if ${CLEAN}; then
    # Only a folder that holds nothing but Takt data is removed, never e.g. the home folder.
    if [[ -d "${TEST_DIR}" ]] &&
      find "${TEST_DIR}" -mindepth 1 -maxdepth 1 ! -name 'takt.sqlite*' ! -name 'Backups' ! -name '._*' |
      grep -q .; then
      echo "${TEST_DIR} enthält mehr als Takt-Daten; --clean leert nur Testordner von Takt." >&2
      exit 1
    fi
    echo "==> Testordner leeren: ${TEST_DIR}"
    rm -rf "${TEST_DIR}"
  fi
  mkdir -p "${TEST_DIR}"
fi

DB="${TEST_DIR}/takt.sqlite"
if ${SEED}; then
  # The app creates the schema and the default categories on its first launch.
  if [[ ! -f "${DB}" ]]; then
    echo "==> Datenbank anlegen"
    launch --args -onboardingCompleted YES
    for _ in $(seq 1 100); do
      count="$(sqlite3 "${DB}" "SELECT COUNT(*) FROM category" 2>/dev/null || echo 0)"
      [[ "${count}" -gt 0 ]] && break
      sleep 0.1
    done
    quit_takt
    [[ -f "${DB}" ]] || {
      echo "Takt hat nach 10 s keine Datenbank in ${TEST_DIR} angelegt; Log: scripts/run-local.sh --no-build --logs" >&2
      exit 1
    }
  fi
  if [[ "$(sqlite3 "${DB}" "SELECT COUNT(*) FROM time_entry")" -gt 0 ]]; then
    echo "==> Testordner enthält schon Einträge, nichts angelegt (--clean leert ihn)."
  else
    echo "==> Beispieldaten anlegen"
    "${ROOT}/scripts/seed-test-data.sh" "${DB}"
  fi
fi

echo "==> Starten${TEST_DIR:+ mit Testdaten aus ${TEST_DIR}}"
launch
echo "Takt läuft in der Menüleiste (Popover: ⌥⇧T, Hauptfenster: ⌘0 im Popover)."

if ${LOGS}; then
  exec log stream --style compact --info --predicate 'subsystem == "de.nilslutz.takt"'
fi
