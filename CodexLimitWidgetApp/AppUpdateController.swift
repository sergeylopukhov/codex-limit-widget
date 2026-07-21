import AppKit
import Combine
import CryptoKit
import Foundation

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

    private let releasesURL = URL(string: "https://api.github.com/repos/sergeylopukhov/codex-limit-widget/releases/latest")!
    private var timer: Timer?
    private var started = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--"
    }

    var isUpdateAvailable: Bool {
        availableRelease != nil
    }

    var isBusy: Bool {
        phase == .checking || phase == .downloading || phase == .installing
    }

    var menuStatusText: String? {
        guard let release = availableRelease else { return nil }
        switch phase {
        case .downloading:
            return "Downloading v\(release.version)…"
        case .installing:
            return "Installing v\(release.version)…"
        default:
            return "Version \(release.version) available"
        }
    }

    var settingsStatusText: String {
        if let release = availableRelease {
            switch phase {
            case .downloading:
                return "Downloading version \(release.version)…"
            case .installing:
                return "Installing version \(release.version)…"
            case .failed:
                return "Version \(release.version) is still available."
            default:
                return "Version \(release.version) is available."
            }
        }

        switch phase {
        case .checking:
            return "Checking GitHub Releases…"
        case .upToDate:
            return "You have the latest version."
        case .failed:
            return "Could not check for updates."
        default:
            return "Updates are checked automatically."
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
        guard phase != .downloading, phase != .installing else { return }

        phase = .checking
        errorMessage = nil

        do {
            let release = try await fetchLatestRelease()
            lastCheckedAt = Date()

            if Self.isVersion(release.version, newerThan: currentVersion) {
                availableRelease = release
                phase = .available
            } else {
                availableRelease = nil
                phase = .upToDate
            }
        } catch {
            phase = .failed
            errorMessage = Self.message(for: error)
        }
    }

    func installAvailableUpdate() async {
        guard let release = availableRelease, phase != .downloading, phase != .installing else { return }

        phase = .downloading
        errorMessage = nil

        do {
            let (downloadURL, response) = try await URLSession.shared.download(from: release.assetURL)
            try Self.validateHTTPResponse(response)

            phase = .installing
            let prepared = try await Task.detached(priority: .userInitiated) {
                try Self.prepareUpdate(downloadURL: downloadURL, release: release)
            }.value

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

    private func fetchLatestRelease() async throws -> AppUpdateRelease {
        var request = URLRequest(url: releasesURL)
        request.timeoutInterval = 20
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
            sha256: asset.digest?.replacingOccurrences(of: "sha256:", with: "")
        )
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

private enum AppUpdateError: LocalizedError {
    case missingReleaseAsset
    case invalidServerResponse
    case checksumMismatch
    case missingAppBundle
    case invalidAppBundle
    case applicationsFolderNotWritable
    case commandFailed

    var errorDescription: String? {
        switch self {
        case .missingReleaseAsset:
            return "The release does not contain a macOS ZIP archive."
        case .invalidServerResponse:
            return "GitHub returned an invalid response."
        case .checksumMismatch:
            return "The downloaded update failed its SHA-256 check."
        case .missingAppBundle:
            return "The downloaded archive does not contain the application."
        case .invalidAppBundle:
            return "The downloaded application identity or version is invalid."
        case .applicationsFolderNotWritable:
            return "The Applications folder is not writable. Open the release page to install manually."
        case .commandFailed:
            return "The downloaded application failed verification."
        }
    }
}
