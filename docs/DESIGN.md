# Takt – Design-Referenz

Die Entwürfe liegen auf einem Design-Canvas: https://claude.ai/artifact/FeiQaPoKc5FuezMenGZ9Kh
Diese Datei hält fest, was für die Umsetzung verbindlich ist: Screens, Farben, Typografie und Interaktionsregeln.

## Screens

| Bereich | Screen | Kernpunkte |
| --- | --- | --- |
| Menüleiste | Popover | Suchfeld mit Sofortfokus, laufender und pausierter Timer, „Zuletzt“ mit ⌘1–⌘4, Tagesfortschritt nach Kategorie, „Alle pausieren ⌥⇧P“ |
| Menüleiste | Suche & ADO-Vorschau | Treffer gruppiert (Azure DevOps, Lokale Tasks), Suchtreffer fett, Kompaktvorschau mit Status, Iteration, Aufwand, Fortschrittsbalken; „Starten ↩“, „Parallel ⌥↩“ |
| Menüleiste | Inaktivität erkannt | Mini-Timeline mit schraffierter Inaktivität, vier Optionen als Radiogruppe, „Als Pause werten“ vorausgewählt |
| Menüleiste | Timer beenden | Stopp beendet sofort mit Toast („Notiz“, „Rückgängig ⌘Z“); Panel mit Notiz, Kategorie, Tags, Buchungswahl nur bei Bedarf |
| Menüleiste | Suche mit Outlook-Terminen (Phase 3) | Gruppe „Kalender“ vor ADO; Zuordnung pro Serie; „Ab 09:45 starten“ |
| Menüleiste | Regeltermin Start/Ende (Phase 3) | Hinweis zum Terminbeginn mit „Timer starten“; Toast zum Ende mit „Verlängern“ |
| Hauptfenster | Heute & Tagesabschluss | KPI-Zeile, Timeline 08–17 Uhr mit paralleler Spur, Pausen und Inaktivität schraffiert, „jetzt“-Linie; rechts Tagesabschluss mit Buchungsliste |
| Hauptfenster | Analysen | Zeitraum-Segmente, Gruppieren nach, Zählweise; KPIs mit Vorwochenvergleich; gestapelte Balken je Tag, Projekte, Top Work Items, Heatmap |
| Hauptfenster | Eintrag bearbeiten | Ziehen in der Timeline mit Zeit-Tooltip; Inspektor mit Segmenten, Pause umwandeln, Gewichtsregler, Hinweis auf Differenzbuchung |
| Dark Mode | Popover, Heute | Gleiche Struktur, aufgehellte Akzente |
| Onboarding | 3 Schritte | 1. ADO per PAT verbinden + Projekte wählen, 2. Kürzel live testen, 3. Startverhalten und Zählweise mit Mini-Beispiel |

## Farben

Systemschrift und Systemmaterialien; eigene Farben nur für Status und Kategorien. Alle Farben als Asset-Katalog mit Hell- und Dunkel-Variante.

| Token | Hell | Dunkel | Verwendung |
| --- | --- | --- | --- |
| `accent` / läuft | `#0F766E` | `#2DD4BF` | Laufender Timer, Primärbuttons, Fokusring |
| `accentText` | `#0F766E` | `#5EEAD4` | Laufzeit, Links |
| `accentSurface` | `#E8F4F2` | `#12332F` | Hintergrund laufender Timer, Auswahl |
| `onAccent` | `#FFFFFF` | `#042F2E` | Text auf Primärbuttons |
| `warning` / pausiert | `#B45309` | `#FBBF24` | Pausiert, „braucht Entscheidung“, fehlendes Work Item |
| `warningSurface` | `#FEF3E2` | `#4A3510` | Hinweise, Inaktivität |
| `danger` | `#B91C1C` | `#F87171` | Löschen, Buchungsfehler |
| `textPrimary` | `#1C1C1E` | `#F5F5F7` | Text |
| `textSecondary` | `#55555A` | `#AEAEB2` | Metadaten (4.5:1 auf Grund) |
| `separator` | `#E5E5EA` | `#3A3A3C` | Linien, Kartenränder |

**Kategorien** (Standardwerte, pro Kategorie änderbar)

| Kategorie | Hell | Dunkel | Timeline-Fläche hell / dunkel |
| --- | --- | --- | --- |
| Entwicklung | `#2563EB` | `#60A5FA` | `#DBEAFE` / `#1E2B4D` |
| Meeting | `#C2410C` | `#FB923C` | `#FFEDD5` / `#41281A` |
| Review | `#7C3AED` | `#A78BFA` | `#EDE9FE` / `#2E2650` |
| Support | `#DB2777` | `#F472B6` | `#FCE7F3` / `#4A1D35` |

**Work-Item-Typen** (Badge mit Buchstabe): Task `#A16207`, Bug `#B91C1C`, User Story `#0369A1`.

## Typografie

- Systemschrift (SF Pro). Zeiten in SF Mono mit tabellarischen Ziffern (`.monospacedDigit()`).
- Größen: Laufzeit im Popover 19 pt semibold, KPI-Werte 20–24 pt, Titel 13–14 pt semibold, Metadaten 12 pt, Abschnittstitel 11 pt uppercase.

## Interaktionsregeln

- Das Suchfeld im Popover hat beim Öffnen immer den Fokus. Enter startet, ⌥↩ startet parallel.
- Undo statt Rückfrage: Stoppen, Löschen, Verschieben sind sofort und per ⌘Z rückgängig zu machen.
- Pausen und Inaktivität werden schraffiert dargestellt, nie als leere Lücke.
- Fehlende Zuordnung (kein Work Item) ist Amber, nicht Rot.
- Eine Hauptaktion pro Ansicht; Primärbutton immer `accent`.
- Touch-Ziele mindestens 28 pt in der Menüleiste, 32 pt im Hauptfenster; alle Icon-Buttons mit Accessibility-Label.
