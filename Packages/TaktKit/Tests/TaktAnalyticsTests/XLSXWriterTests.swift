import Foundation
import Testing

@testable import TaktAnalytics

// MARK: - ZipArchiveTests

struct ZipArchiveTests {
  @Test(arguments: [
    ("", UInt32(0)),
    ("a", UInt32(0xE8B7_BE43)),
    ("123456789", UInt32(0xCBF4_3926)),
    ("The quick brown fox jumps over the lazy dog", UInt32(0x414F_A339)),
  ])
  func crc32MatchesKnownValues(input: String, expected: UInt32) {
    #expect(ZipArchive.crc32(Data(input.utf8)) == expected)
  }

  @Test
  func archiveHasLocalHeadersCentralDirectoryAndEndRecord() throws {
    var zip = ZipArchive()
    zip.add("a.txt", "Hallo")
    zip.add("dir/ü.xml", "<x/>")
    let data = zip.data()

    #expect(data.uint32(at: 0) == 0x0403_4B50)
    #expect(data.uint16(at: 8) == 0) // stored
    #expect(data.uint32(at: 14) == ZipArchive.crc32(Data("Hallo".utf8)))
    #expect(data.uint32(at: 18) == 5)
    #expect(data.uint32(at: 22) == 5)

    let end = data.count - 22
    #expect(data.uint32(at: end) == 0x0605_4B50)
    #expect(data.uint16(at: end + 10) == 2)
    let centralSize = Int(data.uint32(at: end + 12))
    let centralOffset = Int(data.uint32(at: end + 16))
    #expect(centralOffset + centralSize == end)
    #expect(data.uint32(at: centralOffset) == 0x0201_4B50)

    let files = try ZipReader.files(data)
    #expect(files.keys.sorted() == ["a.txt", "dir/ü.xml"])
    #expect(files["dir/ü.xml"] == "<x/>")
  }

  @Test
  func sameInputGivesSameBytes() {
    var zip = ZipArchive()
    zip.add("a.txt", "Hallo")
    #expect(zip.data() == zip.data())
  }
}

// MARK: - XLSXWriterTests

struct XLSXWriterTests {

  // MARK: Internal

