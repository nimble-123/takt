import Foundation
import TaktCore

// MARK: - PublicHoliday + name

extension PublicHoliday {
  /// Short name for the day headers (AZ-03).
  nonisolated var name: String {
    switch self {
    case .newYear: String(localized: "New Year's Day", bundle: .module)
    case .epiphany: String(localized: "Epiphany", bundle: .module)
    case .womensDay: String(localized: "Women's Day", bundle: .module)
    case .goodFriday: String(localized: "Good Friday", bundle: .module)
    case .easterSunday: String(localized: "Easter Sunday", bundle: .module)
    case .easterMonday: String(localized: "Easter Monday", bundle: .module)
    case .labourDay: String(localized: "Labour Day", bundle: .module)
    case .ascension: String(localized: "Ascension Day", bundle: .module)
    case .whitSunday: String(localized: "Whit Sunday", bundle: .module)
    case .whitMonday: String(localized: "Whit Monday", bundle: .module)
    case .corpusChristi: String(localized: "Corpus Christi", bundle: .module)
    case .assumption: String(localized: "Assumption Day", bundle: .module)
    case .childrensDay: String(localized: "Children's Day", bundle: .module)
    case .germanUnity: String(localized: "German Unity Day", bundle: .module)
    case .reformation: String(localized: "Reformation Day", bundle: .module)
    case .allSaints: String(localized: "All Saints' Day", bundle: .module)
    case .repentance: String(localized: "Day of Repentance", bundle: .module)
    case .christmasDay: String(localized: "Christmas Day", bundle: .module)
    case .boxingDay: String(localized: "Boxing Day", bundle: .module)
    }
  }
}

// MARK: - FederalState + name

extension FederalState {
  nonisolated var name: String {
    switch self {
    case .badenWuerttemberg: String(localized: "Baden-Württemberg", bundle: .module)
    case .bavaria: String(localized: "Bavaria", bundle: .module)
    case .berlin: String(localized: "Berlin", bundle: .module)
    case .brandenburg: String(localized: "Brandenburg", bundle: .module)
    case .bremen: String(localized: "Bremen", bundle: .module)
    case .hamburg: String(localized: "Hamburg", bundle: .module)
    case .hesse: String(localized: "Hesse", bundle: .module)
    case .mecklenburgWesternPomerania: String(localized: "Mecklenburg-Western Pomerania", bundle: .module)
    case .lowerSaxony: String(localized: "Lower Saxony", bundle: .module)
    case .northRhineWestphalia: String(localized: "North Rhine-Westphalia", bundle: .module)
    case .rhinelandPalatinate: String(localized: "Rhineland-Palatinate", bundle: .module)
    case .saarland: String(localized: "Saarland", bundle: .module)
    case .saxony: String(localized: "Saxony", bundle: .module)
    case .saxonyAnhalt: String(localized: "Saxony-Anhalt", bundle: .module)
    case .schleswigHolstein: String(localized: "Schleswig-Holstein", bundle: .module)
    case .thuringia: String(localized: "Thuringia", bundle: .module)
    }
  }
}
