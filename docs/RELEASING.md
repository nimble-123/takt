# Releasing

Versionen entstehen automatisch aus den Commit-Nachrichten; signiert und notarisiert wird vorerst lokal.

## Ablauf

1. Jeder PR wird per Squash gemergt. Sein Titel folgt Conventional Commits und wird damit zur Commit-Nachricht auf `main`.
2. Nach jedem Push auf `main` aktualisiert release-please einen Release-PR („chore(main): release x.y.z“). Er enthält den neuen `CHANGELOG.md`-Abschnitt und die Versionsnummer in `project.yml` (`MARKETING_VERSION`, markiert mit `# x-release-please-version`).
3. Ist der Stand releasebereit, wird der Release-PR gemergt. release-please legt dann den Tag `vX.Y.Z` und ein GitHub-Release mit den Release Notes an.
4. Lokal das PKG bauen und an das Release hängen:

   ```bash
   git fetch --tags && git checkout vX.Y.Z
   TAKT_TEAM_ID=XXXXXXXXXX scripts/release-local.sh X.Y.Z
   ```

5. Das PKG aus dem GitHub-Release ins MDM (Intune/Jamf) laden.

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

Soll die CI signieren, kommen Zertifikat (als `.p12`), dessen Passwort und ein App-Store-Connect-API-Key für `notarytool` als GitHub-Secrets dazu. Der Release-Workflow reagiert dann auf das von release-please erstellte Release. Bis dahin baut und testet die CI nur.

## Hinweis zu Release-PRs

Von release-please mit dem Standard-`GITHUB_TOKEN` erstellte PRs starten keine anderen Workflows. Soll die CI auch auf Release-PRs laufen, ein Fine-grained PAT (Contents und Pull requests: Read & Write) als Secret `RELEASE_PLEASE_TOKEN` hinterlegen; der Workflow nutzt es automatisch.
