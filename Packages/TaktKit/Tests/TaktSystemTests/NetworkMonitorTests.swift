import Testing

@testable import TaktSystem

struct NetworkMonitorTests {
  @Test
  func onlyChangesAfterTheFirstReportCount() {
    var reachability = Reachability()
    let reports = [true, true, false, false, true, true]
    let changes = reports.map { reachability.change(to: $0) }
    // The first report is the state at launch; a second usable path (Wi-Fi to Ethernet) is no change.
    #expect(changes == [nil, nil, false, nil, true, nil])
  }

  @Test
  func comingOnlineAfterAnOfflineLaunchCounts() {
    var reachability = Reachability()
    #expect(reachability.change(to: false) == nil)
    #expect(reachability.change(to: true) == true)
  }
}
