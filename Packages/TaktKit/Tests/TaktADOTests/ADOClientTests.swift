import Foundation
import Testing

@testable import TaktADO

struct ADOClientTests {
    let stub = Stub()

    private func client(token: String = "secret") -> ADOClient {
        ADOClient(organization: "contoso", authorization: PATAuthorization(token: token), session: stub.session)
    }

    @Test func patIsSentAsBasicAuthWithEmptyUser() async throws {
        let header = try await PATAuthorization(token: "abc").authorizationHeader()
        #expect(header == "Basic " + Data(":abc".utf8).base64EncodedString())
    }

    @Test func verifyReturnsTheUserAndSendsVersionAndAuth() async throws {
        stub.respond { _ in Stub.Response(status: 200, body: Stub.fixture("connectionData")) }

        let identity = try await client().verify()

        #expect(identity.displayName == "Nils Lutz")
        let request = try #require(stub.requests.first)
        #expect(request.url?.absoluteString == "https://dev.azure.com/contoso/_apis/connectionData?api-version=7.1")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    }

    @Test func anonymousIdentityMeansTheTokenWasNotAccepted() async throws {
        stub.respond { _ in Stub.Response(status: 200, body: Stub.fixture("connectionData-anonymous")) }
        await #expect(throws: ADOError.unauthorized) { try await client().verify() }
    }

    @Test(arguments: [401, 403])
    func rejectedTokenIsUnauthorized(status: Int) async throws {
        stub.respond { _ in Stub.Response(status: status, body: Data()) }
        await #expect(throws: ADOError.unauthorized) { try await client().verify() }
    }

    @Test func noNetworkIsOffline() async throws {
        stub.respond { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: ADOError.offline) { try await client().verify() }
    }

    @Test func throttlingReportsRetryAfter() async throws {
        stub.respond { _ in Stub.Response(status: 429, body: Data(), headers: ["Retry-After": "30"]) }
        await #expect(throws: ADOError.throttled(retryAfter: 30)) { try await client().verify() }
    }

    @Test func projectsAreSortedByName() async throws {
        stub.respond { _ in Stub.Response(status: 200, body: Stub.fixture("projects")) }
        let projects = try await client().projects()
        #expect(projects.map(\.name) == ["Backoffice", "Kundenportal"])
    }

    @Test func areaPathsAreFlattened() async throws {
        stub.respond { request in
            #expect(request.url?.path() == "/contoso/Kundenportal/_apis/wit/classificationnodes/areas")
            return Stub.Response(status: 200, body: Stub.fixture("areas"))
        }
        let paths = try await client().areaPaths(of: "Kundenportal")
        #expect(
            paths == [
                "Kundenportal", "Kundenportal\\Team Login", "Kundenportal\\Team Billing",
                "Kundenportal\\Team Billing\\Rechnungen",
            ]
        )
    }
}

struct ADOAccountsTests {
    let stub = Stub()
    let secrets = MemorySecrets()
    let suite = "takt-ado-\(UUID().uuidString)"

    private var accounts: ADOAccounts {
        ADOAccounts(secrets: secrets, suiteName: suite, session: stub.session)
    }

    @Test func connectVerifiesThenStoresTokenAndConnection() async throws {
        stub.respond { _ in Stub.Response(status: 200, body: Stub.fixture("connectionData")) }
        let expires = Date(timeIntervalSince1970: 1_800_000_000)

        let connection = try await accounts.connect(
            organization: "https://dev.azure.com/contoso/", token: " secret \n", expires: expires
        )

        #expect(connection.organization == "contoso")
        #expect(connection.userName == "Nils Lutz")
        #expect(try secrets.read("contoso") == "secret")
        #expect(accounts.connections == [connection])
        #expect(try accounts.client(for: "contoso") != nil)
    }

    @Test func failedVerificationStoresNothing() async throws {
        stub.respond { _ in Stub.Response(status: 401, body: Data()) }
        await #expect(throws: ADOError.unauthorized) {
            try await accounts.connect(organization: "contoso", token: "wrong", expires: nil)
        }
        #expect(accounts.connections.isEmpty)
        #expect(try secrets.read("contoso") == nil)
    }

    @Test func removeDeletesTokenAndConnection() async throws {
        stub.respond { _ in Stub.Response(status: 200, body: Stub.fixture("connectionData")) }
        try await accounts.connect(organization: "contoso", token: "secret", expires: nil)
        try accounts.remove("contoso")
        #expect(accounts.connections.isEmpty)
        #expect(try accounts.client(for: "contoso") == nil)
    }

    @Test(arguments: [
        ("contoso", "contoso"), ("https://dev.azure.com/contoso/", "contoso"),
        ("dev.azure.com/contoso/Portal", "contoso"), ("https://contoso.visualstudio.com", "contoso"),
    ])
    func organizationInputIsNormalized(input: String, expected: String) {
        #expect(ADOAccounts.normalized(input) == expected)
    }

    @Test func expiryReminderStartsFourteenDaysBefore() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = ADOConnection(organization: "a", userName: "u", tokenExpires: now.addingTimeInterval(13 * 86_400))
        let later = ADOConnection(organization: "a", userName: "u", tokenExpires: now.addingTimeInterval(20 * 86_400))
        #expect(soon.tokenExpiresSoon(at: now))
        #expect(!later.tokenExpiresSoon(at: now))
    }
}
