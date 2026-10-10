import Testing

@testable import TaktCore

/// Search hits ordered by state: in progress, testing, new, done; removed ones left out.
struct WorkItemStateTests {

  @Test
  func statesOfTheProcessesFallIntoGroups() {
    #expect(WorkItemStateGroup(state: "Active") == .inProgress)
    #expect(WorkItemStateGroup(state: "In Progress") == .inProgress)
    #expect(WorkItemStateGroup(state: "Committed") == .inProgress)
    #expect(WorkItemStateGroup(state: "Doing") == .inProgress)
    #expect(WorkItemStateGroup(state: "Testing") == .testing)
    #expect(WorkItemStateGroup(state: "Ready for Test") == .testing)
    #expect(WorkItemStateGroup(state: "New") == .proposed)
    #expect(WorkItemStateGroup(state: "To Do") == .proposed)
    #expect(WorkItemStateGroup(state: "Approved") == .proposed)
    #expect(WorkItemStateGroup(state: "Done") == .completed)
    #expect(WorkItemStateGroup(state: "Closed") == .completed)
    #expect(WorkItemStateGroup(state: "Resolved") == .completed)
    #expect(WorkItemStateGroup(state: "Removed") == .removed)
    #expect(WorkItemStateGroup(state: "Cancelled") == .removed)
    #expect(WorkItemStateGroup(state: "Release") == .other)
    #expect(WorkItemStateGroup(state: nil) == .other)
  }

  @Test
  func groupsSortInProgressFirstAndDoneLast() {
    let sorted = ["Done", "New", "Testing", "Active", "Release"].map { WorkItemStateGroup(state: $0) }.sorted()
    #expect(sorted == [.inProgress, .testing, .proposed, .other, .completed])
  }
}
