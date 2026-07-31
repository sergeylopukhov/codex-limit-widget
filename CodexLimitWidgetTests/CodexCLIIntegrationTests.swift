import XCTest
@testable import Codex_Limit_Widget

final class CodexCLIIntegrationTests: XCTestCase {
    func testAuthenticationErrorsAreRecognized() {
        XCTAssertTrue(
            CodexRateLimitError.isAuthenticationError(
                code: nil,
                message: "codex account authentication required to read rate limits"
            )
        )
        XCTAssertTrue(CodexRateLimitError.isAuthenticationError(code: 401, message: "request failed"))
        XCTAssertFalse(CodexRateLimitError.isAuthenticationError(code: 500, message: "server unavailable"))
    }

    func testCLIEnvironmentIncludesUserLocalBin() {
        let environment = CodexCLI.makeEnvironment()
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin")
            .path
        let paths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        XCTAssertTrue(paths.contains(localBin))
        XCTAssertEqual(paths.filter { $0 == localBin }.count, 1)
    }

    func testOfficialInstallerUsesChatGPTHost() {
        XCTAssertEqual(CodexCLIInstaller.scriptURL.scheme, "https")
        XCTAssertEqual(CodexCLIInstaller.scriptURL.host, "chatgpt.com")
        XCTAssertEqual(CodexCLIInstaller.scriptURL.path, "/codex/install.sh")
        XCTAssertEqual(
            CodexCLIInstaller.manualInstallCommand,
            "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
        )
    }

    func testCommandResultSuccessState() {
        let result = CodexCLICommandResult(
            terminationStatus: 0,
            standardOutput: "Logged in using ChatGPT",
            standardError: ""
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.combinedOutput, "Logged in using ChatGPT")
    }


    func testLoginItemPolicyAcceptsOnlyCanonicalReleaseCopy() {
        XCTAssertTrue(
            LoginItemRegistrationPolicy.shouldRegister(
                bundleIdentifier: LoginItemRegistrationPolicy.canonicalBundleIdentifier,
                bundleURL: URL(fileURLWithPath: LoginItemRegistrationPolicy.canonicalApplicationPath),
                isDebugBuild: false
            )
        )
        XCTAssertFalse(
            LoginItemRegistrationPolicy.shouldRegister(
                bundleIdentifier: LoginItemRegistrationPolicy.canonicalBundleIdentifier,
                bundleURL: URL(fileURLWithPath: "/tmp/Codex Limit Widget.app"),
                isDebugBuild: false
            )
        )
    }

    func testLoginItemPolicyRejectsDebugBuildsAndWrongBundleIDs() {
        XCTAssertFalse(
            LoginItemRegistrationPolicy.shouldRegister(
                bundleIdentifier: LoginItemRegistrationPolicy.canonicalBundleIdentifier,
                bundleURL: URL(fileURLWithPath: LoginItemRegistrationPolicy.canonicalApplicationPath),
                isDebugBuild: true
            )
        )
        XCTAssertFalse(
            LoginItemRegistrationPolicy.shouldRegister(
                bundleIdentifier: "$(PRODUCT_BUNDLE_IDENTIFIER)",
                bundleURL: URL(fileURLWithPath: LoginItemRegistrationPolicy.canonicalApplicationPath),
                isDebugBuild: false
            )
        )
    }

    func testReleaseNotesShowWhenNoPreviousVersionWasRecorded() {
        XCTAssertTrue(
            ReleaseNotesPresentationPolicy.shouldShow(
                currentVersionIdentifier: "1.2.253 (147)",
                lastShownVersionIdentifier: nil
            )
        )
    }

    func testReleaseNotesShowAfterOlderBuildAndSkipSameBuild() {
        XCTAssertTrue(
            ReleaseNotesPresentationPolicy.shouldShow(
                currentVersionIdentifier: "1.2.253 (147)",
                lastShownVersionIdentifier: "1.2.251 (146)"
            )
        )
        XCTAssertTrue(
            ReleaseNotesPresentationPolicy.shouldShow(
                currentVersionIdentifier: "1.2.253 (147)",
                lastShownVersionIdentifier: "1.2.251 (145)"
            )
        )
        XCTAssertFalse(
            ReleaseNotesPresentationPolicy.shouldShow(
                currentVersionIdentifier: "1.2.253 (147)",
                lastShownVersionIdentifier: "1.2.253 (147)"
            )
        )
    }
}
