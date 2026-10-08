# Takt – Hinweise für Claude Code

Takt ist ein nativer macOS-Timetracker (Menüleiste + Hauptfenster) mit Azure-DevOps-Anbindung. Swift 6, SwiftUI/AppKit, GRDB, macOS 26+. Alle Daten lokal, kein Backend.

## Wo was steht

- `docs/PRD.md` – Anforderungen mit IDs (z. B. `TM-05`, `DO-24`). Quelle der Wahrheit für das *Was*.
- `docs/TECHNICAL_CONCEPT.md` – Architektur, Schema, Timer-Engine, ADO-Buchungsablauf. Quelle der Wahrheit für das *Wie*.
- `docs/DESIGN.md` – Screens, Farb-Tokens, Typografie, Interaktionsregeln.
- Design-Canvas (https://claude.ai/artifact/FeiQaPoKc5FuezMenGZ9Kh) – Entwürfe aller Screens, Quelle der Wahrheit für das *Aussehen*.
- `docs/RELEASING.md` – Versionierung, Release-PRs, lokales Signieren.
- `site/` – Produktseite auf GitHub Pages (Vite, GSAP, Lenis, three.js); `npm ci && npm run dev` in `site/`.
- `docs/MDM.md` – verwaltbare Einstellungen, Beispielprofil `docs/mdm/Takt.mobileconfig`, Verteilung per Intune/Jamf.
- GitHub-Issues und Milestones (`Phase 1 · Erfassen`, `Phase 2 · Azure DevOps`, `Phase 3 · Ausbau`, `Phase 4 · Nachweis`) – der Backlog.

Weicht eine Umsetzung bewusst vom Konzept ab, wird das Konzept im selben PR angepasst. Features mit Auswirkung auf UI/UX werden vor oder im selben PR auf dem Design-Canvas festgehalten (neues oder geändertes Artboard), in `docs/DESIGN.md` eingetragen und der Snapshot in `site/public/design/` aktualisiert (siehe „Galerie aktualisieren“ in `docs/DESIGN.md`).

## Befehle

```bash
brew install xcodegen                                   # einmalig
xcodegen generate                                       # erzeugt Takt.xcodeproj (nicht einchecken)
swift test --package-path Packages/TaktKit              # Package-Tests
scripts/format.sh                                       # Formatieren (SwiftFormat + SwiftLint, Airbnb-Stil)
scripts/format.sh --lint                                # nur prüfen, wie in der CI
xcodebuild -project Takt.xcodeproj -scheme Takt -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
scripts/run-local.sh --test --seed                     # App bauen und mit Beispieldaten in ~/takt-test starten
```

Ohne macOS bzw. ohne Swift-Toolchain (z. B. in einer Linux-Sandbox) können die App und Apple-Frameworks nicht gebaut werden. Dann: Code sorgfältig schreiben, `TaktCore`/`TaktStore` Linux-kompatibel halten und auf die CI verlassen. Nie behaupten, etwas sei getestet, wenn es nicht lief.

## Architekturregeln (nicht verhandelbar)

- **Schichten:** App → TaktUI → Dienste (TaktADO, TaktSystem, TaktAnalytics, TaktCalendar) → TaktStore → TaktCore. Abhängigkeiten nur nach unten.
- **TaktCore** importiert nur `Foundation` und Module der Swift-Standardbibliothek (z. B. `Synchronization`) – kein AppKit, SwiftUI, GRDB. **TaktCore und TaktStore** bleiben frei von Apple-only-Frameworks, damit ihre Tests auch unter Linux laufen (eigener CI-Job). `Package.swift` deklariert Apple-only-Targets (TaktUI, TaktSystem …) deshalb nur innerhalb von `#if os(macOS)`.
- **Rohdaten statt Ableitungen:** Gespeichert werden Segmente (UTC-Millisekunden, `INTEGER`). Zählweise, Rundung und Buchungsbeträge werden zur Abfragezeit berechnet.
- **Zeit nur über `TaktClock`:** Kein `Date()` in Core/Store/Diensten außer in `SystemClock`. Tests nutzen eine manuelle Uhr.
- **Ein Befehl = eine Transaktion:** Die Timer-Engine schreibt ausschließlich über `TimerStore.update(_:)`.
- **IDs** sind UUIDs, gespeichert als `uuidString` (`TEXT`) – GRDB würde `UUID` sonst als Blob speichern.
- **Migrationen** sind append-only. Eine bestehende Migration wird nie geändert.
- **ADO-Buchungen** sind immer Differenzen mit `sync_record` und `test /rev`, nie absolute Werte. Kennung `takt:<id>` in `System.History`.
- **Geheimnisse** nur im Schlüsselbund. Titel, Notizen und Tokens in Logs mit `privacy: .private`.
- **Swift 6 strikte Concurrency.** `@unchecked Sendable` nur mit Kommentar, warum es sicher ist. Kein Force-Unwrap außerhalb von Tests.

## Konventionen

- Code, Bezeichner und Code-Kommentare auf Englisch; UI-Texte über String Catalog (Deutsch und Englisch); Doku auf Deutsch, nur `README.md` auf Englisch.
- Tests mit Swift Testing (`import Testing`), Namen in lowerCamelCase. Jede Fehlerbehebung bekommt einen Test, der vorher fehlschlägt.
- Stil nach dem Airbnb Swift Style Guide, durchgesetzt von `scripts/format.sh` (Konfiguration in `BuildTools/`). Ausnahmen nur mit `// swiftlint:disable:next <regel>` und Begründung in der Zeile davor. Passende Xcode-Einstellungen (Einrückung, Zeilenlänge) optional per [`xcode_settings.bash`](https://github.com/airbnb/swift/blob/master/resources/xcode_settings.bash).
- Commits und PR-Titel nach Conventional Commits; der PR-Titel wird geprüft und wird per Squash-Merge zur Commit-Nachricht.
  - Typen: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`
  - Scopes: `core`, `store`, `ui`, `system`, `ado`, `analytics`, `calendar`, `app`, `release`, `deps`, `site`
  - Beispiel: `feat(core): add split allocation with weights (TM-04)`
- Anforderungs-IDs aus dem PRD in PR-Beschreibung und, wo sinnvoll, im Commit-Titel nennen.
- Branches: `feat/<issue>-<kurzname>`, `fix/<issue>-<kurzname>`. Kleine PRs, ein Thema pro PR.
- Versionen und `CHANGELOG.md` pflegt release-please. Nie von Hand ändern.

## Skills für die Entwicklung

Die Skills liegen im Repo unter `.claude/skills/` und stehen damit allen Mitwirkenden und Cloud-Sessions zur Verfügung. Beim Schreiben, Ändern und Reviewen diese Skills verwenden:

| Skill | Wofür | Quelle (Stand) |
| --- | --- | --- |
| `swift` | Airbnb Swift Style Guide: Regeln, die SwiftFormat/SwiftLint nicht automatisch korrigieren | https://swift.airbnb.tech/SKILL.md (airbnb/swift 1.2.0, MIT) |
| `write-swift` | Modernes Swift: Werttypen, Swift-6-Concurrency, Generics, API-Design, Performance, Swift Testing | `emilkowalski/skills` (`bdefda3`, MIT) |
| `swift-architecture-skill` | Architektur von Features und Modulen planen und reviewen | `efremidze/swift-architecture-skill` (`dc30a63`, MIT) |
| `ui-ux-pro-max` | UI/UX-Entscheidungen und Reviews: Barrierefreiheit, Interaktion, Typografie, Farbe, Diagramme | `nextlevelbuilder/ui-ux-pro-max-skill` (`0b6619c`, MIT) |
| `canvas-design` | Statische Grafiken als PNG/PDF, z. B. für `site/` oder Release-Material | `anthropics/skills` (`95095fa`, Apache 2.0) |

Aktualisieren: mit `npx skills add <quelle> --skill <name>` global installieren, den Ordner nach `.claude/skills/<name>/` kopieren (ohne `__pycache__` und `._*`) und den Stand in dieser Tabelle anpassen. Inhalte von Skills nur nach Durchsicht übernehmen.

Vorrang: Die Architekturregeln oben, die übrigen Konventionen dieser Datei und `docs/DESIGN.md` gehen den Skills vor. Insbesondere:
- Die Schichtung (App → TaktUI → Dienste → TaktStore → TaktCore) bleibt; der Architektur-Skill dient nur zur Einordnung, nicht zur Einführung von TCA, VIPER o. Ä.
- Aussehen und Interaktion richten sich nach dem Design-Canvas und `docs/DESIGN.md` (native macOS-App, schlicht); `ui-ux-pro-max` hilft bei Prüfung und Entscheidungen, setzt aber keinen eigenen Stil durch. Seine Web-Regeln (Viewport, Breakpoints, Lazy Loading) gelten für `site/`, nicht für die App.
- Tests bleiben in lowerCamelCase benannt (Entscheidung in #97); die Raw-Identifier-Regel des Airbnb-Skills gilt hier nicht.

## Vor jedem PR

1. `swift test --package-path Packages/TaktKit`
2. `scripts/format.sh` (danach `scripts/format.sh --lint` ohne Befund)
3. App-Build mit `xcodebuild` (siehe oben)
4. PR-Vorlage ausfüllen, betroffene Anforderungs-IDs nennen, `Closes #<issue>`.
