import Foundation

// MARK: - Living Profile Service
//
// Top-level orchestrator. This is the single entry point engineers wire up.
//
// Typical lifecycle:
//   1. App starts → init LivingProfileService with config + userId
//   2. Before session → call buildSessionContext() → inject result into system prompt
//   3. After session → LLM produces ExtractionPackage → call persist(_:)
//
// Thread safety: All public methods are async and actor-isolated internally.
// Safe to call from any Swift concurrency context.

public final class LivingProfileService: Sendable {
    private let retain: ProfileRetainService
    private let recall: ProfileRecallService
    public  let userId: String

    public init(config: HindsightConfig, userId: String) {
        let client   = HindsightClient(config: config)
        self.retain  = ProfileRetainService(client: client)
        self.recall  = ProfileRecallService(client: client)
        self.userId  = userId
    }

    // MARK: - Write path

    /// Call this once the extraction LLM returns an ExtractionPackage.
    /// Persists every non-empty layer to Hindsight.
    ///
    /// Trigger: `pom_data_package_ready` event from the conversation pipeline.
    public func persist(_ package: ExtractionPackage) async throws {
        guard package.metadata.userId == userId else {
            throw LivingProfileError.userIdMismatch(
                expected: userId,
                received: package.metadata.userId
            )
        }
        try await retain.persist(package)
    }

    // MARK: - Read path

    /// Call this before every coaching session to build the context block.
    /// Pass the result's `renderForPrompt()` output into the coaching AI's system prompt.
    ///
    /// - Parameters:
    ///   - query:  A short description of today's session focus (e.g. "fear of failure before
    ///             the championship"). Used to bias semantic recall toward relevant dimensions.
    ///             Pass an empty string for a general check-in.
    ///   - budget: Controls Hindsight token budget. Use `.high` for first sessions,
    ///             `.mid` for standard sessions, `.low` for quick check-ins.
    public func buildSessionContext(
        query: String = "",
        budget: RecallBudget = .mid
    ) async throws -> CoachSessionContext {
        try await recall.buildSessionContext(userId: userId, query: query, budget: budget)
    }

    // MARK: - Targeted reads (for UI, dashboards, admin tools)

    /// Retrieve the current state of a single profile dimension (1-21).
    public func dimension(_ number: Int) async throws -> [RecallFact] {
        try await recall.recallDimension(number, userId: userId)
    }

    /// Retrieve all dimensions for a pillar.
    public func pillar(_ pillar: Pillar) async throws -> [RecallFact] {
        try await recall.recallPillar(pillar, userId: userId)
    }

    /// Retrieve signal flags by severity. Severity `.escalate` should be surfaced
    /// to the Clinical Profiling Agent immediately.
    public func flags(severity: FlagSeverity) async throws -> [RecallFact] {
        try await recall.recallFlags(severity: severity, userId: userId)
    }
}

// MARK: - Errors

public enum LivingProfileError: Error, LocalizedError {
    case userIdMismatch(expected: String, received: String)

    public var errorDescription: String? {
        switch self {
        case .userIdMismatch(let expected, let received):
            return "ExtractionPackage userId '\(received)' does not match service userId '\(expected)'."
        }
    }
}
