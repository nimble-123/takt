# Takt – Design-Referenz

Die Entwürfe liegen auf einem Design-Canvas: https://claude.ai/artifact/FeiQaPoKc5FuezMenGZ9Kh
Diese Datei hält fest, was für die Umsetzung verbindlich ist: Screens, Farben, Typografie und Interaktionsregeln.

Eine schreibgeschützte Galerie aller Artboards liegt auf GitHub Pages: https://nimble-123.github.io/takt/design/ (Quelle: `site/public/design/`).

**Pflege:** Der Canvas ist die Quelle der Wahrheit für das Aussehen, diese Datei für die verbindlichen Regeln. Features mit Auswirkung auf UI/UX werden vor oder im selben PR auf dem Canvas entworfen (neues oder geändertes Artboard) und hier in der Screen-Tabelle eingetragen. Entworfene, aber noch nicht gebaute Elemente sammelt #101.

**Galerie aktualisieren:** Nach jeder Änderung am Canvas die Dateien unter `project/` des Canvas (`canvas.json` und alle `*.dc.html`) nach `site/public/design/` übernehmen, z. B. mit Claude Code (Artifact „read“). Vorher prüfen, dass die Artboards keine externen Skripte oder Stylesheets laden. `support.js` ist ein eigener, vereinfachter Renderer (Platzhalter, `sc-for`, `sc-if`); der Editor des Canvas läuft nur auf claude.ai und wird nicht ins Repo kopiert.

## Screens

