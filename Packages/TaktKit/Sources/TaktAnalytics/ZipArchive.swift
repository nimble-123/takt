import Foundation

// MARK: - ZipArchive

/// A ZIP archive without compression (method 0, "stored"), as the container of an XLSX file
/// (AN-08). Enough for a few small XML parts; no ZIP64, no encryption. All entries carry the same
/// fixed timestamp, so the same input gives the same bytes.
struct ZipArchive {

  // MARK: Internal

  struct Entry {
    var path: String
    var data: Data
  }

  var entries = [Entry]()

  /// CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320) as ZIP and PNG use it.
  static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }

  mutating func add(_ path: String, _ data: Data) {
    entries.append(Entry(path: path, data: data))
  }

  mutating func add(_ path: String, _ text: String) {
    add(path, Data(text.utf8))
  }

  func data() -> Data {
    var output = Data()
    var central = Data()
    for entry in entries {
      let name = Data(entry.path.utf8)
      let crc = Self.crc32(entry.data)
      let size = UInt32(entry.data.count)
      let offset = UInt32(output.count)

      output.append(le32: 0x0403_4B50) // local file header
      output.append(le16: 20) // version needed: 2.0
      output.append(le16: Self.utf8Flag)
      output.append(le16: 0) // stored
      output.append(le16: Self.dosTime)
      output.append(le16: Self.dosDate)
      output.append(le32: crc)
      output.append(le32: size) // compressed
      output.append(le32: size) // uncompressed
      output.append(le16: UInt16(name.count))
      output.append(le16: 0) // extra field
      output.append(name)
      output.append(entry.data)

      central.append(le32: 0x0201_4B50) // central directory header
      central.append(le16: 20) // made by: 2.0, MS-DOS
      central.append(le16: 20)
      central.append(le16: Self.utf8Flag)
      central.append(le16: 0)
      central.append(le16: Self.dosTime)
      central.append(le16: Self.dosDate)
      central.append(le32: crc)
      central.append(le32: size)
      central.append(le32: size)
      central.append(le16: UInt16(name.count))
      central.append(le16: 0) // extra field
      central.append(le16: 0) // comment
      central.append(le16: 0) // disk number
      central.append(le16: 0) // internal attributes
      central.append(le32: 0) // external attributes
      central.append(le32: offset)
      central.append(name)
    }
    let centralOffset = UInt32(output.count)
    output.append(central)
    output.append(le32: 0x0605_4B50) // end of central directory
    output.append(le16: 0) // this disk
    output.append(le16: 0) // disk with the central directory
    output.append(le16: UInt16(entries.count))
    output.append(le16: UInt16(entries.count))
    output.append(le32: UInt32(central.count))
    output.append(le32: centralOffset)
    output.append(le16: 0) // comment
    return output
  }

  // MARK: Private

  /// Bit 11: names are UTF-8.
  private static let utf8Flag: UInt16 = 0x0800
  /// 1980-01-01 00:00, the earliest DOS date.
  private static let dosTime: UInt16 = 0
  private static let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1

  private static let crcTable: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 {
      value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
    return value
  }
}

extension Data {
  fileprivate mutating func append(le16 value: UInt16) {
    append(UInt8(value & 0xFF))
    append(UInt8(value >> 8))
  }

  fileprivate mutating func append(le32 value: UInt32) {
    append(le16: UInt16(value & 0xFFFF))
    append(le16: UInt16(value >> 16))
  }
}
