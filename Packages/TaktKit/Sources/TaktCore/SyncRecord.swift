import Foundation

/// One booking to Azure DevOps: the difference sent for an entry on a local day (DO-24).
/// Completed Work in Azure DevOps is a single number; the history of bookings lives here.
public struct SyncRecord: Hashable, Sendable, Codable, Identifiable {
    public enum Status: String, Sendable, Codable {
        /// Created before sending; still pending after a crash or while offline.
        case pending
        case synced
        case failed
    }

    public var id: SyncRecordID
    public var entryID: EntryID
    public var workItemLinkID: WorkItemLinkID
    /// `YYYY-MM-DD`
    public var localDay: String
    /// Reference name of the booked field, e.g. `Microsoft.VSTS.Scheduling.CompletedWork`;
    /// `System.History` if the work item type has no time field.
    public var field: String
    /// Can be negative when an entry was shortened or deleted.
    public var deltaSeconds: Int
    public var status: Status
    public var adoRevision: Int?
    public var error: String?
    public var createdAt: Timestamp
    public var syncedAt: Timestamp?

    public init(
        id: SyncRecordID = SyncRecordID(),
        entryID: EntryID,
        workItemLinkID: WorkItemLinkID,
        localDay: String,
        field: String,
        deltaSeconds: Int,
        status: Status = .pending,
        adoRevision: Int? = nil,
        error: String? = nil,
        createdAt: Timestamp,
        syncedAt: Timestamp? = nil
    ) {
        self.id = id
        self.entryID = entryID
        self.workItemLinkID = workItemLinkID
        self.localDay = localDay
        self.field = field
        self.deltaSeconds = deltaSeconds
        self.status = status
        self.adoRevision = adoRevision
        self.error = error
        self.createdAt = createdAt
        self.syncedAt = syncedAt
    }

    /// `takt:<id>` in `System.History` finds the booking again after a crash.
    public var marker: String { "takt:\(id.uuidString.lowercased())" }
}
