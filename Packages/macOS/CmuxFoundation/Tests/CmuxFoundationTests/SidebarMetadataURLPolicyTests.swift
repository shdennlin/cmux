import Foundation
import Testing

@testable import CmuxFoundation

@Suite struct SidebarMetadataURLPolicyTests {
    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test(arguments: ["https://example.com/pr/1", "http://localhost:3000"])
    func webDestinationsAreAlwaysAllowed(raw: String) throws {
        let policy = SidebarMetadataURLPolicy(appScheme: nil)
        #expect(policy.allows(try url(raw)))
    }

    /// The reason this type exists: a row may link back into cmux itself, so a
    /// workspace/surface deep link in this build's own scheme is admitted.
    @Test func theAppsOwnSchemeIsAllowed() throws {
        let policy = SidebarMetadataURLPolicy(appScheme: "cmux-dev-plus")
        #expect(policy.allows(try url("cmux-dev-plus://workspace/A/surface/B")))
    }

    /// Another build's scheme is not this build's, so it stays refused.
    @Test(arguments: ["cmux://workspace/A", "cmux-dev-dev://workspace/A"])
    func anotherBuildsSchemeIsRefused(raw: String) throws {
        let policy = SidebarMetadataURLPolicy(appScheme: "cmux-dev-plus")
        #expect(!policy.allows(try url(raw)))
    }

    /// Admitting any scheme would let a caller with control-socket access put a
    /// row in the sidebar that launches an unrelated app's URL handler.
    @Test(arguments: ["file:///etc/passwd", "ssh://host", "mailto:a@b.c", "javascript:alert(1)"])
    func unrelatedSchemesAreRefused(raw: String) throws {
        let policy = SidebarMetadataURLPolicy(appScheme: "cmux-dev-plus")
        #expect(!policy.allows(try url(raw)))
    }

    @Test func schemeComparisonIgnoresCase() throws {
        let policy = SidebarMetadataURLPolicy(appScheme: "CMUX-Dev-Plus")
        #expect(policy.allows(try url("cmux-dev-plus://workspace/A")))
    }

    /// A caller that cannot resolve the scheme gets the web-only contract
    /// rather than an accidental wildcard.
    @Test(arguments: [nil, "", "   "] as [String?])
    func anAbsentSchemeAdmitsWebOnly(appScheme: String?) throws {
        let policy = SidebarMetadataURLPolicy(appScheme: appScheme)
        #expect(policy.allows(try url("https://example.com")))
        #expect(!policy.allows(try url("cmux-dev-plus://workspace/A")))
    }

    @Test func theRejectionMessageNamesTheAppSchemeWhenThereIsOne() {
        let withScheme = SidebarMetadataURLPolicy(appScheme: "cmux-dev-plus")
        #expect(withScheme.rejectionMessage(rawURL: "ssh://h").contains("cmux-dev-plus://"))

        let webOnly = SidebarMetadataURLPolicy(appScheme: nil)
        #expect(webOnly.rejectionMessage(rawURL: "ssh://h").contains("expected http(s) URL"))
    }
}
