# Takt

Zeit erfassen, ohne den Takt zu verlieren: ein nativer macOS-Timetracker für die Menüleiste, mit Pausen, Multitasking, Analysen und Buchung nach Azure DevOps. Alle Daten bleiben lokal auf dem Mac.

> Status: Phasen 1–3 umgesetzt (ohne Entra ID und Outlook-Kalender). Noch kein Release.

## Dokumentation

| Dokument | Inhalt |
| --- | --- |
| [PRD](docs/PRD.md) | Ziele, Anforderungen mit IDs, Release-Plan, Entscheidungen |
| [Technisches Konzept](docs/TECHNICAL_CONCEPT.md) | Module, Datenbankschema, Timer-Engine, ADO-Buchungsablauf, Tests |
| [Design](docs/DESIGN.md) | Screens, Farben, Typografie, Interaktionsregeln |
| [Releasing](docs/RELEASING.md) | Versionierung, Release-PRs, Signieren und Notarisieren |
| [CLAUDE.md](CLAUDE.md) | Arbeitsregeln für Claude Code und alle anderen |

## Entwickeln

Voraussetzungen: macOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Takt.xcodeproj
swift test --package-path Packages/TaktKit
```

Das Xcode-Projekt wird aus `project.yml` erzeugt und nicht eingecheckt.

### Lokal starten

```bash
scripts/run-local.sh                          # bauen und mit deinen echten Daten starten
scripts/run-local.sh --test --seed            # eigener Datenordner ~/takt-test mit Beispieldaten
scripts/run-local.sh --test --seed --clean    # Testdaten neu anlegen
scripts/run-local.sh --no-build --logs        # ohne Build starten und das Log mitlesen
```

Im Testmodus bleiben die Einträge getrennt; Einstellungen, Azure-DevOps-Verbindungen und Schlüsselbund teilt Takt mit der echten App. `scripts/run-local.sh --help` zeigt alle Optionen.

## Mitarbeiten

- Arbeit läuft über Issues und die Milestones `Phase 1 · Erfassen`, `Phase 2 · Azure DevOps`, `Phase 3 · Ausbau`.
- PR-Titel folgen [Conventional Commits](https://www.conventionalcommits.org/de/v1.0.0/), gemergt wird per Squash.
- Versionen, Tags und Changelog erstellt [release-please](https://github.com/googleapis/release-please) automatisch.

## Rechte

Alle Rechte vorbehalten. © 2026 Nils Lutz.
