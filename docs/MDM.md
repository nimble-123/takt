# Takt per MDM verteilen und konfigurieren

Ziel ist die Verteilung als signiertes und notarisiertes PKG über das MDM (siehe [RELEASING.md](RELEASING.md)). **Aktueller Stand:** Es gibt noch kein signiertes PKG (#16, #53); Releases liefern unsignierte DMG/ZIP und einen Homebrew-Cask. Die Konfigurationsprofile unten funktionieren unabhängig davon. Teamweite Vorgaben kommen über ein Konfigurationsprofil mit der Preference-Domain `de.nilslutz.takt`. Takt liest die Werte über `UserDefaults`; jeder vom Profil gesetzte Wert ist in den Einstellungen gesperrt und mit einem Schloss markiert (`UserDefaults.objectIsForced`).

Beispielprofil: [`docs/mdm/Takt.mobileconfig`](mdm/Takt.mobileconfig). Ein Test hält Profil, diese Tabelle und die App synchron.

## Schlüssel

| Schlüssel | Typ | Werte | Wirkung |
| --- | --- | --- | --- |
| `adoOrganization` | String | z. B. `contoso` | Organisation für die Azure-DevOps-Anmeldung; das Feld ist vorbelegt und gesperrt |
| `startMode` | String | `switch`, `parallel` | Startverhalten: neuer Timer pausiert die laufenden oder läuft parallel (TM-05) |
| `countingMode` | String | `split`, `full` | Zählweise paralleler Zeit für Einträge ohne eigene (TM-04) |
| `idleThresholdMinutes` | Integer | 1–60, Default 10 | Ab wann Takt nach Inaktivität fragt (TM-06) |
| `lockCountsAsPause` | Boolean | Default `false` | Gesperrter Bildschirm zählt ohne Rückfrage als Pause |
| `askCorrectionReason` | Boolean | Default `false` | Bei Änderungen an Zeiten älter als 7 Tage nach einem Grund fragen (AZ-04) |
| `roundingMinutes` | Integer | 0, 5, 6, 10, 15, 30 | Rundung für Export und Buchungen; 0 = keine (TM-10) |
| `bookingMode` | String | `manual`, `review`, `automatic` | Buchung nach Azure DevOps: pro Eintrag, Tagesabschluss (Default) oder beim Stoppen (DO-21) |
| `reduceRemainingWork` | Boolean | Default `true` | Remaining Work um die gebuchte Zeit reduzieren (DO-22) |
| `bookingIncludesNote` | Boolean | Default `true` | Notiz des Eintrags in den Kommentar am Work Item (DO-23) |
| `dailyGoalHours` | Real | Default 8, 1–12 | Tagesziel im Popover; Nachkommastellen erlaubt (z. B. 7.6 bei 38 Wochenstunden) |
| `weeklyHours` | Real | Default 40, 0–60 | Wochenstunden für Soll/Ist (AN-07); Nachkommastellen erlaubt |
| `workDays` | Array of Integer | 1 = Montag … 7 = Sonntag, Default 1–5 | Arbeitstage für Soll/Ist |
| `workTimeModel` | String | `flexTime` (Default), `trust` | Gleitzeit mit Soll und Flexkonto oder Vertrauensarbeitszeit ohne beides (AZ-05) |
| `flexStartBalanceHours` | Real | Default 0, −999–999 | Stand des Flexkontos vor dem Stichtag, z. B. Übertrag aus dem Vorjahr |
| `flexStartDay` | String | `YYYY-MM-DD`; leer = erster erfasster Tag (Default) | Stichtag, ab dem das Flexkonto zählt |
| `vacationDaysPerYear` | Integer | Default 30, 0–60 | Urlaubsanspruch in Tagen pro Jahr (AZ-06) |
| `overtimeQuarterQuotaHours` | Real | Default 0 = kein Kontingent, 0–999 | Überstunden, die pro Quartal vergütet werden dürfen; Überschreiten ergibt nur einen Hinweis (AZ-07) |
| `vacationCarryoverDays` | Integer | Default 0, 0–99 | Resturlaub aus dem Vorjahr beim Start des Urlaubskontos; Folgejahre berechnet Takt |
| `federalState` | String | `BW`, `BY`, `BE`, `BB`, `HB`, `HH`, `HE`, `MV`, `NI`, `NW`, `RP`, `SL`, `SN`, `ST`, `SH`, `TH`; leer = keins (Default) | Gesetzliche Feiertage dieses Bundeslands haben kein Soll (AZ-03) |
| `showElapsedInMenuBar` | Boolean | Default `true` | Laufzeit neben dem Symbol in der Menüleiste |
| `remindWhenNoTimer` | Boolean | Default `true` | Erinnern, wenn in der Arbeitszeit kein Timer läuft (TM-09) |
| `noTimerReminderMinutes` | Integer | 5–120, Default 15 | Nach wie vielen Minuten ohne Timer erinnert wird, danach im selben Abstand |
| `workdayStartMinute` | Integer | Minuten nach Mitternacht, Default 540 (9:00) | Beginn der Arbeitszeit für die Erinnerung |
| `workdayEndMinute` | Integer | Minuten nach Mitternacht, Default 1020 (17:00) | Ende der Arbeitszeit für die Erinnerung |
| `gitFolders` | Array of String | Pfade | Ordner mit Git-Repositories für Branch-Vorschläge |
| `onboardingCompleted` | Boolean | `true` überspringt das Onboarding | Sinnvoll, wenn alles andere per Profil kommt |
| `entraClientID` | String | Client-ID der App-Registrierung | Reserviert für die Entra-ID-Anmeldung (#13), noch nicht gelesen |
| `entraTenantID` | String | Tenant-ID | Reserviert für die Entra-ID-Anmeldung (#13), noch nicht gelesen |

Nicht per Profil: Tokens und PAT. Sie liegen ausschließlich im Schlüsselbund des Nutzers.

## Profil anpassen

1. `docs/mdm/Takt.mobileconfig` kopieren, nicht benötigte Schlüssel **entfernen** – alles, was im Profil steht, ist für den Nutzer gesperrt.
2. Beide `PayloadUUID` mit `uuidgen` neu vergeben.
3. Prüfen: `plutil -lint Takt.mobileconfig`.

## Microsoft Intune

1. **Geräte → macOS → Konfiguration → Erstellen → Neue Richtlinie**, Profiltyp **Vorlagen → Benutzerdefiniert**.
2. Bereitstellungskanal **Benutzerkanal** (das Profil ist `PayloadScope` `User`), die angepasste `.mobileconfig` hochladen.
3. Zuweisen an die Gruppe des Teams.

Alternativ ohne eigene Datei: Profiltyp **Einstellungskatalog → Präferenzdatei (Preference file)** mit der Domain `de.nilslutz.takt` und einer Plist, die nur das innere Dictionary (ohne `Payload…`-Schlüssel) enthält.

Das PKG selbst kommt als **macOS-App (PKG)** unter **Apps → macOS → Hinzufügen**.

## Jamf Pro

1. **Computer → Konfigurationsprofile → Neu**, Payload **Application & Custom Settings → Upload**.
2. Preference Domain `de.nilslutz.takt`, als Property List das innere Dictionary aus dem Beispielprofil.
3. Scope auf die Gruppe des Teams.

Alternativ die ganze `.mobileconfig` über **Upload** importieren. Das PKG kommt über **Pakete** und eine Richtlinie.

## Prüfen auf einem Mac

```bash
# Ist das Profil installiert?
sudo profiles show -type configuration | grep -A3 de.nilslutz.takt
# Welche Werte sieht Takt?
defaults read de.nilslutz.takt
```

In Takt erscheinen vorgegebene Einstellungen ausgegraut mit Schloss und dem Hinweis „Von deiner Organisation vorgegeben“ – in den Einstellungen wie im Onboarding. Ein vorgegebener Wert lässt sich auch für die laufende Sitzung nicht ändern.

Takt liest die Werte beim Start. Wird ein Profil installiert oder geändert, während Takt läuft, erscheinen die Felder sofort gesperrt; die neuen Werte gelten aber erst nach einem Neustart von Takt.
