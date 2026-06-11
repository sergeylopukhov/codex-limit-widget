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
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let reader = JSONLineReader(fileHandle: output.fileHandleForReading)
        try send(.initialize, to: input.fileHandleForWriting)
        _ = try await reader.response(id: 1, timeout: 5)

        try send(.initialized, to: input.fileHandleForWriting)
        try send(.rateLimitsRead, to: input.fileHandleForWriting)
        let rateLimitsResponse = try await reader.response(id: 2, timeout: 15)
        try send(.usageRead, to: input.fileHandleForWriting)
        let usageResponse = try? await reader.response(id: 3, timeout: 15)

        input.fileHandleForWriting.closeFile()

        let usage: AccountUsageSnapshot?
        if let usageResponse {
            let usageData = try JSONSerialization.data(withJSONObject: usageResponse)
            usage = try? JSONDecoder().decode(AccountUsageEnvelope.self, from: usageData).result.normalizedUsage()
        } else {
            usage = nil
        }

        let data = try JSONSerialization.data(withJSONObject: rateLimitsResponse)
        let envelope = try JSONDecoder().decode(RateLimitsEnvelope.self, from: data)
        return try envelope.result.normalizedSnapshot(usage: usage)
    }

    private func send(_ request: JSONRPCRequest, to handle: FileHandle) throws {
        let data = try JSONEncoder().encode(request)
        handle.write(data)
        handle.write(Data([0x0A]))
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
            return "The Codex response is missing the 5-hour or weekly window."
        }
    }
}

private final class JSONLineReader {
    private let fileHandle: FileHandle
    private var buffer = Data()

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func response(id: Int, timeout: TimeInterval) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let object = try nextObject(), object["id"] as? Int == id {
                if let error = object["error"] {
                    throw NSError(domain: "CodexAppServer", code: id, userInfo: [NSLocalizedDescriptionKey: "\(error)"])
                }
                return object
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw CodexRateLimitError.timeout
    }

    private func nextObject() throws -> [String: Any]? {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            return try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
        }

        let chunk = fileHandle.availableData
        if chunk.isEmpty { return nil }
        buffer.append(chunk)
        return try nextObject()
    }
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
        guard let primary = codex.primary, let secondary = codex.secondary else {
            throw CodexRateLimitError.invalidWindow
        }

        return LimitSnapshot(
            fiveHour: LimitWindowSnapshot(
                label: "5 hours",
                usedPercent: primary.usedPercent,
                windowDurationMins: primary.windowDurationMins,
                resetsAt: primary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ),
            weekly: LimitWindowSnapshot(
                label: "Week",
                usedPercent: secondary.usedPercent,
                windowDurationMins: secondary.windowDurationMins,
                resetsAt: secondary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ),
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
