#!/usr/bin/env python3
"""Reads the Excel timesheet ("Zeiterfassungstabelle … Vollzeit V2") into JSON for `takt import` (#190).

Usage:
  uv run --with openpyxl scripts/timesheet-to-json.py <timesheet.xlsx> [out.json]

Only input columns are read (B date, C flex day, D marker, M/N start/end, P break, Q/R, AA note);
formula columns serve the comparison only (sheet "Summenblatt"). Nothing is written to Takt here.
The JSON contains personal working time data: keep it out of the repository.
"""
import datetime as dt
import json
import sys

import openpyxl

MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
          "November", "Dezember"]
FIRST_ROW, LAST_ROW = 20, 50
STATES = {
    "baden-württemberg": "BW", "bayern": "BY", "berlin": "BE", "brandenburg": "BB", "bremen": "HB",
    "hamburg": "HH", "hessen": "HE", "mecklenburg-vorpommern": "MV", "niedersachsen": "NI",
    "nordrhein-westfalen": "NW", "rheinland-pfalz": "RP", "saarland": "SL", "sachsen": "SN",
    "sachsen-anhalt": "ST", "schleswig-holstein": "SH", "thüringen": "TH",
}
ABSENCES = {"U": "vacation", "K": "sick"}
MARKERS = {"A": "Abfeiern", "S": "Sonderurlaub", "X": "Arbeitsfrei", "H": "Homeoffice", "G": "Geschäft",
           "R": "Reise"}


def minutes(value):
    """Minutes of a time or duration cell; None if empty."""
    if value is None or value == "":
        return None
    if isinstance(value, dt.time):
        return value.hour * 60 + value.minute + round(value.second / 60)
    if isinstance(value, dt.timedelta):
        return round(value.total_seconds() / 60)
    if isinstance(value, dt.datetime):
        # Durations above 24 h are stored as dates after 1899-12-30.
        return round((value - dt.datetime(1899, 12, 30)).total_seconds() / 60)
    if isinstance(value, (int, float)):
        return round(value * 24 * 60)
    raise ValueError(f"not a time: {value!r}")


def clock(total):
    return f"{total // 60:02d}:{total % 60:02d}"


def state_code(name):
    key = "".join(str(name or "").lower().split()).replace("–", "-")
    return STATES.get(key)


def main():
    path = sys.argv[1]
    book = openpyxl.load_workbook(path, data_only=True)
    january = book["Januar"]
    sign = -1 if str(january["C12"].value or "+").strip() == "-" else 1
    warnings = []
    state = state_code(january["P3"].value)
    if state is None:
        warnings.append(f"Bundesland nicht erkannt: {january['P3'].value!r}")
    settings = {
        "weeklyHours": january["A7"].value,
        "federalState": state,
        "flexStartBalanceMinutes": sign * (minutes(january["M12"].value) or 0),
        "vacationCarryoverDays": january["N16"].value or 0,
        "vacationDaysPerYear": january["P16"].value,
    }
    days, year = [], None
    for month_index, name in enumerate(MONTHS, start=1):
        sheet = book[name]
        for row in range(FIRST_ROW, LAST_ROW + 1):
            date = sheet[f"B{row}"].value
            if not isinstance(date, dt.datetime) or date.month != month_index:
                continue
            year = year or date.year
            day = date.date().isoformat()
            flex_day = str(sheet[f"C{row}"].value or "").strip().upper() == "F"
            marker = str(sheet[f"D{row}"].value or "").strip().upper()
            start, end = minutes(sheet[f"M{row}"].value), minutes(sheet[f"N{row}"].value)
            pause = minutes(sheet[f"P{row}"].value) or 0
            note = sheet[f"AA{row}"].value
            note = str(note).strip() if note not in (None, "") else None
            for column, label in (("Q", "Geleistete Überstunden"), ("R", "Betriebsbedingte Fehlzeit")):
                if minutes(sheet[f"{column}{row}"].value):
                    warnings.append(f"{day}: Spalte {column} ({label}) ist belegt und wird nicht importiert")
            if marker in MARKERS:
                warnings.append(f"{day}: Kennzeichen {marker} ({MARKERS[marker]}) wird nicht importiert")
            entry = {"date": day}
            if note:
                entry["note"] = note
            if flex_day:
                entry["flexDay"] = True
            if marker in ABSENCES:
                entry["absence"] = ABSENCES[marker]
            if start is not None and end is not None:
                if end <= start:
                    warnings.append(f"{day}: Ende {clock(end)} nicht nach Beginn {clock(start)}, übersprungen")
                else:
                    entry.update(start=clock(start), end=clock(end), pauseMinutes=pause)
                    if "absence" in entry:
                        warnings.append(f"{day}: Arbeitszeit und Kennzeichen {marker} am selben Tag")
            elif (start is None) != (end is None):
                warnings.append(f"{day}: nur Beginn oder nur Ende eingetragen, übersprungen")
            # A note alone (e.g. a public holiday's name) has nothing to attach to.
            if "start" in entry or "absence" in entry or flex_day:
                days.append(entry)
    summary = book["Summenblatt"]
    months, total = [], None
    for row in summary.iter_rows(values_only=True):
        cells = [cell for cell in row if cell is not None]
        if len(cells) >= 3 and cells[0] in MONTHS and isinstance(cells[2], (int, float)):
            months.append({"month": f"{year}-{MONTHS.index(cells[0]) + 1:02d}", "flexHours": round(cells[2], 4)})
        elif len(cells) >= 3 and cells[0] == "Gesamtsaldo" and isinstance(cells[2], (int, float)):
            total = round(cells[2], 4)
    result = {
        "format": 1,
        "year": year,
        "settings": settings,
        "days": days,
        "months": months,
        "totalFlexHours": total,
        "warnings": warnings,
    }
    text = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w", encoding="utf-8") as file:
            file.write(text)
        worked = sum(1 for day in days if "start" in day)
        absent = sum(1 for day in days if "absence" in day)
        print(f"{worked} Arbeitstage, {absent} Abwesenheiten, {len(warnings)} Hinweise → {sys.argv[2]}", file=sys.stderr)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