  @Test
  func escapesSpecialAndControlCharacters() {
    #expect(XLSXWriter.escape(#"<a href="x">Tom & 'Jerry'</a>"#)
      == "&lt;a href=&quot;x&quot;&gt;Tom &amp; &apos;Jerry&apos;&lt;/a&gt;")
    #expect(XLSXWriter.escape("a\u{0}b\u{1B}c\td\ne") == "a_x0000_b_x001B_c\td\ne")
    #expect(XLSXWriter.escape("_x0041_ and _x") == "_x005F_x0041_ and _x")
    #expect(XLSXWriter.escape("Grüße 🙂") == "Grüße 🙂")
  }

  @Test
  func serialDatesAndColumnNames() {
    #expect(XLSXWriter.serial(ofDay: "1900-03-01") == 61)
    #expect(XLSXWriter.serial(ofDay: "2026-10-05") == 46300)
    #expect(XLSXWriter.serial(ofDay: "05.10.2026") == nil)
    #expect([0, 25, 26, 51, 701, 702].map(XLSXWriter.columnName) == ["A", "Z", "AA", "AZ", "ZZ", "AAA"])
  }

  @Test
  func sheetsHaveTypedCellsFrozenHeaderAndAutofilter() throws {
    let data = XLSXWriter.workbook([
      XLSXWriter.Sheet(
        name: "Einträge",
        header: ["Datum", "Titel", "Stunden"],
        rows: [
          [.day("2026-10-05"), .text(" Review "), .number(1.5, .decimal)],
          [.day("kein Datum"), .text("Review"), .empty],
        ],
      ),
      XLSXWriter.Sheet(name: "Ein/träge", header: ["A"], rows: []),
    ])
    let files = try ZipReader.files(data)

    #expect(Set(files.keys) == [
      "[Content_Types].xml",
      "_rels/.rels",
      "xl/workbook.xml",
      "xl/_rels/workbook.xml.rels",
      "xl/styles.xml",
      "xl/worksheets/sheet1.xml",
      "xl/worksheets/sheet2.xml",
      "xl/sharedStrings.xml",
    ])
    let sheet = try #require(files["xl/worksheets/sheet1.xml"])
    #expect(sheet.contains(#"<dimension ref="A1:C3"/>"#))
    #expect(sheet.contains(#"<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>"#))
    #expect(sheet.contains(#"<autoFilter ref="A1:C3"/>"#))
    #expect(sheet.contains(#"<c r="A1" s="1" t="s"><v>0</v></c>"#)) // bold header
    #expect(sheet.contains(#"<c r="A2" s="2"><v>46300</v></c>"#)) // date
    #expect(sheet.contains(#"<c r="C2" s="3"><v>1.5</v></c>"#)) // 0.00
    #expect(sheet.contains(#"<c r="A3" t="s"><v>4</v></c>"#)) // not a date: text
    #expect(!sheet.contains(#"r="C3""#)) // empty cells are left out
    #expect(sheet.contains(#"<col min="2" max="2" width="#))

    let strings = try #require(files["xl/sharedStrings.xml"])
    #expect(strings.contains(#"count="7" uniqueCount="7""#))
    #expect(strings.contains(#"<si><t xml:space="preserve"> Review </t></si>"#))

    let workbook = try #require(files["xl/workbook.xml"])
    #expect(workbook.contains(#"<sheet name="Einträge" sheetId="1" r:id="rId1"/>"#))
    #expect(workbook.contains(#"<sheet name="Einträge 2" sheetId="2" r:id="rId2"/>"#))
    #expect(workbook.contains("&apos;Einträge&apos;!$A$1:$C$3"))
  }

  @Test
  func emptySheetStillOpens() throws {
    let files = try ZipReader.files(XLSXWriter.workbook([XLSXWriter.Sheet(name: "Leer", header: ["A", "B"], rows: [])]))
    let sheet = try #require(files["xl/worksheets/sheet1.xml"])
    #expect(sheet.contains(#"<dimension ref="A1:B1"/>"#))
    #expect(sheet.contains(#"<sheetData><row r="1">"#))
    #expect(files["xl/sharedStrings.xml"]?.contains(#"uniqueCount="2""#) == true)
  }

  @Test
  func exportHasEntriesAndTotalsPerProjectAndCategory() throws {
    let rows = [
      row(date: "2026-10-05", title: "=SUM(A1)", project: "Portal", category: "Meeting", hours: 1.5, rounded: 1.5),
      row(date: "2026-10-05", title: "Login", project: "Portal", category: "Development", hours: 2, rounded: 2),
      row(date: "2026-10-06", title: "Mail", project: nil, category: "Meeting", hours: 0.5, rounded: 0.75),
    ]
    let files = try ZipReader.files(Exporter.xlsx(rows))
    let entries = try #require(files["xl/worksheets/sheet1.xml"])
    let totals = try #require(files["xl/worksheets/sheet2.xml"])
    let strings = try #require(files["xl/sharedStrings.xml"])

    #expect(entries.contains(#"<autoFilter ref="A1:L4"/>"#))
    #expect(entries.contains(#"<c r="G2" s="4"><v>4821</v></c>"#)) // work item as a number
    #expect(entries.contains(#"<c r="K2" s="3"><v>1.5</v></c>"#))
    #expect(strings.contains("<t>=SUM(A1)</t>")) // a string cell, never a formula
    #expect(!entries.contains("<f>"))

    // Project: Portal 3.5 h, (none) 0.5 h; category: Development 2, Meeting 2 (by name); total.
    #expect(totals.contains(#"<autoFilter ref="A1:E6"/>"#))
    #expect(totals.contains(#"<c r="C2" s="3"><v>3.5</v></c><c r="D2" s="3"><v>3.5</v></c>"#))
    #expect(totals.contains(#"<c r="E2" s="5"><v>0.875</v></c>"#))
    #expect(totals.contains(#"<c r="D3" s="3"><v>0.75</v></c>"#))
    #expect(totals.contains(#"<c r="C6" s="3"><v>4</v></c><c r="D6" s="3"><v>4.25</v></c>"#))
    let values = strings.components(separatedBy: "<si><t>").dropFirst().map { $0.components(separatedBy: "</t>")[0] }
    for (row, name) in ["Portal", "(none)", "Development", "Meeting"].enumerated() {
      let index = try #require(values.firstIndex(of: name))
      #expect(totals.contains("<c r=\"B\(row + 2)\" t=\"s\"><v>\(index)</v></c>"))
    }
  }

  @Test
  func emptyPeriodGivesHeadersOnly() throws {
    let files = try ZipReader.files(Exporter.xlsx([]))
    #expect(files["xl/worksheets/sheet1.xml"]?.contains(#"<dimension ref="A1:L1"/>"#) == true)
    #expect(files["xl/worksheets/sheet2.xml"]?.contains(#"<c r="C2" s="3"><v>0</v></c>"#) == true)
  }

  // MARK: Private

  private func row(
    date: String,
    title: String,
    project: String?,
    category: String?,
    hours: Double,
    rounded: Double,
  ) -> Exporter.Row {
    Exporter.Row(
      date: date,
      title: title,
      project: project,
      task: nil,
      category: category,
      tags: [],
      workItem: 4821,
      note: nil,
      countingMode: "split",
      seconds: hours * 3600,
      hours: hours,
      roundedHours: rounded,
    )
  }
}

// MARK: - ZipReader

/// Reads a stored ZIP through its central directory, as the tests' independent check.
private enum ZipReader {
  struct Malformed: Error { }

  static func files(_ data: Data) throws -> [String: String] {
    let end = data.count - 22
    guard end >= 0, data.uint32(at: end) == 0x0605_4B50 else { throw Malformed() }
    var offset = Int(data.uint32(at: end + 16))
    var files = [String: String]()
    for _ in 0..<Int(data.uint16(at: end + 10)) {
      guard data.uint32(at: offset) == 0x0201_4B50 else { throw Malformed() }
      let size = Int(data.uint32(at: offset + 20))
      let nameLength = Int(data.uint16(at: offset + 28))
      let local = Int(data.uint32(at: offset + 42))
      let name = String(decoding: data.subdata(in: offset + 46..<offset + 46 + nameLength), as: UTF8.self)
      guard data.uint32(at: local) == 0x0403_4B50 else { throw Malformed() }
      let start = local + 30 + Int(data.uint16(at: local + 26)) + Int(data.uint16(at: local + 28))
      let content = data.subdata(in: start..<start + size)
      guard ZipArchive.crc32(content) == data.uint32(at: offset + 16) else { throw Malformed() }
      files[name] = String(decoding: content, as: UTF8.self)
      offset += 46 + nameLength
    }
    return files
  }
}

extension Data {
  fileprivate func uint16(at offset: Int) -> UInt16 {
    UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
  }

  fileprivate func uint32(at offset: Int) -> UInt32 {
    UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
  }
}
