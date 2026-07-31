import AppKit
import Combine
import CryptoKit
import Foundation
import UserNotifications

struct AppUpdateRelease: Equatable, Sendable {
    let version: String
    let pageURL: URL
    let assetURL: URL
    let assetName: String
    let sha256: String?
}

@MainActor
final class AppUpdateController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case installing
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var availableRelease: AppUpdateRelease?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCheckedAt: Date?

    private nonisolated static let releasesURL = URL(string: "https://api.github.com/repos/sergeylopukhov/codex-limit-widget/releases/latest")!
    private static let updateNotificationVersionKey = "lastNotifiedUpdateVersion"
    private var timer: Timer?
    private var started = false
    private var activeCheckID: UUID?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--"
    }

    var isUpdateAvailable: Bool {
        availableRelease != nil
    }

    var isBusy: Bool {
        phase == .downloading || phase == .installing || (phase == .checking && availableRelease == nil)
    }

    var menuActionTitle: String {
        switch phase {
        case .downloading:
            return "Downloading"
        case .installing:
            return "Installing"
        default:
            return "Update"
        }
    }

    var menuStatusText: String? {
        guard let release = availableRelease else { return nil }
        switch phase {
        case .downloading:
            return Self.localized("Downloading v%@…", release.version)
        case .installing:
            return Self.localized("Installing v%@…", release.version)
        default:
            return Self.localized("Version %@ available", release.version)
        }
    }

    var settingsStatusText: String {
        if let release = availableRelease {
            switch phase {
            case .downloading:
                return Self.localized("Downloading version %@…", release.version)
            case .installing:
                return Self.localized("Installing version %@…", release.version)
            case .failed:
                return Self.localized("Version %@ is still available.", release.version)
            default:
                return Self.localized("Version %@ is available.", release.version)
            }
        }

        switch phase {
        case .checking:
            return NSLocalizedString("Checking GitHub Releases…", comment: "Update status")
        case .upToDate:
            return NSLocalizedString("You have the latest version.", comment: "Update status")
        case .failed:
            return NSLocalizedString("Could not check for updates.", comment: "Update status")
        default:
            return NSLocalizedString("Updates are checked automatically.", comment: "Update status")
        }
    }

    func start() {
        guard !started else { return }
        started = true

        Task { await checkForUpdates() }
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForUpdates()
            }
        }
    }

    func checkForUpdates() async {
        guard phase != .downloading, phase != .installing, phase != .checking else { return }

        let checkID = UUID()
        activeCheckID = checkID
        phase = .checking
        errorMessage = nil

        do {
            let release = try await Self.fetchLatestReleaseWithTimeout(currentVersion: currentVersion)
            guard activeCheckID == checkID else { return }

            activeCheckID = nil
            lastCheckedAt = Date()

            if Self.isVersion(release.version, newerThan: currentVersion) {
                availableRelease = release
                phase = .available
                notifyAboutAvailableUpdate(release)
            } else {
                availableRelease = nil
                phase = .upToDate
            }
        } catch is CancellationError {
            guard activeCheckID == checkID else { return }
            activeCheckID = nil
            phase = availableRelease == nil ? .idle : .available
        } catch {
            guard activeCheckID == checkID else { return }

            activeCheckID = nil
            phase = .failed
            errorMessage = Self.message(for: error)
        }
    }

    func installAvailableUpdate() async {
        guard let release = availableRelease, phase != .downloading, phase != .installing else { return }

        phase = .downloading
        errorMessage = nil

        do {
            let prepared = try await Self.downloadAndPrepareUpdate(for: release)
            phase = .installing

            try launchInstaller(for: prepared)
        } catch {
            phase = .failed
            errorMessage = Self.message(for: error)
        }
    }

    func openReleasePage() {
        guard let pageURL = availableRelease?.pageURL else { return }
        NSWorkspace.shared.open(pageURL)
    }

    private func notifyAboutAvailableUpdate(_ release: AppUpdateRelease) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.updateNotificationVersionKey) != release.version else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let authorized: Bool

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                authorized = true
            case .notDetermined:
                authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            default:
                authorized = false
            }

            guard authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Codex Limit Widget", comment: "Update notification title")
            content.body = String(
                format: NSLocalizedString("New version %@ is available.", comment: "Update notification body"),
                release.version
            )
            content.sound = .default
            content.userInfo = ["codexLimitWidgetAction": "openUpdates"]

            let request = UNNotificationRequest(
                identifier: "codex-limit-widget.update.\(release.version)",
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                defaults.set(release.version, forKey: Self.updateNotificationVersionKey)
            } catch {
                return
            }
        }
    }

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = numericVersionParts(candidate)
        let currentParts = numericVersionParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }

        return false
    }

    private nonisolated static func fetchLatestReleaseWithTimeout(currentVersion: String) async throws -> AppUpdateRelease {
        try await withThrowingTaskGroup(of: AppUpdateRelease.self) { group in
            group.addTask {
                try await Self.fetchLatestRelease(currentVersion: currentVersion)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                throw AppUpdateError.updateCheckTimedOut
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw AppUpdateError.updateCheckTimedOut
            }
            return result
        }
    }

    private nonisolated static func fetchLatestRelease(currentVersion: String) async throws -> AppUpdateRelease {
        var request = URLRequest(url: releasesURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexLimitWidget/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response)

        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        let version = payload.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard
            !version.isEmpty,
            let pageURL = URL(string: payload.htmlURL),
            let asset = payload.assets.first(where: {
                $0.name.hasPrefix("CodexLimitWidget-") && $0.name.hasSuffix("-macOS.zip")
            }),
            let assetURL = URL(string: asset.downloadURL)
        else {
            throw AppUpdateError.missingReleaseAsset
        }

        return AppUpdateRelease(
            version: version,
            pageURL: pageURL,
            assetURL: assetURL,
            assetName: asset.name,
            sha256: asset.digest?.replacingOccurrences(of: "sha256:", with: "", options: [.caseInsensitive])
        )
    }

    private nonisolated static func downloadAndPrepareUpdate(for release: AppUpdateRelease) async throws -> PreparedUpdate {
        var candidateURLs = [release.assetURL]
        if let cacheBustedURL = cacheBustedURL(for: release.assetURL) {
            candidateURLs.append(cacheBustedURL)
        }

        for (index, candidateURL) in candidateURLs.enumerated() {
            do {
                var request = URLRequest(url: candidateURL)
                request.timeoutInterval = 120
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (downloadURL, response) = try await URLSession.shared.download(for: request)
                try validateHTTPResponse(response)

                return try await Task.detached(priority: .userInitiated) {
                    try Self.prepareUpdate(downloadURL: downloadURL, release: release)
                }.value
            } catch {
                guard let updateError = error as? AppUpdateError,
                      updateError == .checksumMismatch,
                      index < candidateURLs.count - 1
                else {
                    throw error
                }
            }
        }

        throw AppUpdateError.checksumMismatch
    }

    private nonisolated static func cacheBustedURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "codex_update", value: UUID().uuidString))
        components.queryItems = queryItems
        return components.url
    }

    private func launchInstaller(for prepared: PreparedUpdate) throws {
        let destination = Self.installDestination
        let destinationParent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: destinationParent.path) else {
            throw AppUpdateError.applicationsFolderNotWritable
        }

        let staging = destinationParent.appendingPathComponent(
            ".Codex Limit Widget.update-\(UUID().uuidString).app",
            isDirectory: true
        )
        let helperScript = #"""
        /usr/bin/ditto "$2" "$4" || exit 20
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        if [ -d "$3/Contents/PlugIns/CodexLimitWidgetExtension.appex" ]; then
          /usr/bin/pluginkit -r "$3/Contents/PlugIns/CodexLimitWidgetExtension.appex" 2>/dev/null || true
        fi
        /bin/rm -rf "$3"
        /bin/mv "$4" "$3" || exit 21
        /usr/bin/xattr -dr com.apple.quarantine "$3" 2>/dev/null || true
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$3" 2>/dev/null || true
        if [ -d "$3/Contents/PlugIns/CodexLimitWidgetExtension.appex" ]; then
          /usr/bin/pluginkit -a "$3/Contents/PlugIns/CodexLimitWidgetExtension.appex" 2>/dev/null || true
        fi
        /usr/bin/open "$3"
        /bin/rm -rf "$5"
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            helperScript,
            "codex-limit-updater",
            String(ProcessInfo.processInfo.processIdentifier),
            prepared.appURL.path,
            destination.path,
            staging.path,
            prepared.temporaryDirectory.path
        ]
        try process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.terminate(nil)
        }
    }

    private nonisolated static func prepareUpdate(
        downloadURL: URL,
        release: AppUpdateRelease
    ) throws -> PreparedUpdate {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "CodexLimitWidgetUpdate-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let archiveURL = temporaryDirectory.appendingPathComponent(release.assetName)
            try fileManager.copyItem(at: downloadURL, to: archiveURL)

            if let expectedSHA256 = release.sha256 {
                let data = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
                let actualSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard actualSHA256.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                    throw AppUpdateError.checksumMismatch
                }
            }

            let extractionDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
            try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
            try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path])

            guard let appURL = findApp(in: extractionDirectory) else {
                throw AppUpdateError.missingAppBundle
            }

            guard
                let bundle = Bundle(url: appURL),
                bundle.bundleIdentifier == "com.sergeylopukhov.CodexLimitWidget",
                let bundleVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                !isVersion(release.version, newerThan: bundleVersion),
                !isVersion(bundleVersion, newerThan: release.version)
            else {
                throw AppUpdateError.invalidAppBundle
            }

            try runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
            return PreparedUpdate(appURL: appURL, temporaryDirectory: temporaryDirectory)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private nonisolated static func findApp(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        for case let candidate as URL in enumerator where candidate.lastPathComponent == "Codex Limit Widget.app" {
            return candidate
        }
        return nil
    }

    private nonisolated static func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.commandFailed
        }
    }

    private nonisolated static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw AppUpdateError.invalidServerResponse
        }
    }

    private nonisolated static func numericVersionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix(while: { $0.isNumber })) ?? 0
            }
    }

    private nonisolated static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private nonisolated static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: "Update status"), arguments: arguments)
    }

    private nonisolated static var installDestination: URL {
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        if currentBundleURL.path.hasPrefix("/Applications/") {
            return currentBundleURL
        }
        return URL(fileURLWithPath: "/Applications/Codex Limit Widget.app", isDirectory: true)
    }
}

