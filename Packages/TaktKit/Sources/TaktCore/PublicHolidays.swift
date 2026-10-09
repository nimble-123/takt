import Foundation

// MARK: - FederalState

/// A German federal state, by its ISO 3166-2 code (AZ-03).
public enum FederalState: String, CaseIterable, Sendable {
  case badenWuerttemberg = "BW"
  case bavaria = "BY"
  case berlin = "BE"
  case brandenburg = "BB"
  case bremen = "HB"
  case hamburg = "HH"
  case hesse = "HE"
  case mecklenburgWesternPomerania = "MV"
  case lowerSaxony = "NI"
  case northRhineWestphalia = "NW"
  case rhinelandPalatinate = "RP"
  case saarland = "SL"
  case saxony = "SN"
  case saxonyAnhalt = "ST"
  case schleswigHolstein = "SH"
  case thuringia = "TH"
}

// MARK: - PublicHoliday

/// Statutory public holidays that apply to a whole federal state (AZ-03). Holidays of single
/// municipalities, e.g. Assumption Day in parts of Bavaria, are left out.
public enum PublicHoliday: String, CaseIterable, Sendable {
  case newYear
  case epiphany
  case womensDay
  case goodFriday
  case easterSunday
  case easterMonday
  case labourDay
  case ascension
  case whitSunday
  case whitMonday
  case corpusChristi
  case assumption
  case childrensDay
  case germanUnity
  case reformation
  case allSaints
  case repentance
  case christmasDay
  case boxingDay

  // MARK: Public

  /// A calendar date without time or time zone.
  public struct Day: Hashable, Sendable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public static func <(lhs: Day, rhs: Day) -> Bool {
      (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
  }

  /// The holidays of `state` in `year`, in date order.
  public static func all(in year: Int, state: FederalState) -> [(date: Day, holiday: PublicHoliday)] {
    allCases
      .filter { $0.applies(in: state, year: year) }
      .map { (date: $0.date(in: year), holiday: $0) }
      .sorted { $0.date < $1.date }
  }

  /// The holiday on the local day of `timestamp`, if any.
  public static func on(_ timestamp: Timestamp, state: FederalState, calendar: Calendar) -> PublicHoliday? {
    let parts = calendar.dateComponents([.year, .month, .day], from: timestamp.date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    let date = Day(year: year, month: month, day: day)
    return all(in: year, state: state).first { $0.date == date }?.holiday
  }

  /// Easter Sunday in the Gregorian calendar (anonymous Gregorian algorithm, after Gauss).
  public static func easterSunday(in year: Int) -> Day {
    let a = year % 19
    let b = year / 100
    let c = year % 100
    let d = b / 4
    let e = b % 4
    let f = (b + 8) / 25
    let g = (b - f + 1) / 3
    let h = (19 * a + b - d - g + 15) % 30
    let i = c / 4
    let k = c % 4
    let l = (32 + 2 * e + 2 * i - h - k) % 7
    let m = (a + 11 * h + 22 * l) / 451
    let month = (h + l - 7 * m + 114) / 31
    let day = (h + l - 7 * m + 114) % 31 + 1
    return Day(year: year, month: month, day: day)
  }

  public func date(in year: Int) -> Day {
    switch self {
    case .newYear: Day(year: year, month: 1, day: 1)
    case .epiphany: Day(year: year, month: 1, day: 6)
    case .womensDay: Day(year: year, month: 3, day: 8)
    case .goodFriday: Self.easter(in: year, plus: -2)
    case .easterSunday: Self.easterSunday(in: year)
    case .easterMonday: Self.easter(in: year, plus: 1)
    case .labourDay: Day(year: year, month: 5, day: 1)
    case .ascension: Self.easter(in: year, plus: 39)
    case .whitSunday: Self.easter(in: year, plus: 49)
    case .whitMonday: Self.easter(in: year, plus: 50)
    case .corpusChristi: Self.easter(in: year, plus: 60)
    case .assumption: Day(year: year, month: 8, day: 15)
    case .childrensDay: Day(year: year, month: 9, day: 20)
    case .germanUnity: Day(year: year, month: 10, day: 3)
    case .reformation: Day(year: year, month: 10, day: 31)
    case .allSaints: Day(year: year, month: 11, day: 1)
    // The Wednesday before 23 November: 16–22 November.
    case .repentance: Day(year: year, month: 11, day: 22 - (Self.weekday(year, 11, 22) + 5) % 7)
    case .christmasDay: Day(year: year, month: 12, day: 25)
    case .boxingDay: Day(year: year, month: 12, day: 26)
    }
  }

  public func applies(in state: FederalState, year: Int) -> Bool {
    switch self {
    case .epiphany: [.badenWuerttemberg, .bavaria, .saxonyAnhalt].contains(state)

    // Berlin since 2019, Mecklenburg-Western Pomerania since 2023.
    case .womensDay: (state == .berlin && year >= 2019) || (state == .mecklenburgWesternPomerania && year >= 2023)

    case .easterSunday, .whitSunday: state == .brandenburg

    case .corpusChristi:
      [.badenWuerttemberg, .bavaria, .hesse, .northRhineWestphalia, .rhinelandPalatinate, .saarland].contains(state)

    case .assumption: state == .saarland

    case .childrensDay: state == .thuringia && year >= 2019

    // Everywhere in 2017 (500 years); since 2018 also in the northern states.
    case .reformation:
      year == 2017 || [.brandenburg, .mecklenburgWesternPomerania, .saxony, .saxonyAnhalt, .thuringia].contains(state)
        || (year >= 2018 && [.bremen, .hamburg, .lowerSaxony, .schleswigHolstein].contains(state))

    case .allSaints:
      [.badenWuerttemberg, .bavaria, .northRhineWestphalia, .rhinelandPalatinate, .saarland].contains(state)

    case .repentance: state == .saxony

    default: true
    }
  }

  // MARK: Private

  private static let gregorian: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
    return calendar
  }()

  private static func easter(in year: Int, plus days: Int) -> Day {
    let easter = easterSunday(in: year)
    let components = DateComponents(year: year, month: easter.month, day: easter.day + days)
    guard let date = gregorian.date(from: components) else { return easter }
    let parts = gregorian.dateComponents([.year, .month, .day], from: date)
    return Day(year: parts.year ?? year, month: parts.month ?? easter.month, day: parts.day ?? easter.day)
  }

  /// 0 = Monday … 6 = Sunday.
  private static func weekday(_ year: Int, _ month: Int, _ day: Int) -> Int {
    guard let date = gregorian.date(from: DateComponents(year: year, month: month, day: day)) else { return 0 }
    return (gregorian.component(.weekday, from: date) + 5) % 7
  }
}
