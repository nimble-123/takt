import Testing

@testable import TaktCore

struct BranchNameTests {
  @Test(arguments: [
    ("feature/1234-login", 1234),
    ("bugfix/AB#1234", 1234),
    ("users/nils/1234", 1234),
    ("1234_token-refresh", 1234),
    ("feature/login-#77", 77),
    ("hotfix/ab#9-crash", 9),
    ("feature/2026-login", 2026),
    ("2026-10-09/1234-login", 1234),
  ])
  func recognizesWorkItems(branch: String, id: Int) {
    #expect(BranchName.workItemID(in: branch) == id)
  }

  @Test(arguments: [
    "main",
    "release/2.3.1",
    "feature/login",
    "feature/v2-login",
    "hotfix/7",
    "feature/oauth2-login",
    "hotfix/2026-10-09",
    "release/2026-10",
    "hotfix/2026_10_09",
  ])
  func ignoresOtherBranches(branch: String) {
    #expect(BranchName.workItemID(in: branch) == nil)
  }
}
