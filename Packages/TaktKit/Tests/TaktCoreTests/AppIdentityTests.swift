import Testing

@testable import TaktCore

struct AppIdentityTests {
    @Test func logSubsystemMatchesBundleIdentifier() {
        #expect(AppIdentity.logSubsystem == "de.nilslutz.takt")
        #expect(AppIdentity.bundleIdentifier == AppIdentity.logSubsystem)
    }
}
