# Releasing

Versionen entstehen automatisch aus den Commit-Nachrichten; signiert und notarisiert wird vorerst lokal.

## Ablauf

1. Jeder PR wird per Squash gemergt. Sein Titel folgt Conventional Commits und wird damit zur Commit-Nachricht auf `main`.
2. Nach jedem Push auf `main` aktualisiert release-please einen Release-PR („chore(main): release x.y.z“). Er enthält den neuen `CHANGELOG.md`-Abschnitt und die Versionsnummer in `project.yml` (`MARKETING_VERSION`, markiert mit `# x-release-please-version`).
3. Auf dem Release-PR läuft zusätzlich der Check „Release-Build (Apple Silicon)“ (`.github/workflows/release-build.yml`). Er baut und packt die App genau so wie später für das Release; ist er grün, lässt sich der Stand ausliefern.
4. Ist der Stand releasebereit, wird der Release-PR gemergt. release-please legt dann den Tag `vX.Y.Z` und ein GitHub-Release mit den Release Notes an.
5. Das veröffentlichte Release startet den Release-Build erneut. Er hängt `Takt-X.Y.Z-arm64.dmg`, `.zip` und die SHA-256-Prüfsummen an und ergänzt die Release Notes um einen Installationshinweis. Lokal geht dasselbe mit `scripts/package-unsigned.sh X.Y.Z`; über „Run workflow“ lässt sich der Build für ein bestehendes Tag wiederholen. Danach setzt der Job „Homebrew-Tap“ `version` und `sha256` in `Casks/takt.rb` von [nimble-123/homebrew-tap](https://github.com/nimble-123/homebrew-tap) auf die neue DMG.
6. Für die Verteilung per MDM lokal das signierte PKG bauen und an das Release hängen:

   ```bash
   git fetch --tags && git checkout vX.Y.Z
   TAKT_TEAM_ID=XXXXXXXXXX scripts/release-local.sh X.Y.Z
   ```

7. Das PKG aus dem GitHub-Release ins MDM (Intune/Jamf) laden.

Der unsignierte Build ist nur ad-hoc signiert und nicht notarisiert, ohne Hardened Runtime und nur für Apple Silicon. macOS blockiert deshalb den ersten Start (Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“), und nach jedem Update fragt macOS erneut nach dem Zugriff auf den Schlüsselbund. Für Firmen-Rollouts bleibt das signierte PKG der Weg.

## Versionsregeln

| Commit-Typ | Wirkung vor 1.0 | Wirkung ab 1.0 |
| --- | --- | --- |
| `fix:` | Patch (0.1.0 → 0.1.1) | Patch |
| `feat:` | Minor (0.1.0 → 0.2.0) | Minor |
| `feat!:` / `BREAKING CHANGE:` | Minor (0.1.0 → 0.2.0) | Major |

Das erste Release mit einem `feat:` wird 0.1.0. Die 1.0 wird bewusst gesetzt, mit einem leeren Commit `chore: release 1.0.0` und der Zeile `Release-As: 1.0.0` im Commit-Text.
| `docs:`, `chore:`, `ci:`, `test:`, `refactor:` | keine neue Version | keine neue Version |

Die Build-Nummer (`CURRENT_PROJECT_VERSION`) setzt das Release-Skript auf die Anzahl der Commits bis zum Tag.

## Einmalige Einrichtung für das Signieren

1. Im privaten Apple-Developer-Account die Zertifikate „Developer ID Application“ und „Developer ID Installer“ erstellen und in den Schlüsselbund laden.
2. Ein App-spezifisches Passwort für die Apple-ID anlegen und das Notarisierungsprofil speichern:

   ```bash
   xcrun notarytool store-credentials takt-notary \
     --apple-id <apple-id> --team-id <team-id> --password <app-spezifisches-passwort>
   ```

3. `gh auth login`, damit das Skript das PKG hochladen kann.

## Später: Signieren in der CI

Soll die CI signieren, kommen Zertifikat (als `.p12`), dessen Passwort und ein App-Store-Connect-API-Key für `notarytool` als GitHub-Secrets dazu. `release-build.yml` würde dann zusätzlich signieren und notarisieren. Bis dahin hängt die CI nur den unsignierten Build an.

## Token für release-please

Von release-please mit dem Standard-`GITHUB_TOKEN` erstellte PRs und Releases starten keine anderen Workflows: Weder die Checks auf dem Release-PR noch der Release-Build würden laufen. Deshalb ist ein Fine-grained PAT (nur dieses Repo; Contents und Pull requests: Read & Write) als Secret `RELEASE_PLEASE_TOKEN` hinterlegt; der Workflow nutzt es automatisch. Läuft das Token ab, fällt release-please still auf das Standard-Token zurück. Dann fehlen die Checks auf dem Release-PR, und der Release-Build muss über „Run workflow“ nachgeholt werden.

## Token für den Homebrew-Tap

Der Job „Homebrew-Tap“ schreibt in ein anderes Repo und braucht dafür das Secret `HOMEBREW_TAP_TOKEN`: ein Fine-grained PAT nur für `nimble-123/homebrew-tap` mit Contents: Read & Write. Fehlt es, warnt der Job und bricht ab, ohne das Release scheitern zu lassen; der Cask zeigt dann weiter auf die vorige Version.

## Website

Die Produktseite liegt in `site/` und wird von `.github/workflows/site.yml` auf GitHub Pages veröffentlicht (https://nimble-123.github.io/takt/). Die angezeigte Version und der DMG-Link kommen beim Build aus `MARKETING_VERSION` in `project.yml`; weil release-please die Datei beim Release anhebt, baut die Seite danach von selbst neu. Änderungen in `site/` lösen kein App-Release aus (`exclude-paths` in `release-please-config.json`). Einmalig unter Settings → Pages die Quelle „GitHub Actions“ wählen.