| Bereich | Screen | Kernpunkte |
| --- | --- | --- |
| Menüleiste | Popover | Suchfeld mit Sofortfokus und Hinweis `#ID`, laufender und pausierter Timer mit Unterzeile Work Item · Projekt · Kategorie, „Zuletzt“ mit Farbpunkt der Kategorie und ⌘1–⌘4, Tagesfortschritt nach Kategorie; Fußzeile „Alle pausieren ⌥⇧P“, „Alle stoppen“, „Takt öffnen“ und Zahnrad für die Einstellungen |
| Menüleiste | Suche & ADO-Vorschau | Trefferzahl im Suchfeld, Treffer gruppiert (Azure DevOps, Lokale Tasks); Azure-DevOps-Treffer nach Status (in Arbeit, Testing, Neu, Erledigt; Removed/Cancelled ausgeblendet), innerhalb eines Status die aktuelle Iteration zuerst („Sprint 42 zuerst“); Status mit farbigem Punkt wie in Azure DevOps (in Arbeit blau, Testing gelb, Neu grau, Erledigt grün), Suchtreffer fett; unter den Treffern Kompaktvorschau des markierten (sonst ersten) Work Items mit Status, Zugewiesen, Iteration, Aufwand und Fortschrittsbalken. Gestartet wird per ↩ / ⌥↩ aus der Liste, die Vorschau hat keine eigenen Buttons |
| Menüleiste | Inaktivität erkannt | Im Popover eingebettet; Titel „Du warst 23 min weg“, Text mit Uhrzeiten und Namen der betroffenen Einträge; Mini-Timeline mit schraffierter Inaktivität und Uhrzeiten (Beginn, Inaktivität ab, zurück um); vier Optionen mit Erklärtext, „Als Pause werten · empfohlen“ vorausgewählt; Checkbox „Bei Bildschirmsperre künftig als Pause werten“; „Später“ blendet den Dialog bis zum nächsten Öffnen des Popovers aus |
| Menüleiste | Timer beenden | Stopp beendet sofort mit Toast („Code-Review beendet · 0:45 h“, „Notiz“, „Rückgängig ⌘Z“). Das Beenden-Panel (Notiz, Projekt, Kategorie, Work Item nur mit ADO-Verbindung, Tags, Buchungswahl „Im Tagesabschluss“ / „Jetzt buchen“, „Beenden ⌘↩“) öffnet sich statt des Stopps, wenn eine in den Einstellungen als Pflicht markierte Angabe fehlt (dann ist „Beenden“ gesperrt, das Feld trägt „Pflicht“), oder per ⌥-Klick auf Stopp. „Alle stoppen“ öffnet bei einem unvollständigen Eintrag dessen Panel und stoppt nichts |
| Menüleiste | Suche mit Outlook-Terminen (Phase 3) | Gruppe „Kalender“ (rechts „Outlook“) vor ADO, bis zu drei Treffer; Zeile mit Kalenderblatt (Tag), Titel bzw. „Privat“, Badge „läuft seit 2 min“ / „in 5 min“ und Unterzeile „Heute 09:45–10:00 · Serie · Online-Meeting · 8 Teilnehmer“. Bei leerem Suchfeld steht der laufende oder in 15 min beginnende Termin als Abschnitt „Kalender“ über „Zuletzt“ (CA-11). Klick oder ↩ startet den Timer mit dem Titel; begann der Termin vor höchstens 10 min, ab Terminbeginn (CA-13). Darunter eine Vorschau-Karte des markierten oder ersten Termins: Titel, „Heute 09:45–10:00 (15 min) · Serie · Online-Meeting · 8 Teilnehmer“, bei Serien „Zuordnung für die ganze Serie“ mit Projekt, Kategorie und „+ Work Item verknüpfen (optional)“, Button „Ab 09:45 starten“ bzw. „Timer starten“ (CA-12, CA-20). Darunter bei Serien „Zu Terminbeginn Timer anbieten“ und „Timer endet mit dem Termin“ (CA-21, CA-22) |
| Menüleiste | Regeltermin Start/Ende (Phase 3) | Pro Serie in der Vorschau-Karte: „Zu Terminbeginn Timer anbieten“, „Timer endet mit dem Termin“. Mitteilung zum Terminbeginn „Daily beginnt“ mit „Plattform · Meeting · bis 10:00“ und „„Login-Flow“ wird pausiert und läuft danach weiter.“, Button „Timer starten“ (Wegwischen = Ignorieren). Timerzeile „endet 10:00“. Zum Ende Toast und Mitteilung „Daily beendet · 0:15 h“ / „„Login-Flow“ läuft weiter.“ mit „Verlängern“ (CA-21, CA-22) |
| Hauptfenster | Heute | Seitenleiste Heute, Tagesabschluss, Woche, Einträge, Analysen, Projekte, Einstellungen, unten links dezent die Version als Release-Tag („v0.6.1“, Tooltip mit Build); KPI-Zeile (Erfasst, Pausen, Einträge, Parallel, Fokusblöcke wie in den Analysen, ggf. ArbZG-Marker mit Details im Tooltip, AZ-02); Timeline über 24 h, scrollt zur aktuellen Stunde, Zeit außerhalb der Rahmenarbeitszeit und arbeitsfreie Tage dezent abgedunkelt (`offHours`, HW-08), parallele Spur, Pausen und Inaktivität schraffiert, „jetzt“-Linie; nicht erfasste Outlook-Termine (bei eingeschaltetem Kalender) blass mit gestricheltem Rand, Titel und „Outlook · zum Übernehmen klicken“, ein Klick übernimmt sie als Eintrag (CA-23); rechts der Inspektor des gewählten Eintrags (eigene Spalte von 300 pt, beginnt unter der Toolbar) |
| Hauptfenster | Tagesabschluss | Eigener Bereich: „Zu buchen“ mit Summe, daneben ggf. der ArbZG-Marker, Hinweis auf wartende Buchungen mit „Erneut senden“, Gruppen je Work Item mit Soll, Gebucht, Differenz und einer Checkbox je offener Differenz zum Abwählen; Einträge ohne Work Item mit „Verknüpfen …“; „Alles buchen“ bzw. nach dem Abwählen „2 Einträge buchen · +3,75 h“ mit ⌘↩ (nicht ↩, damit Return in einem Inspektorfeld nichts bucht); darunter dezent der Monatsabschluss (AZ-10): Vormonat noch nicht archiviert mit „Archivieren“, Arbeitstage seit über 7 Tagen ohne Aufzeichnung mit „Zeigen“ |
| Hauptfenster | Woche | Kalenderraster Mo–So mit Tagessummen, Zeit außerhalb der Rahmenarbeitszeit sowie Wochenende und Feiertage dezent abgedunkelt (HW-08), und ggf. Abwesenheit (AZ-05) oder Feiertagsname (AZ-03) im Kopf, Kontextmenü „Abwesenheit“ am Kopf, heutiger Tag hervorgehoben; Doppelklick auf einen Tag öffnet ihn; Einträge per Drag auf andere Uhrzeit oder anderen Tag verschieben |
| Hauptfenster | Einträge | Tabelle mit Inline-Titel, Projekt, Zeit, Dauer, Zählweise; Mehrfachauswahl mit Sammeländerung im Inspektor |
| Hauptfenster | Projekte | Projekte mit Tasks, Kategorien, Tags und Regeln; Farbe und Symbol per Menü, Archivieren statt Löschen, ADO-Kennzeichnung; je Kategorie Häkchen „Arbeitszeit“ (AZ-01) |
| Hauptfenster | Einstellungen | Farbschema (Theme-Karten und Darstellung System/Hell/Dunkel, HW-07), Allgemein (u. a. Arbeitstage, Rahmenarbeitszeit von–bis (Standard 6–19 Uhr, HW-08), Arbeitszeitmodell, Startsaldo und Stichtag des Flexkontos, Übertragsgrenze ins Folgejahr, Quartalskontingent für vergütete Überstunden, Urlaubstage pro Jahr und Resturlaub aus dem Vorjahr, Feiertage nach Bundesland), Erfassung, Erinnerung (an/aus, Abstand; gilt in der Rahmenarbeitszeit), Monatsabschluss (Archivordner, automatisch zum Monatsanfang, AZ-10), Kurzbefehle, Kommandozeile (`takt` mit Status „Installiert“ und „Installieren …“, das nach `/usr/local/bin` verlinkt; CL-01), Azure DevOps, Microsoft-Konto (angemeldet Name und Adresse mit „Abmelden“ und darunter der Schalter „Outlook-Termine in der Suche zeigen“ (standardmäßig aus, CA-01); abgemeldet die Felder „Client-ID“ und „Tenant-ID“ der App-Registrierung (per MDM vorgegeben gesperrt, #242), darunter „Nicht angemeldet“ und „Mit Microsoft anmelden …“, gesperrt bis beide IDs eingetragen sind; die Anmeldung öffnet ein eigenes Fenster von 480 × 640 pt mit der Microsoft-Anmeldeseite, ohne Safari-Sitzung; Schließen bricht ab, DO-01, CA-02), Daten (Backup, Export, Import, „Auf Werkseinstellungen zurücksetzen …“ in Rot mit kritischem Hinweis, „Abbrechen“ als Standard), Über Takt (Version mit Build, Links zu Website, Quellcode, Versionshinweisen und „Problem melden“); von MDM vorgegebene Werte gesperrt mit Hinweis „Von deiner Organisation vorgegeben“ |
| Hauptfenster | Suchergebnisse | Suchfeld in der Toolbar („Einträge, Projekte, Work Items“, 286 pt breit, damit es über der Inspektorspalte liegt und „+“ und der Inspektor-Button links davon) ersetzt den Bereich durch Treffer: Einträge, dann Work Items wie im Popover (Typ-Badge, Nummer, Titel mit Treffer fett, Status farbig, darunter Zuweisung · Projekt · Iteration · Parent; nach Status sortiert, Removed/Cancelled ausgeblendet; Klick öffnet Azure DevOps), dann Projekte, Tasks, Kategorien, Tags |
| Hauptfenster | Befehlspalette ⌘K | Sheet mit unscharfer Suche über alle Aktionen, „Timer „…“ starten“, Einträge und gecachte Work Items |
| Hauptfenster | Analysen | Zeitraum-Segmente, Gruppieren nach, Zählweise (Pro Eintrag, Voll, Geteilt); KPIs mit Vergleich zur Vorperiode als Differenz („+2:10 h ggü. KW 40“, Fokusblöcke und Wechsel pro Tag ebenso, Verbesserung im Akzent), Multitasking mit paralleler Zeit, Soll/Ist und Flexkonto (AZ-05, nicht bei Vertrauensarbeitszeit; Klick öffnet die Vergütungen mit „Überstunden vergüten …“, mit Kontingent darunter die Quartalszeile, AZ-07; ab 1.10. stattdessen „X verfallen zum Jahreswechsel“ über der Übertragsgrenze, AZ-08), Urlaub des laufenden Jahres mit Hinweis auf offenen Vorjahresurlaub bis 31.3. (AZ-06); Insight-Satz als Titel der Tagesbalken („Dienstag war der längste Tag, Entwicklung überwiegt“), gestapelte Balken je Tag; rechts Verteilung nach der Gruppierung, darunter „Nach Projekt“ mit Anteil in % und „Top Work Items“ (jeweils nicht, wenn schon danach gruppiert wird); Heatmap (Hover-Label je Zelle: Wochentag, Stunde, Zeit; wie die Labels der Diagramme über allen Säulen und Zellen gezeichnet) 06–22 Uhr; Export CSV, Excel (.xlsx, AN-08), JSON, PDF und Arbeitszeitnachweis als PDF, CSV oder Excel (AZ-09, im Speichern-Dialog „Namen weglassen“); Tooltips beim Überfahren: Balkenabschnitt (Tag, Gruppe, Dauer, Tagessumme), Donut (Gruppe, Dauer, Anteil in der Mitte), Heatmap-Zelle (Wochentag, Stunde, Minuten), KPI (Erklärung, Vorperiodenwert und Differenz) |
| Hauptfenster | Eintrag bearbeiten | Ziehen in der Timeline mit Zeit-Tooltip; Inspektor mit Segmenten, „+ Segment“ (30 min nach dem letzten), Pause umwandeln, Herkunft „aus Inaktivität“ an der Pause, Hinweis „Parallel zu …, 30 min“ über der Zählweise, Gewichtsregler als Faktor, Buchungshinweis mit konkreter Differenz („Bereits gebucht: 2,25 h. Nach der Änderung sind es 2,50 h; die Differenz von +0,25 h wird im nächsten Tagesabschluss nachgebucht.“); „korrigiert“ unter den Segmenten mit dem Änderungsprotokoll im Tooltip (AZ-04); bei Änderungen älter als 7 Tage optional ein Alert „Grund der Korrektur“ |
| Dark Mode | Popover, Heute | Gleiche Struktur, aufgehellte Akzente |
| Onboarding | 3 Schritte | 1. ADO per PAT verbinden + Projekte wählen, darunter (nur wenn Client- und Tenant-ID eingetragen oder per MDM gesetzt sind) der Schalter „Outlook-Termine in der Suche zeigen“; Einschalten meldet zuerst mit dem Arbeitskonto an, bei Abbruch bleibt er aus (CA-01), 2. Kürzel „Takt öffnen“ aufnehmen und live testen („Alle pausieren“ nur in den Einstellungen), 3. Startverhalten als Auswahlkarten „Wechseln“ / „Parallel“ mit Erklärung (so hoch wie der längere Text), Zählweise mit Mini-Beispiel |

## Farben

Systemschrift und Systemmaterialien; eigene Farben nur für Status und Kategorien. Die Tokens unten sind das Standard-Theme „Takt“ mit Hell- und Dunkel-Variante.

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
| `offHours` | Schwarz 4,5 % | Schwarz 22 % | Zeit außerhalb der Rahmenarbeitszeit in den Timelines (HW-08), über dem Fensterhintergrund in jedem Theme |

**Kategorien** (Standardwerte, pro Kategorie änderbar)

| Kategorie | Hell | Dunkel | Timeline-Fläche hell / dunkel |
| --- | --- | --- | --- |
| Entwicklung | `#2563EB` | `#60A5FA` | `#DBEAFE` / `#1E2B4D` |
| Meeting | `#C2410C` | `#FB923C` | `#FFEDD5` / `#41281A` |
| Review | `#7C3AED` | `#A78BFA` | `#EDE9FE` / `#2E2650` |
| Support | `#DB2777` | `#F472B6` | `#FCE7F3` / `#4A1D35` |

**Themes** (HW-07, `TaktUI/Theme.swift`)

- Einstellungen → Farbschema: Karten mit Mini-Vorschau (Seitenleiste, Akzentbalken, Textzeilen, Auswahl-, Warn- und Fehlerfarbe; bei zwei Varianten links hell, rechts dunkel), Name und „Hell · Dunkel“ bzw. „Dunkel“, Tooltip mit den Namen der Varianten; die gewählte Karte mit Akzentrahmen und Häkchen. Darunter „Darstellung“ als Segmente System, Hell, Dunkel; bei Themes mit nur einer Variante deaktiviert, mit Hinweis „Tokyo Night gibt es nur in Dunkel.“
- Ein Theme liefert dieselben Tokens wie oben, dazu Fenster- und Seitenleistenhintergrund. Das Standard-Theme lässt Fensterhintergrund, Seitenleiste, Textfarbe und Tint beim System (Systemmaterialien); alle anderen malen Fenster, Popover und Seitenleiste in ihrer Hintergrundfarbe, Text in `textPrimary`, Bedienelemente im Akzent. Tabellen verzichten dann auf die System-Streifen.
- Themes mit nur einer Variante legen Hell oder Dunkel für alle Fenster, Menüs und Dialoge fest. Ein Wechsel wirkt sofort, ohne Neustart.
- Kategorie- und Projektfarben bleiben die gewählten (Hell-/Dunkel-Variante nach dem Erscheinungsbild). Die Menüleiste färbt nicht mit; die ausgewählte Zeile der Seitenleiste nutzt bei Fokus die Akzentfarbe der App (macOS).
- Kontrast in jedem Theme und jeder Variante: Text, Sekundärtext, Akzenttext und Warnung 4,5:1 auf Hintergrund und Seitenleiste, Akzent als Bedienelement 3:1 (Test `ThemeTests`). Wo die Vorlage das verfehlt (z. B. gedämpfte Kommentarfarben), ist der Wert aufgehellt bzw. abgedunkelt.

| Theme | Varianten | Hintergrund | Akzent |
| --- | --- | --- | --- |
| Takt (Standard) | Hell, Dunkel | Systemmaterial | `#0F766E` / `#2DD4BF` |
| GitHub | Light, Dark | `#FFFFFF` / `#0D1117` | `#0969DA` / `#1F6FEB` |
| SAP Fiori Horizon | Morning, Evening | `#F5F6F7` / `#12171C` | `#0070F2` / `#4DB1FF` |
| Tokyo Night | Dunkel | `#1A1B26` | `#7AA2F7` |
| Aura Dark | Dunkel | `#15141B` | `#A277FF` |
| Panda | Dunkel | `#292A2B` | `#FF75B5` |
| Dracula | Dunkel | `#282A36` | `#BD93F9` |
| One Dark | Dunkel | `#282C34` | `#61AFEF` |
| Nord | Dunkel | `#2E3440` | `#88C0D0` |
| Catppuccin Mocha | Dunkel | `#1E1E2E` | `#CBA6F7` |

**Work-Item-Typen** (Badge mit Buchstabe, Farben wie in Azure DevOps): Task `#A16207`, Bug `#B91C1C`, User Story/Product Backlog Item `#0369A1`, Feature `#7E22CE` (lila), Epic `#EA580C` (orange), andere `#475569`. Buchstabe (wie das Häkchen auf Farbmustern) weiß oder schwarz, je nachdem, was auf der Fläche mehr Kontrast hat – mindestens 4,5:1, auch mit den Dunkel-Varianten.

## Typografie

- Systemschrift (SF Pro). Zeiten in SF Mono mit tabellarischen Ziffern (`.monospacedDigit()`).
- Größen: Laufzeit im Popover 19 pt semibold, KPI-Werte 20–24 pt, Titel 13–14 pt semibold, Metadaten 12 pt, Abschnittstitel 11 pt uppercase.

## Interaktionsregeln

- Das Suchfeld im Popover hat beim Öffnen immer den Fokus. Enter startet, ⌥↩ startet parallel.
- Undo statt Rückfrage: Stoppen, Löschen, Verschieben sind sofort und per ⌘Z rückgängig zu machen.
- Pausen und Inaktivität werden schraffiert dargestellt, nie als leere Lücke.
- Wechsel auf Heute, Tagesabschluss oder Woche über die Seitenleiste oder ⌘K zeigt immer den heutigen Tag bzw. die aktuelle Woche (#244). Sprünge auf einen bestimmten Tag (Tageskopf in der Woche, Suchtreffer, Monatsabschluss) behalten ihren Tag.
- Ein Klick auf einen Eintrag (Heute, Tagesabschluss, Woche, Einträge) wählt ihn aus und öffnet den Inspektor; ⌘-Klick ergänzt oder entfernt ihn in der Auswahl, ein Klick auf eine freie Stelle der Timeline hebt die Auswahl auf. Inspektor ein- und ausblenden mit ⌥⌘I.
- Timeline per Tastatur (Heute, Woche, #171): Die Timeline hat beim Öffnen und nach jedem Klick den Fokus. ↑/↓ geht zum vorherigen/nächsten Block nach Beginn und Spur und wählt ihn aus (Start beim ausgewählten Eintrag), ⇧↑/⇧↓ erweitert die Auswahl, ←/→ springt in der Woche zum zeitlich nächsten Block des Nachbartags, ⌥↑/⌥↓ verschiebt um 5 min (je ein Undo-Schritt), ↩/Leertaste öffnet den Inspektor, ⌫ löscht. Fokusring 2,5 pt in der Akzentfarbe außerhalb der Auswahl; der fokussierte Block bleibt im sichtbaren Bereich, VoiceOver sagt Titel und Zeit an. Am Anfang oder Ende scrollen die Pfeile wie gewohnt.
- Zoom der Timeline (Heute, Woche, #245): Trackpad-Pinch stufenlos, ⌘+ / ⌘− in Stufen (24, 32, 40, 56, 80, 120, 160 pt pro Stunde), ⌘0 zurück auf den Standard (Heute 56, Woche 40); dieselben Befehle in ⌘K, auch für VoiceOver. Die Zeit unter den Fingern bzw. in der Mitte bleibt an ihrer Stelle; ab 120 pt zeigen dünne Linien die Viertelstunden. Die Stufe wird je Sicht gemerkt.
- Rechtsklick auf einen Eintrag (Heute, Woche, Einträge) bietet „Löschen“: gelöscht wird der ganze Eintrag, bei Mehrfachauswahl alle ausgewählten; ⌘Z macht es rückgängig. Auf einer Pause zusätzlich „Als Arbeitszeit zählen“.
- Rechtsklick auf eine freie Stelle der Timeline (Heute) oder auf den Kopf einer Wochenspalte bietet „Abwesenheit“ mit Urlaub, Krank, Frei (AZ-05); ⌘K bietet dasselbe für den angezeigten Tag.
- Überstunden vergüten (AZ-07): Klick auf die Kennzahl „Flexkonto“ (Popover mit den Vergütungen des Jahres) oder ⌘K öffnet ein Sheet mit Stunden, Datum und Notiz. Hinweise auf ein überschrittenes Quartalskontingent oder ein negatives Flexkonto stehen im Sheet, gesperrt wird nichts; ⌘↩ vergütet.
- Fehlende Zuordnung (kein Work Item) ist Amber, nicht Rot.
- Diagramme zeigen genaue Werte beim Überfahren mit der Maus: Hilfe-Tooltip (`.help`) oder kleines Label im Diagramm, keine zusätzlichen Bedienelemente. VoiceOver bekommt dieselben Werte.
- Eine Hauptaktion pro Ansicht; Primärbutton immer `accent`.
- Touch-Ziele mindestens 28 pt in der Menüleiste, 32 pt im Hauptfenster; alle Icon-Buttons mit Accessibility-Label.
