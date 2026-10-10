import Foundation

/// A minimal Office Open XML spreadsheet writer (AN-08): typed cells, shared strings, a bold and
/// frozen header row with autofilter, column widths from the content. No formulas, no images, no
/// dependency; the container is a `ZipArchive` without compression.
public enum XLSXWriter {

  // MARK: Public

  public enum Cell: Hashable, Sendable {
    case text(String)
    case number(Double, NumberFormat = .general)
    /// `YYYY-MM-DD`, shown in the reader's short date format. Anything else is written as text.
    case day(String)
    case empty
  }

  public enum NumberFormat: Hashable, Sendable {
    case general
    /// `0`
    case integer
    /// `0.00`
    case decimal
    /// `0 %`
    case percent
  }

  public struct Sheet: Hashable, Sendable {

    // MARK: Lifecycle

    /// The first row is the header: bold, frozen and with an autofilter over all rows.
    public init(name: String, header: [String], rows: [[Cell]]) {
      self.name = name
      self.header = header
      self.rows = rows
    }

    // MARK: Public

    public var name: String
    public var header: [String]
    public var rows: [[Cell]]
  }

  public static func workbook(_ sheets: [Sheet]) -> Data {
    var strings = SharedStrings()
    let names = uniqueSheetNames(sheets.map(\.name))
    let worksheets = sheets.enumerated().map { index, sheet in
      worksheet(sheet, selected: index == 0, strings: &strings)
    }

    var zip = ZipArchive()
    zip.add("[Content_Types].xml", contentTypes(sheetCount: sheets.count))
    zip.add("_rels/.rels", rootRelationships)
    zip.add("xl/workbook.xml", workbook(names: names, sheets: sheets))
    zip.add("xl/_rels/workbook.xml.rels", workbookRelationships(sheetCount: sheets.count))
    zip.add("xl/styles.xml", styles)
    for (index, xml) in worksheets.enumerated() {
      zip.add("xl/worksheets/sheet\(index + 1).xml", xml)
    }
    zip.add("xl/sharedStrings.xml", strings.xml)
    return zip.data()
  }

  // MARK: Internal

