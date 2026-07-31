import Darwin
import Foundation

struct CodexCLI: Sendable, Equatable {
    let executableURL: URL
    let environment: [String: String]

    static func resolve() throws -> CodexCLI {
        let environment = makeEnvironment()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let preferredCandidates = [
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]

        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }

        var seenPaths = Set<String>()
        for candidate in preferredCandidates + pathCandidates {
            guard seenPaths.insert(candidate.path).inserted else { continue }
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            return CodexCLI(executableURL: candidate, environment: environment)
        }

        throw CodexRateLimitError.codexNotFound
    }

    static func makeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let additionalPaths = [
            homeDirectory.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let inheritedPaths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var paths = Set<String>()
        let orderedPaths = (additionalPaths + inheritedPaths).filter { paths.insert($0).inserted }
        environment["PATH"] = orderedPaths.joined(separator: ":")
        if environment["HOME"] == nil {
            environment["HOME"] = homeDirectory.path
        }
        return environment
    }

    func run(arguments: [String], environmentOverrides: [String: String] = [:]) async throws -> CodexCLICommandResult {
        var commandEnvironment = environment
        for (key, value) in environmentOverrides {
            commandEnvironment[key] = value
        }

        return try await CodexCLIProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            environment: commandEnvironment
        )
    }

    func authenticationStatus() async throws -> CodexCLIAuthenticationStatus {
        let result = try await run(arguments: ["login", "status"])
        return result.terminationStatus == 0 ? .loggedIn : .notLoggedIn
    }

    func version() async throws -> String {
        let result = try await run(arguments: ["--version"])
        guard result.succeeded, !result.combinedOutput.isEmpty else {
            throw CodexCLICommandError.versionCheckFailed(result.combinedOutput)
        }
        return result.combinedOutput
    }
}

enum CodexCLIAuthenticationStatus: Equatable, Sendable {
    case loggedIn
    case notLoggedIn
}

struct CodexCLICommandResult: Sendable, Equatable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool { terminationStatus == 0 }

    var combinedOutput: String {
        [standardError, standardOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum CodexCLIProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> CodexCLICommandResult {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let temporaryDirectory = fileManager.temporaryDirectory
            let identifier = UUID().uuidString
            let standardOutputURL = temporaryDirectory.appendingPathComponent("codex-limit-\(identifier)-stdout")
            let standardErrorURL = temporaryDirectory.appendingPathComponent("codex-limit-\(identifier)-stderr")

            defer {
                try? fileManager.removeItem(at: standardOutputURL)
                try? fileManager.removeItem(at: standardErrorURL)
            }

            fileManager.createFile(atPath: standardOutputURL.path, contents: nil)
            fileManager.createFile(atPath: standardErrorURL.path, contents: nil)

            let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
            let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
            defer {
                try? standardOutputHandle.close()
                try? standardErrorHandle.close()
            }

            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = standardOutputHandle
            process.standardError = standardErrorHandle

            try process.run()
            process.waitUntilExit()
            try? standardOutputHandle.close()
            try? standardErrorHandle.close()

            let standardOutput = String(
                data: try Data(contentsOf: standardOutputURL),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let standardError = String(
                data: try Data(contentsOf: standardErrorURL),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return CodexCLICommandResult(
                terminationStatus: process.terminationStatus,
                standardOutput: standardOutput,
                standardError: standardError
            )
        }.value
    }
}

enum CodexCLIInstaller {
    static let scriptURL = URL(string: "https://chatgpt.com/codex/install.sh")!
    static let manualInstallCommand = "curl -fsSL https://chatgpt.com/codex/install.sh | sh"

    static func install() async throws {
        let (data, response) = try await URLSession.shared.data(from: scriptURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw CodexCLIInstallError.downloadFailed
        }

        guard data.count <= 2_000_000,
              let script = String(data: data, encoding: .utf8),
              script.hasPrefix("#!/bin/sh")
        else {
            throw CodexCLIInstallError.invalidScript
        }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CodexLimitCLIInstall-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let scriptURL = temporaryDirectory.appendingPathComponent("install.sh")
        try data.write(to: scriptURL, options: [.atomic])

        var environment = CodexCLI.makeEnvironment()
        environment["CODEX_NON_INTERACTIVE"] = "1"
        if environment["CODEX_INSTALL_DIR"] == nil {
            environment["CODEX_INSTALL_DIR"] = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin")
                .path
        }

        let result = try await CodexCLIProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            environment: environment
        )
        guard result.succeeded else {
            throw CodexCLIInstallError.commandFailed(result.combinedOutput)
        }
    }
}

enum CodexCLIInstallError: LocalizedError, Equatable {
    case downloadFailed
    case invalidScript
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "The official Codex CLI installer could not be downloaded."
        case .invalidScript:
            return "The downloaded Codex CLI installer was not recognized."
        case let .commandFailed(output):
            return output.isEmpty ? "The Codex CLI installer failed." : output
        }
    }
}

