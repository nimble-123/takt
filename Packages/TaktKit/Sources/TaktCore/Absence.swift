import Foundation

/// Why a working day has no target (AZ-05). Only these three on purpose: taking time off from the
/// flex account needs no marker, a day with less work uses it up anyway.
public enum AbsenceKind: String, CaseIterable, Sendable {
  case vacation
  case sick
  /// Other paid leave, e.g. special leave or vocational school.
  case off
}
