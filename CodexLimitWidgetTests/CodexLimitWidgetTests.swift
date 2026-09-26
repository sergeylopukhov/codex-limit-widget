import Foundation
import XCTest
@testable import Codex_Limit_Widget

final class CodexLimitWidgetTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func snapshot(updatedAt: Date) -> LimitSnapshot {
        LimitSnapshot(
            fiveHour: nil,
            weekly: nil,
            credits: nil,
            planType: nil,
            usage: nil,
            updatedAt: updatedAt,
            errorMessage: nil
        )
    }

    private func usage(_ days: [DailyTokenUsage]) -> AccountUsageSnapshot {
        AccountUsageSnapshot(
            dailyTokens: days,
            lifetimeTokens: nil,
            peakDailyTokens: nil,
            longestRunningTurnSec: nil,
            currentStreakDays: nil,
            longestStreakDays: nil,
            learnedSkillsCount: nil,
            totalSkillUses: nil,
            totalThreads: nil,
            lastDailyTokens: nil,
            lastDailyDate: nil,
            updatedAt: nil
        )
    }

    func testRemainingLevelBelowCriticalBoundary() {
        XCTAssertEqual(LimitRemainingLevel.resolve(remainingPercent: 19), .critical)
    }

    func testRemainingLevelAtCriticalBoundary() {
        XCTAssertEqual(LimitRemainingLevel.resolve(remainingPercent: 20), .warning)
    }

    func testRemainingLevelBelowWarningBoundary() {
        XCTAssertEqual(LimitRemainingLevel.resolve(remainingPercent: 49), .warning)
    }

    func testRemainingLevelAtWarningBoundary() {
        XCTAssertEqual(LimitRemainingLevel.resolve(remainingPercent: 50), .normal)
    }

    func testRemainingLevelAtZero() {
        XCTAssertEqual(LimitRemainingLevel.resolve(remainingPercent: 0), .critical)
    }

    func testRecentSnapshotIsNotStale() {
        XCTAssertFalse(snapshot(updatedAt: Date().addingTimeInterval(-299)).isStale)
    }

    func testOldSnapshotIsStale() {
        XCTAssertTrue(snapshot(updatedAt: Date().addingTimeInterval(-301)).isStale)
    }

    func testTokenCountBelowThousand() {
        XCTAssertEqual(TokenCountText.make(999), "999")
    }

    func testTokenCountAtThousand() {
        XCTAssertEqual(TokenCountText.make(1_000), "1.0K")
    }

    func testTokenCountInMillions() {
        XCTAssertEqual(TokenCountText.make(820_100_000), "820.1M")
    }

    func testTokenCountInBillions() {
        XCTAssertEqual(TokenCountText.make(16_380_000_000), "16.38B")
    }

    func testTokenCountAbsent() {
        XCTAssertEqual(TokenCountText.make(nil), "--")
    }

    func testResetClockFormatsHoursAndMinutes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 7, minute: 5))!
        XCTAssertEqual(LimitResetClockText.make(for: date), "07:05")
    }

    func testResetClockWithoutDate() {
        XCTAssertEqual(LimitResetClockText.make(for: nil), "--")
    }

    func testRateLimitsFixtureUsesCodexLimitsAndNormalizesWindows() throws {
        let result = try JSONDecoder().decode(RateLimitsEnvelope.self, from: fixture("rate-limits")).result
        let normalized = try result.normalizedSnapshot(usage: nil)
        XCTAssertEqual(normalized.fiveHour?.usedPercent, 25)
        XCTAssertEqual(normalized.weekly?.usedPercent, 70)
        XCTAssertEqual(normalized.fiveHour?.windowDurationMins, 300)
        XCTAssertEqual(normalized.weekly?.windowDurationMins, 10_080)
        XCTAssertEqual(normalized.planType, "pro")
        XCTAssertEqual(normalized.credits?.balance, "12.5")
    }

    func testUsageFixtureDecodesAliasesAndDailyBuckets() throws {
        let result = try JSONDecoder().decode(AccountUsageEnvelope.self, from: fixture("usage-read")).result
        let normalized = result.normalizedUsage()
        XCTAssertEqual(normalized.lifetimeTokens, 5_400)
        XCTAssertEqual(normalized.learnedSkillsCount, 4)
        XCTAssertEqual(normalized.totalSkillUses, 12)
        XCTAssertEqual(normalized.totalThreads, 6)
        XCTAssertEqual(normalized.dailyTokens?.count, 2)
        XCTAssertEqual(normalized.lastDailyDate, "2026-09-26")
        XCTAssertEqual(normalized.lastDailyTokens, 3_200)
        XCTAssertNotNil(normalized.updatedAt)
    }

    func testLegacySnapshotWithoutUsageTimestampDecodesAsExpired() throws {
        let legacy = try JSONDecoder().decode(LimitSnapshot.self, from: fixture("legacy-snapshot"))
        XCTAssertEqual(legacy.usage?.lifetimeTokens, 1_000)
        XCTAssertNil(legacy.usage?.updatedAt)
        XCTAssertTrue(try XCTUnwrap(legacy.usage).isStale)
        XCTAssertNil(legacy.freshUsage)
    }

    func testPreferencesFromOlderVersionEnableColoredMeter() throws {
        let stored = Data(#"{"menuBarMode":"percentOnly","showsMenuBarItem":true}"#.utf8)
        let preferences = try JSONDecoder().decode(LimitPreferences.self, from: stored)
        XCTAssertTrue(preferences.menuBarColoredMeter)
        XCTAssertFalse(preferences.menuBarColoredDigits)
    }

    func testDisabledColoredMeterStaysDisabled() throws {
        let stored = Data(#"{"menuBarColoredMeter":false}"#.utf8)
        let preferences = try JSONDecoder().decode(LimitPreferences.self, from: stored)
        XCTAssertFalse(preferences.menuBarColoredMeter)
    }

    func testSystemDesignResolvesToDark() {
        XCTAssertEqual(MenuWindowDesign.system.resolved(isDark: true), .terminal)
    }

    func testSystemDesignResolvesToLight() {
        XCTAssertEqual(MenuWindowDesign.system.resolved(isDark: false), .editorial)
    }

    func testExplicitDesignRemainsSelected() {
        XCTAssertEqual(MenuWindowDesign.editorial.resolved(isDark: true), .editorial)
        XCTAssertEqual(MenuWindowDesign.terminal.resolved(isDark: false), .terminal)
    }

    func testSevenDayAverageWithoutBuckets() {
        XCTAssertNil(usage([]).sevenDayAverageTokens)
    }

    func testSevenDayAverageSkipsMissingTokens() {
        let reading = usage([
            DailyTokenUsage(date: "2026-09-24", tokens: 300),
            DailyTokenUsage(date: "2026-09-25", tokens: nil),
            DailyTokenUsage(date: "2026-09-26", tokens: 100)
        ])
        XCTAssertEqual(reading.sevenDayAverageTokens, 200)
    }

    func testSevenDayAverageIncludesZeroTokens() {
        let reading = usage([
            DailyTokenUsage(date: "2026-09-25", tokens: 0),
            DailyTokenUsage(date: "2026-09-26", tokens: 100)
        ])
        XCTAssertEqual(reading.sevenDayAverageTokens, 50)
    }
}