enum CodexCLICommandError: LocalizedError, Equatable {
    case loginFailed(String)
    case versionCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case let .loginFailed(output):
            return output.isEmpty ? "Codex login did not complete." : output
        case let .versionCheckFailed(output):
            return output.isEmpty ? "Codex CLI version could not be checked." : output
        }
    }
}

struct CodexRateLimitClient {
    func fetch() async throws -> LimitSnapshot {
        let cli = try CodexCLI.resolve()
        let process = Process()
        process.executableURL = cli.executableURL
        process.arguments = ["app-server", "--stdio"]
        process.environment = cli.environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        let reader = JSONLineReader(fileHandle: output.fileHandleForReading)
        defer {
            reader.close()
            stop(process: process, input: input)
        }

        try send(.initialize, to: input.fileHandleForWriting)
        _ = try await reader.response(id: 1, timeout: 5)

        try send(.initialized, to: input.fileHandleForWriting)
        try send(.rateLimitsRead, to: input.fileHandleForWriting)
        let rateLimitsResponse = try await reader.response(id: 2, timeout: 15)
        try send(.usageRead, to: input.fileHandleForWriting)
        let usageResponse = try? await reader.response(id: 3, timeout: 15)

        let usage: AccountUsageSnapshot?
        if let usageResponse {
            usage = try? JSONDecoder().decode(AccountUsageEnvelope.self, from: usageResponse).result.normalizedUsage()
        } else {
            usage = nil
        }

        let envelope = try JSONDecoder().decode(RateLimitsEnvelope.self, from: rateLimitsResponse)
        return try envelope.result.normalizedSnapshot(usage: usage)
    }

    private func send(_ request: JSONRPCRequest, to handle: FileHandle) throws {
        let data = try JSONEncoder().encode(request)
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    private func stop(process: Process, input: Pipe) {
        try? input.fileHandleForWriting.close()
        guard process.isRunning else { return }

        process.terminate()

        DispatchQueue.global(qos: .utility).async {
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }

            process.waitUntilExit()
        }
    }

}

enum CodexRateLimitError: LocalizedError {
    case codexNotFound
    case authenticationRequired
    case timeout
    case missingCodexLimit
    case invalidWindow

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "codex was not found in PATH or fallback paths."
        case .authenticationRequired:
            return "Codex CLI authentication is required."
        case .timeout:
            return "Codex app-server did not respond in time."
        case .missingCodexLimit:
            return "The response does not include the codex limit."
        case .invalidWindow:
            return "The Codex response does not include an available limit window."
        }
    }

    static func isAuthenticationError(code: Int?, message: String) -> Bool {
        let normalized = message.lowercased()
        if code == 401 || code == 403 {
            return true
        }

        return normalized.contains("authentication required")
            || normalized.contains("not logged in")
            || normalized.contains("unauthorized")
            || normalized.contains("unauthenticated")
            || normalized.contains("login required")
    }
}

