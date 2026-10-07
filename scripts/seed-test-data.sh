#!/usr/bin/env bash
# Fills a Takt test database with two weeks of sample entries. Used by run-local.sh --seed.
# Usage: scripts/seed-test-data.sh <path/to/takt.sqlite>
# Writes plain rows; the database triggers keep the search index current.
set -euo pipefail

DB="${1:?Pfad zur Test-Datenbank angeben}"
case "${DB}" in
  *"Library/Application Support/Takt"*) echo "Das ist die echte Datenbank, abgebrochen." >&2; exit 1 ;;
esac

uuid() { uuidgen; }
category() { sqlite3 "${DB}" "SELECT id FROM category WHERE name = '$1' OR rowid = $2 ORDER BY name = '$1' DESC LIMIT 1"; }

DEV="$(category Entwicklung 1)"
MEETING="$(category Meeting 2)"
REVIEW="$(category Review 3)"
SUPPORT="$(category Support 4)"
PROJECT="$(uuid)"
NOW_MS=$(($(date +%s) * 1000))

SQL="INSERT INTO project (id, name, color, icon, source, created_at)
     VALUES ('${PROJECT}', 'Kundenportal', '#0F766E', 'globe', 'local', ${NOW_MS});"

# title|category|minutes|note
ACTIVITIES=(
  "Login-Refactoring|${DEV}|90|Token-Refresh im Interceptor"
  "Daily Standup|${MEETING}|15|"
  "Code-Review Pull Request|${REVIEW}|45|"
  "Support-Ticket Rechnungsexport|${SUPPORT}|30|Kunde meldet doppelte Positionen"
  "API-Dokumentation|${DEV}|60|"
  "Sprint-Planung|${MEETING}|60|"
)

entry() { # start_ms end_ms title category note state
  local id segment note_sql
  id="$(uuid)"
  segment="$(uuid)"
  note_sql="NULL"
  [[ -n "$5" ]] && note_sql="'$5'"
  local end_sql="$2" state="${6:-stopped}"
  [[ "${state}" == "running" ]] && end_sql="NULL"
  SQL+="INSERT INTO time_entry (id, title, project_id, category_id, note, state, created_at, updated_at)
        VALUES ('${id}', '$3', '${PROJECT}', '$4', ${note_sql}, '${state}', $1, $1);
        INSERT INTO segment (id, entry_id, start_at, end_at, source) VALUES ('${segment}', '${id}', $1, ${end_sql}, 'live');"
}

# Two weeks back, working days only, starting at 08:30 local time.
for days_ago in $(seq 14 -1 1); do
  day="$(date -v-"${days_ago}"d +%Y-%m-%d)"
  weekday="$(date -j -f %Y-%m-%d "${day}" +%u)"
  [[ "${weekday}" -gt 5 ]] && continue
  start=$(($(date -j -f "%Y-%m-%d %H:%M" "${day} 08:30" +%s) * 1000))
  for index in 0 1 2 3 4; do
    IFS='|' read -r title cat minutes note <<<"${ACTIVITIES[$(((days_ago + index) % ${#ACTIVITIES[@]}))]}"
    end=$((start + minutes * 60000))
    entry "${start}" "${end}" "${title}" "${cat}" "${note}"
    # A short pause or switch between activities.
    start=$((end + (index % 2) * 15 * 60000))
  done
done

# Today: one finished entry and one that is still running.
today_start=$(($(date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) 08:30" +%s) * 1000))
if [[ "${today_start}" -lt $((NOW_MS - 60 * 60000)) ]]; then
  entry "${today_start}" $((today_start + 45 * 60000)) "Daily Standup und Planung" "${MEETING}" ""
fi
entry $((NOW_MS - 25 * 60000)) 0 "Login-Refactoring" "${DEV}" "" running

sqlite3 "${DB}" "BEGIN; ${SQL} COMMIT;"
echo "$(sqlite3 "${DB}" "SELECT COUNT(*) FROM time_entry") Einträge angelegt."