  /// Days since 1899-12-30, Excel's serial date (1900 system); `nil` unless `YYYY-MM-DD`.
  static func serial(ofDay day: String) -> Int? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1900...9999).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2])
    else { return nil }
    return daysFromCivil(year: parts[0], month: parts[1], day: parts[2]) - daysFromCivil(year: 1899, month: 12, day: 30)
  }

  /// `A`, `B`, … `Z`, `AA`, … for a zero-based column index.
  static func columnName(_ index: Int) -> String {
    var name = ""
    var rest = index + 1
    while rest > 0 {
      let digit = (rest - 1) % 26
      name = String(UnicodeScalar(UInt8(65 + digit))) + name
      rest = (rest - 1) / 26
    }
    return name
  }

  /// Escapes XML's five special characters. Characters XML 1.0 does not allow (control characters
  /// other than tab, LF and CR, U+FFFE, U+FFFF) become `_xHHHH_` as in OOXML; an underscore that
  /// would read as such an escape becomes `_x005F_`.
  static func escape(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    let scalars = Array(text.unicodeScalars)
    for (index, scalar) in scalars.enumerated() {
      switch scalar {
      case "&": result += "&amp;"
      case "<": result += "&lt;"
      case ">": result += "&gt;"
      case "\"": result += "&quot;"
      case "'": result += "&apos;"
      case "_" where looksLikeEscape(scalars[(index + 1)...]): result += "_x005F_"
      case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
      case _ where scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF:
        result += "_x" + hex4(scalar.value) + "_"
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  // MARK: Private

  /// Shared string table: each distinct text once, cells refer to it by index.
  private struct SharedStrings {
    var indices = [String: Int]()
    var values = [String]()
    var references = 0

    var xml: String {
      let items = values.map { value in
        // Leading or trailing spaces and line breaks would otherwise be dropped.
        let preserve = value.first?.isWhitespace == true || value.last?.isWhitespace == true
        return "<si><t\(preserve ? " xml:space=\"preserve\"" : "")>\(escape(value))</t></si>"
      }
      return xmlHeader + """
        <sst xmlns="\(mainNamespace)" count="\(references)" uniqueCount="\(values.count)">\(items.joined())</sst>
        """
    }

    mutating func index(of value: String) -> Int {
      references += 1
      if let index = indices[value] { return index }
      values.append(value)
      indices[value] = values.count - 1
      return values.count - 1
    }
  }

  /// Style indices in `cellXfs` of `styles`.
  private enum Style: Int {
    case plain = 0
    case header = 1
    case date = 2
    case decimal = 3
    case integer = 4
    case percent = 5
  }

  private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
  private static let mainNamespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  private static let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  private static let packageRelationshipNamespace = "http://schemas.openxmlformats.org/package/2006/relationships"

  private static let rootRelationships = xmlHeader + """
    <Relationships xmlns="\(packageRelationshipNamespace)">\
    <Relationship Id="rId1" Type="\(relationshipNamespace)/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

  /// Fonts: regular, bold. Number formats are built in: 14 short date, 1 `0`, 2 `0.00`, 9 `0%`.
  private static let styles = xmlHeader + """
    <styleSheet xmlns="\(mainNamespace)">\
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font>\
    <font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>\
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="6">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="9" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """

  private static func contentTypes(sheetCount: Int) -> String {
    let sheets = (0..<sheetCount).map {
      "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" "
        + "ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
    }
    return xmlHeader + """
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
      <Default Extension="xml" ContentType="application/xml"/>\
      <Override PartName="/xl/workbook.xml" \
      ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
      \(sheets.joined())\
      <Override PartName="/xl/styles.xml" \
      ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
      <Override PartName="/xl/sharedStrings.xml" \
      ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\
      </Types>
      """
  }

  private static func workbook(names: [String], sheets: [Sheet]) -> String {
    let entries = names.enumerated().map { index, name in
      "<sheet name=\"\(escape(name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
    }
    // Excel keeps an autofilter's range in this hidden name; without it, it may drop the filter.
    let filters = zip(names, sheets).enumerated().compactMap { index, pair -> String? in
      let (name, sheet) = pair
      guard !sheet.header.isEmpty else { return nil }
      let quoted = "'" + name.replacingOccurrences(of: "'", with: "''") + "'"
      let lastColumn = columnName(sheet.header.count - 1)
      let range = "\(quoted)!$A$1:$\(lastColumn)$\(sheet.rows.count + 1)"
      return "<definedName name=\"_xlnm._FilterDatabase\" localSheetId=\"\(index)\" hidden=\"1\">"
        + escape(range) + "</definedName>"
    }
    return xmlHeader + """
      <workbook xmlns="\(mainNamespace)" xmlns:r="\(relationshipNamespace)">\
      <bookViews><workbookView activeTab="0"/></bookViews>\
      <sheets>\(entries.joined())</sheets>\
      \(filters.isEmpty ? "" : "<definedNames>\(filters.joined())</definedNames>")\
      </workbook>
      """
  }

  private static func workbookRelationships(sheetCount: Int) -> String {
    let sheets = (0..<sheetCount).map {
      "<Relationship Id=\"rId\($0 + 1)\" Type=\"\(relationshipNamespace)/worksheet\" "
        + "Target=\"worksheets/sheet\($0 + 1).xml\"/>"
    }
    return xmlHeader + """
      <Relationships xmlns="\(packageRelationshipNamespace)">\(sheets.joined())\
      <Relationship Id="rId\(sheetCount + 1)" Type="\(relationshipNamespace)/styles" Target="styles.xml"/>\
      <Relationship Id="rId\(sheetCount + 2)" Type="\(relationshipNamespace)/sharedStrings" \
      Target="sharedStrings.xml"/>\
      </Relationships>
      """
  }

  private static func worksheet(_ sheet: Sheet, selected: Bool, strings: inout SharedStrings) -> String {
    let columnCount = max(sheet.header.count, sheet.rows.map(\.count).max() ?? 0)
    let lastColumn = columnName(max(columnCount - 1, 0))
    let lastRow = sheet.rows.count + 1

    var rows = [String]()
    if !sheet.header.isEmpty {
      let cells = sheet.header.enumerated().map { column, title in
        "<c r=\"\(columnName(column))1\" s=\"\(Style.header.rawValue)\" t=\"s\"><v>\(strings.index(of: title))</v></c>"
      }
      rows.append("<row r=\"1\">\(cells.joined())</row>")
    }
    for (offset, row) in sheet.rows.enumerated() {
      let number = offset + 2
      let cells = row.enumerated().compactMap { column, cell in
        xml(cell, at: "\(columnName(column))\(number)", strings: &strings)
      }
      rows.append("<row r=\"\(number)\">\(cells.joined())</row>")
    }

    let widths = (0..<columnCount).map { column in
      let header = column < sheet.header.count ? sheet.header[column].count + 3 : 0
      let content = sheet.rows.lazy.map { column < $0.count ? displayLength($0[column]) : 0 }.max() ?? 0
      let width = min(max(Double(max(header, content)) + 2, 8), 60)
      return "<col min=\"\(column + 1)\" max=\"\(column + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
    }
    let pane =
      sheet.header.isEmpty
        ? ""
        : "<pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/>"
          + "<selection pane=\"bottomLeft\" activeCell=\"A2\" sqref=\"A2\"/>"
    let filter = sheet.header.isEmpty ? "" : "<autoFilter ref=\"A1:\(lastColumn)\(lastRow)\"/>"

    return xmlHeader + """
      <worksheet xmlns="\(mainNamespace)" xmlns:r="\(relationshipNamespace)">\
      <dimension ref="A1:\(lastColumn)\(lastRow)"/>\
      <sheetViews><sheetView\(selected ? " tabSelected=\"1\"" : "") workbookViewId="0">\(pane)</sheetView></sheetViews>\
      <sheetFormatPr defaultRowHeight="15"/>\
      \(widths.isEmpty ? "" : "<cols>\(widths.joined())</cols>")\
      <sheetData>\(rows.joined())</sheetData>\
      \(filter)\
      </worksheet>
      """
  }

  private static func xml(_ cell: Cell, at reference: String, strings: inout SharedStrings) -> String? {
    switch cell {
    case .empty:
      return nil

    case .text(let value):
      return "<c r=\"\(reference)\" t=\"s\"><v>\(strings.index(of: value))</v></c>"

    case .number(let value, let format):
      guard value.isFinite else { return nil }
      let style: Style =
        switch format {
        case .general: .plain
        case .integer: .integer
        case .decimal: .decimal
        case .percent: .percent
        }
      let styleAttribute = style == .plain ? "" : " s=\"\(style.rawValue)\""
      return "<c r=\"\(reference)\"\(styleAttribute)><v>\(number(value))</v></c>"

    case .day(let value):
      guard let serial = serial(ofDay: value) else {
        return xml(.text(value), at: reference, strings: &strings)
      }
      return "<c r=\"\(reference)\" s=\"\(Style.date.rawValue)\"><v>\(serial)</v></c>"
    }
  }

  /// Characters a column needs to show the cell, roughly.
  private static func displayLength(_ cell: Cell) -> Int {
    switch cell {
    case .empty: 0

    case .text(let value): value.split(whereSeparator: \.isNewline).lazy.map(\.count).max() ?? 0

    case .number(let value, let format):
      switch format {
      case .general: number(value).count
      case .integer: String(Int(value.rounded())).count
      case .decimal: String(Int(value.rounded(.towardZero))).count + 3
      case .percent: 5
      }

    case .day: 10
    }
  }

  /// Shortest round-tripping decimal, never in exponent notation for whole numbers.
  private static func number(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
    return "\(value)"
  }

  private static func uniqueSheetNames(_ names: [String]) -> [String] {
    var used = Set<String>()
    return names.enumerated().map { index, name in
      // Excel: at most 31 characters, none of : \ / ? * [ ], unique ignoring case.
      let cleaned = String(name.filter { !":\\/?*[]".contains($0) }.prefix(31))
      var candidate = cleaned.isEmpty ? "Sheet\(index + 1)" : cleaned
      var suffix = 2
      while used.contains(candidate.lowercased()) {
        candidate = String(cleaned.prefix(28)) + " \(suffix)"
        suffix += 1
      }
      used.insert(candidate.lowercased())
      return candidate
    }
  }

  private static func looksLikeEscape(_ rest: ArraySlice<Unicode.Scalar>) -> Bool {
    let next = Array(rest.prefix(6))
    guard next.count == 6, next[0] == "x", next[5] == "_" else { return false }
    return next[1...4].allSatisfy { $0.properties.isASCIIHexDigit }
  }

  private static func hex4(_ value: UInt32) -> String {
    let digits = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
  }

  /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's algorithm).
  private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
    let shiftedYear = month <= 2 ? year - 1 : year
    let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
    let yearOfEra = shiftedYear - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }
}