private final class JSONLineReader: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let queue = DispatchQueue(label: "com.sergeylopukhov.codexlimitwidget.json-line-reader")
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var iterator: AsyncThrowingStream<Data, Error>.Iterator
    private var buffer = Data()
    private var isClosed = false

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        let stream = AsyncThrowingStream<Data, Error> { createdContinuation in
            continuation = createdContinuation
        }
        self.continuation = continuation
        self.iterator = stream.makeAsyncIterator()

        fileHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let reader = self else { return }
            reader.queue.async {
                reader.consume(chunk)
            }
        }
    }

    func response(id: Int, timeout: TimeInterval) async throws -> Data {
        try await withTimeout(timeout) {
            while let line = try await self.nextLine() {
                let meta = try JSONDecoder().decode(JSONRPCResponseMeta.self, from: line)
                guard meta.id == id else { continue }

                if let error = try JSONDecoder().decode(JSONRPCErrorEnvelope.self, from: line).error {
                    let message = error.message ?? "Codex app-server returned an error."
                    if CodexRateLimitError.isAuthenticationError(code: error.code, message: message) {
                        throw CodexRateLimitError.authenticationRequired
                    }
                    throw NSError(
                        domain: "CodexAppServer",
                        code: error.code ?? id,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                }

                return line
            }

            throw CodexRateLimitError.timeout
        }
    }

    func close() {
        queue.async {
            guard !self.isClosed else { return }
            self.isClosed = true
            self.fileHandle.readabilityHandler = nil
            self.continuation.finish()
        }
    }

    private func consume(_ chunk: Data) {
        guard !isClosed else { return }

        if chunk.isEmpty {
            isClosed = true
            continuation.finish()
            return
        }

        buffer.append(chunk)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            continuation.yield(Data(line))
        }
    }

    private func nextLine() async throws -> Data? {
        try await iterator.next()
    }

}

private func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            let nanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
            throw CodexRateLimitError.timeout
        }

        guard let result = try await group.next() else {
            throw CodexRateLimitError.timeout
        }

        group.cancelAll()
        return result
    }
}

private struct JSONRPCResponseMeta: Decodable {
    var id: Int?
}

private struct JSONRPCErrorEnvelope: Decodable {
    var error: JSONRPCErrorDTO?
}

private struct JSONRPCErrorDTO: Decodable {
    var code: Int?
    var message: String?
}

private enum JSONRPCRequest: Encodable {
    case initialize
    case initialized
    case rateLimitsRead
    case usageRead

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)

        switch self {
        case .initialize:
            try container.encode(1, forKey: .id)
            try container.encode("initialize", forKey: .method)
            try container.encode(InitializeParams(), forKey: .params)
        case .initialized:
            try container.encode("initialized", forKey: .method)
        case .rateLimitsRead:
            try container.encode(2, forKey: .id)
            try container.encode("account/rateLimits/read", forKey: .method)
            try container.encodeNil(forKey: .params)
        case .usageRead:
            try container.encode(3, forKey: .id)
            try container.encode("account/usage/read", forKey: .method)
            try container.encodeNil(forKey: .params)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
    }
}

private struct InitializeParams: Encodable {
    var clientInfo = ClientInfo()
    var capabilities = Capabilities()

    struct ClientInfo: Encodable {
        var name = "codex-limit-widget"
        var version = "0.1"
    }

    struct Capabilities: Encodable {
        var experimentalApi = true
    }
}

private struct RateLimitsEnvelope: Decodable {
    var result: RateLimitsResult
}

private struct RateLimitsResult: Decodable {
    var rateLimits: RateLimitSnapshotDTO
    var rateLimitsByLimitId: [String: RateLimitSnapshotDTO]?

