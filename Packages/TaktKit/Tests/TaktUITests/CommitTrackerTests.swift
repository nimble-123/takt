import Testing

@testable import TaktUI

struct CommitTrackerTests {
  @Test
  func valueLoadedWithoutFocusIsNotWrittenBack() {
    var tracker = CommitTracker("")
    // Tags arrive after the field appeared, the user never touches it.
    tracker.valueChanged(to: "x, y", focused: false)
    let commits = tracker.shouldCommit("x, y")
    #expect(!commits)
  }

  @Test
  func typedValueCommitsOnce() {
    var tracker = CommitTracker("x")
    tracker.valueChanged(to: "x, z", focused: true)
    let first = tracker.shouldCommit("x, z")
    let second = tracker.shouldCommit("x, z")
    #expect(first)
    #expect(!second)
  }

  @Test
  func unchangedValueDoesNotCommit() {
    var tracker = CommitTracker("x")
    let commits = tracker.shouldCommit("x")
    #expect(!commits)
  }
}
