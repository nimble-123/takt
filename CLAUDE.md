# Takt – Hinweise für Claude Code

Takt ist ein nativer macOS-Timetracker (Menüleiste + Hauptfenster) mit Azure-DevOps-Anbindung. Swift 6, SwiftUI/AppKit, GRDB, macOS 26+. Alle Daten lokal, kein Backend.

## Wo was steht

- `docs/PRD.md` – Anforderungen mit IDs (z. B. `TM-05`, `DO-24`). Quelle der Wahrheit für das *Was*.
- `docs/TECHNICAL_CONCEPT.md` – Architektur, Schema, Timer-Engine, ADO-Buchungsablauf. Quelle der Wahrheit für das *Wie*.
- `docs/DESIGN.md` – Screens, Farb-Tokens, Typografie, Interaktionsregeln. Entwürfe: Link in der Datei.
- `docs/RELEASING.md` – Versionierung, Release-PRs, lokales Signieren.
- `docs/MDM.md` – verwaltbare Einstellungen, Beispielprofil `docs/mdm/Takt.mobileconfig`, Verteilung per Intune/Jamf.
- GitHub-Issues und Milestones (`Phase 1 · Erfassen`, `Phase 2 · Azure DevOps`, `Phase 3 · Ausbau`) – der Backlog.

Weicht eine Umsetzung bewusst vom Konzept ab, wird das Konzept im selben PR angepasst.

## Befehle

```bash
brew install xcodegen                                   # einmalig
xcodegen generate                                       # erzeugt Takt.xcodeproj (nicht einchecken)
swift test --package-path Packages/TaktKit              # Package-Tests
swift format lint --strict --recursive App Packages     # Lint (swift-format aus der Toolchain)
xcodebuild -project Takt.xcodeproj -scheme Takt -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
scripts/run-local.sh --test --seed                     # App bauen und mit Beispieldaten in ~/takt-test starten
```

Ohne macOS bzw. ohne Swift-Toolchain (z. B. in einer Linux-Sandbox) können die App und Apple-Frameworks nicht gebaut werden. Dann: Code sorgfältig schreiben, `TaktCore`/`TaktStore` Linux-kompatibel halten und auf die CI verlassen. Nie behaupten, etwas sei getestet, wenn es nicht lief.

## Architekturregeln (nicht verhandelbar)

- **Schichten:** App → TaktUI → Dienste (TaktADO, TaktSystem, TaktAnalytics, TaktCalendar) → TaktStore → TaktCore. Abhängigkeiten nur nach unten.
- **TaktCore** importiert nur `Foundation` – kein AppKit, SwiftUI, GRDB. **TaktCore und TaktStore** bleiben frei von Apple-only-Frameworks, damit ihre Tests auch unter Linux laufen (eigener CI-Job). `Package.swift` deklariert Apple-only-Targets (TaktUI, TaktSystem …) deshalb nur innerhalb von `#if os(macOS)`.
- **Rohdaten statt Ableitungen:** Gespeichert werden Segmente (UTC-Millisekunden, `INTEGER`). Zählweise, Rundung und Buchungsbeträge werden zur Abfragezeit berechnet.
- **Zeit nur über `TaktClock`:** Kein `Date()` in Core/Store/Diensten außer in `SystemClock`. Tests nutzen eine manuelle Uhr.
- **Ein Befehl = eine Transaktion:** Die Timer-Engine schreibt ausschließlich über `TimerStore.update(_:)`.
- **IDs** sind UUIDs, gespeichert als `uuidString` (`TEXT`) – GRDB würde `UUID` sonst als Blob speichern.
- **Migrationen** sind append-only. Eine bestehende Migration wird nie geändert.
- **ADO-Buchungen** sind immer Differenzen mit `sync_record` und `test /rev`, nie absolute Werte. Kennung `takt:<id>` in `System.History`.
- **Geheimnisse** nur im Schlüsselbund. Titel, Notizen und Tokens in Logs mit `privacy: .private`.
- **Swift 6 strikte Concurrency.** `@unchecked Sendable` nur mit Kommentar, warum es sicher ist. Kein Force-Unwrap außerhalb von Tests.

## Konventionen

- Code, Bezeichner und Code-Kommentare auf Englisch; UI-Texte über String Catalog (Deutsch und Englisch); Doku auf Deutsch.
- Tests mit Swift Testing (`import Testing`). Jede Fehlerbehebung bekommt einen Test, der vorher fehlschlägt.
- Commits und PR-Titel nach Conventional Commits; der PR-Titel wird geprüft und wird per Squash-Merge zur Commit-Nachricht.
  - Typen: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`
  - Scopes: `core`, `store`, `ui`, `system`, `ado`, `analytics`, `calendar`, `app`, `release`, `deps`
  - Beispiel: `feat(core): add split allocation with weights (TM-04)`
- Anforderungs-IDs aus dem PRD in PR-Beschreibung und, wo sinnvoll, im Commit-Titel nennen.
- Branches: `feat/<issue>-<kurzname>`, `fix/<issue>-<kurzname>`. Kleine PRs, ein Thema pro PR.
- Versionen und `CHANGELOG.md` pflegt release-please. Nie von Hand ändern.

## Vor jedem PR

1. `swift test --package-path Packages/TaktKit`
2. `swift format lint --strict --recursive App Packages`
3. App-Build mit `xcodebuild` (siehe oben)
4. PR-Vorlage ausfüllen, betroffene Anforderungs-IDs nennen, `Closes #<issue>`.