    func normalizedSnapshot(usage: AccountUsageSnapshot?) throws -> LimitSnapshot {
        let codex = rateLimitsByLimitId?["codex"] ?? rateLimits
        guard codex.limitId == nil || codex.limitId == "codex" else {
            throw CodexRateLimitError.missingCodexLimit
        }

        // A single weekly window can now be returned as `primary`. Classify
        // windows by their duration instead of assuming primary always means 5h.
        let windows = [codex.primary, codex.secondary].compactMap { $0 }
        let fiveHourWindow = windows.first { $0.windowDurationMins == 5 * 60 }
            ?? (codex.primary?.windowDurationMins == nil ? codex.primary : nil)
        let weeklyWindow = windows.first { $0.windowDurationMins == 7 * 24 * 60 }
            ?? (codex.secondary?.windowDurationMins == nil ? codex.secondary : nil)

        guard fiveHourWindow != nil || weeklyWindow != nil else {
            throw CodexRateLimitError.invalidWindow
        }

        return LimitSnapshot(
            fiveHour: fiveHourWindow.map { window in
                LimitWindowSnapshot(
                    label: "5 hours",
                    usedPercent: window.usedPercent,
                    windowDurationMins: window.windowDurationMins,
                    resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
            },
            weekly: weeklyWindow.map { window in
                LimitWindowSnapshot(
                    label: "Week",
                    usedPercent: window.usedPercent,
                    windowDurationMins: window.windowDurationMins,
                    resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
            },
            credits: codex.credits,
            planType: codex.planType,
            usage: usage,
            updatedAt: Date(),
            errorMessage: nil
        )
    }
}

private struct RateLimitSnapshotDTO: Decodable {
    var limitId: String?
    var primary: RateLimitWindowDTO?
    var secondary: RateLimitWindowDTO?
    var credits: CreditsSnapshot?
    var planType: String?

    private enum CodingKeys: String, CodingKey {
        case limitId
        case primary
        case secondary
        case credits
        case planType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitId = try container.decodeIfPresent(String.self, forKey: .limitId)
        primary = try container.decodeIfPresent(RateLimitWindowDTO.self, forKey: .primary)
        secondary = try container.decodeIfPresent(RateLimitWindowDTO.self, forKey: .secondary)
        credits = try? container.decode(CreditsSnapshot.self, forKey: .credits)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
    }
}

private struct RateLimitWindowDTO: Decodable {
    var usedPercent: Int
    var windowDurationMins: Int?
    var resetsAt: Int?
}

private struct AccountUsageEnvelope: Decodable {
    var result: AccountUsageResult
}

private struct AccountUsageResult: Decodable {
    var summary: AccountUsageSummaryDTO
    var dailyUsageBuckets: [AccountUsageDailyBucketDTO]?

    func normalizedUsage() -> AccountUsageSnapshot {
        let lastBucket = dailyUsageBuckets?.sorted { $0.startDate < $1.startDate }.last

        return AccountUsageSnapshot(
            lifetimeTokens: summary.lifetimeTokens,
            peakDailyTokens: summary.peakDailyTokens,
            longestRunningTurnSec: summary.longestRunningTurnSec,
            currentStreakDays: summary.currentStreakDays,
            longestStreakDays: summary.longestStreakDays,
            learnedSkillsCount: summary.learnedSkillsCount,
            totalSkillUses: summary.totalSkillUses,
            totalThreads: summary.totalThreads,
            lastDailyTokens: lastBucket?.tokens,
            lastDailyDate: lastBucket?.startDate
        )
    }
}

private struct AccountUsageSummaryDTO: Decodable {
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var longestRunningTurnSec: Int64?
    var currentStreakDays: Int64?
    var longestStreakDays: Int64?
    var learnedSkillsCount: Int64?
    var totalSkillUses: Int64?
    var totalThreads: Int64?

    enum CodingKeys: String, CodingKey {
        case lifetimeTokens
        case peakDailyTokens
        case longestRunningTurnSec
        case currentStreakDays
        case longestStreakDays
        case learnedSkillsCount
        case learnedSkills
        case skillsLearned
        case uniqueSkillsUsed
        case totalSkillUses
        case totalSkillUseCount
        case usedSkillsTotal
        case totalThreads
        case threadCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lifetimeTokens = try container.decodeIfPresent(Int64.self, forKey: .lifetimeTokens)
        peakDailyTokens = try container.decodeIfPresent(Int64.self, forKey: .peakDailyTokens)
        longestRunningTurnSec = try container.decodeIfPresent(Int64.self, forKey: .longestRunningTurnSec)
        currentStreakDays = try container.decodeIfPresent(Int64.self, forKey: .currentStreakDays)
        longestStreakDays = try container.decodeIfPresent(Int64.self, forKey: .longestStreakDays)
        learnedSkillsCount =
            try container.decodeIfPresent(Int64.self, forKey: .learnedSkillsCount) ??
            container.decodeIfPresent(Int64.self, forKey: .learnedSkills) ??
            container.decodeIfPresent(Int64.self, forKey: .skillsLearned) ??
            container.decodeIfPresent(Int64.self, forKey: .uniqueSkillsUsed)
        totalSkillUses =
            try container.decodeIfPresent(Int64.self, forKey: .totalSkillUses) ??
            container.decodeIfPresent(Int64.self, forKey: .totalSkillUseCount) ??
            container.decodeIfPresent(Int64.self, forKey: .usedSkillsTotal)
        totalThreads =
            try container.decodeIfPresent(Int64.self, forKey: .totalThreads) ??
            container.decodeIfPresent(Int64.self, forKey: .threadCount)
    }
}

private struct AccountUsageDailyBucketDTO: Decodable {
    var startDate: String
    var tokens: Int64
}
