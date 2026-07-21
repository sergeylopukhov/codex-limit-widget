import Darwin
import Foundation

struct CodexRateLimitClient {
    func fetch() async throws -> LimitSnapshot {
        let codexURL = try resolveCodexExecutable()
        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["app-server", "--stdio"]
        process.environment = environment()

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

    private func resolveCodexExecutable() throws -> URL {
        let candidates = [
            "/Users/sergeylopukhov/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let env = Process()
        env.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        env.arguments = ["which", "codex"]
        let output = Pipe()
        env.standardOutput = output
        try env.run()
        env.waitUntilExit()

        guard env.terminationStatus == 0,
              let data = try output.fileHandleForReading.readToEnd(),
              let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            throw CodexRateLimitError.codexNotFound
        }

        return URL(fileURLWithPath: path)
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let additions = [
            "/Users/sergeylopukhov/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        env["PATH"] = (env["PATH"].map { additions.joined(separator: ":") + ":" + $0 }) ?? additions.joined(separator: ":")
        return env
    }
}

enum CodexRateLimitError: LocalizedError {
    case codexNotFound
    case timeout
    case missingCodexLimit
    case invalidWindow

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "codex was not found in PATH or fallback paths."
        case .timeout:
            return "Codex app-server did not respond in time."
        case .missingCodexLimit:
            return "The response does not include the codex limit."
        case .invalidWindow:
            return "The Codex response does not include an available limit window."
        }
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
                    throw NSError(
                        domain: "CodexAppServer",
                        code: error.code ?? id,
                        userInfo: [NSLocalizedDescriptionKey: error.message ?? "Codex app-server returned an error."]
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
    var planType: String?
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
