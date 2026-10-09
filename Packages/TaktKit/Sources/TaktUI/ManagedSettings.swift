import Foundation
import TaktADO

/// Every key a configuration profile (MDM) can set for `de.nilslutz.takt`; docs/MDM.md and
/// docs/mdm/Takt.mobileconfig list the same keys, a test keeps them in sync.
nonisolated public enum ManagedSettings {
  public enum ValueType: String, Sendable {
    case string
    case integer
    case real
    case boolean
    case array
  }

  public struct Key: Hashable, Sendable {
    public var name: String
    public var type: ValueType
    /// `false` for keys reserved for a later feature.
    public var isRead: Bool
  }

  public static let keys: [Key] = [
    Key(name: ADOAccounts.managedOrganizationKey, type: .string, isRead: true),
    Key(name: AppSettings.Key.startMode.rawValue, type: .string, isRead: true),
    Key(name: AppSettings.Key.countingMode.rawValue, type: .string, isRead: true),
    Key(name: AppSettings.Key.idleThresholdMinutes.rawValue, type: .integer, isRead: true),
    Key(name: AppSettings.Key.lockCountsAsPause.rawValue, type: .boolean, isRead: true),
    Key(name: AppSettings.Key.roundingMinutes.rawValue, type: .integer, isRead: true),
    Key(name: AppSettings.Key.bookingMode.rawValue, type: .string, isRead: true),
    Key(name: AppSettings.Key.reduceRemainingWork.rawValue, type: .boolean, isRead: true),
    Key(name: AppSettings.Key.bookingIncludesNote.rawValue, type: .boolean, isRead: true),
    Key(name: AppSettings.Key.dailyGoalHours.rawValue, type: .real, isRead: true),
    Key(name: AppSettings.Key.weeklyHours.rawValue, type: .real, isRead: true),
    Key(name: AppSettings.Key.workDays.rawValue, type: .array, isRead: true),
    Key(name: AppSettings.Key.showElapsedInMenuBar.rawValue, type: .boolean, isRead: true),
    Key(name: AppSettings.Key.gitFolders.rawValue, type: .array, isRead: true),
    Key(name: AppSettings.Key.onboardingCompleted.rawValue, type: .boolean, isRead: true),
    // Entra ID sign-in (#13) reads these once the app registration exists.
    Key(name: "entraClientID", type: .string, isRead: false),
    Key(name: "entraTenantID", type: .string, isRead: false),
  ]
}