private struct PreparedUpdate: Sendable {
    let appURL: URL
    let temporaryDirectory: URL
}

private struct GitHubReleasePayload: Decodable, Sendable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable, Sendable {
    let name: String
    let downloadURL: String
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case digest
    }
}

private enum AppUpdateError: LocalizedError, Equatable {
    case updateCheckTimedOut
    case missingReleaseAsset
    case invalidServerResponse
    case checksumMismatch
    case missingAppBundle
    case invalidAppBundle
    case applicationsFolderNotWritable
    case commandFailed

    var errorDescription: String? {
        switch self {
        case .updateCheckTimedOut:
            return NSLocalizedString("Update check timed out. Please try again.", comment: "Update check timeout")
        case .missingReleaseAsset:
            return NSLocalizedString("The release does not contain a macOS ZIP archive.", comment: "Missing update asset")
        case .invalidServerResponse:
            return NSLocalizedString("GitHub returned an invalid response.", comment: "Invalid update response")
        case .checksumMismatch:
            return NSLocalizedString("The downloaded update failed its SHA-256 check. Try again.", comment: "Update checksum error")
        case .missingAppBundle:
            return NSLocalizedString("The downloaded archive does not contain the application.", comment: "Missing application bundle")
        case .invalidAppBundle:
            return NSLocalizedString("The downloaded application identity or version is invalid.", comment: "Invalid application bundle")
        case .applicationsFolderNotWritable:
            return NSLocalizedString("The Applications folder is not writable. Open the release page to install manually.", comment: "Applications folder error")
        case .commandFailed:
            return NSLocalizedString("The downloaded application failed verification.", comment: "Application verification error")
        }
    }
}
