import Foundation

// MARK: - Profile Recall Service
//
// Assembles context for the coaching AI before a session begins.
// Reads from Hindsight in priority order — most time-sensitive layers first.
//
// Recall strategy:
//   • Use recall() for factual retrieval (bio, dimensions, recent threads)
//   • Use reflect() for synthesized narrative (coaching picture, architecture read)
//   • Scope every query with tags to avoid cross-user bleed
//
// Budget guidance:
//   "high"  — opening session for a new user (needs full bio + all 21 dims)
//   "mid"   — standard daily session (recent 3 sessions + active dims)
//   "low"   — quick check-in (journal + open threads only)

public actor ProfileRecallService {
    private let client: HindsightClient

    public init(client: HindsightClient) {
        self.client = client
    }

    // MARK: - Session Context

    /// Assembles the full context block the Coach AI needs before a session.
    /// Returns a structured `CoachSessionContext` ready to inject into the system prompt.
    public func buildSessionContext(
        userId: String,
        query: String,
        budget: RecallBudget = .mid
    ) async throws -> CoachSessionContext {
        let bankId = userId

        async let recentSessions   = recallRecentSessions(bankId: bankId, userId: userId, budget: budget)
        async let openThreads      = recallOpenThreads(bankId: bankId, userId: userId)
        async let journal          = recallJournal(bankId: bankId, userId: userId)
        async let signalFlags      = recallSignalFlags(bankId: bankId, userId: userId)
        async let activeDimensions = recallActiveDimensions(bankId: bankId, userId: userId, query: query, budget: budget)
        async let bio              = recallBio(bankId: bankId, userId: userId, query: query)
        async let programState     = recallProgramState(bankId: bankId, userId: userId)
        async let managementItems  = recallManagement(bankId: bankId, userId: userId)

        // reflect() calls are synthesis operations — run after factual recalls settle
        async let coachingPicture  = reflectCoachingPicture(bankId: bankId, userId: userId, query: query)
        async let architectureRead = reflectArchitecture(bankId: bankId, userId: userId, query: query)

        return try await CoachSessionContext(
            recentSessions:   recentSessions,
            openThreads:      openThreads,
            journal:          journal,
            signalFlags:      signalFlags,
            activeDimensions: activeDimensions,
            bio:              bio,
            coachingPicture:  coachingPicture,
            architectureRead: architectureRead,
            programState:     programState,
            managementItems:  managementItems
        )
    }

    // MARK: - Layer reads

    /// Recent 3-5 session briefs — highest priority for continuity
    private func recallRecentSessions(bankId: String, userId: String, budget: RecallBudget) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "recent session briefs and conversation summaries",
            budget: budget.rawValue,
            maxTokens: 2048,
            tags: ["layer:sessions"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: bankId, request: request).results
    }

    /// Open threads the Coach must address or continue
    private func recallOpenThreads(bankId: String, userId: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "open threads commitments follow up next session",
            budget: "mid",
            maxTokens: 1024,
            tags: ["open-threads"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: bankId, request: request).results
    }

    /// The most recent Coach's Journal entry — voice and tone calibration
    private func recallJournal(bankId: String, userId: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "coach journal entry latest",
            budget: "low",
            maxTokens: 512,
            tags: ["layer:journal"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: bankId, request: request).results
    }

    /// Active signal flags — especially monitor and escalate severity
    private func recallSignalFlags(bankId: String, userId: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "distress signal avoidance pattern incongruence escalate monitor",
            budget: "low",
            maxTokens: 512,
            tags: ["layer:signals"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: bankId, request: request).results
    }

    /// Dimensions most relevant to the incoming session query
    private func recallActiveDimensions(bankId: String, userId: String, query: String, budget: RecallBudget) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: query.isEmpty ? "identity self-belief motivation fear resilience" : query,
            budget: budget.rawValue,
            maxTokens: 2048,
            tags: ["layer:dimensions"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: bankId, request: request).results
    }

    /// Biographical facts relevant to the session query
    private func recallBio(bankId: String, userId: String, query: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: query.isEmpty ? "background origin sport career family" : query,
            budget: "low",
            maxTokens: 1024,
            tags: ["layer:bio"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: bankId, request: request).results
    }

    /// Current program state — which skill arc, which phase
    private func recallProgramState(bankId: String, userId: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "program state skill arc phase practices prescribed",
            budget: "low",
            maxTokens: 512,
            tags: ["layer:program"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: bankId, request: request).results
    }

    /// Active goals, habits, and to-dos
    private func recallManagement(bankId: String, userId: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "goals habits todos active",
            budget: "low",
            maxTokens: 512,
            tags: ["layer:management"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: bankId, request: request).results
    }

    // MARK: - Reflect calls (synthesized narrative)

    /// Agentic synthesis of the overall Coaching Picture — where is this person?
    private func reflectCoachingPicture(bankId: String, userId: String, query: String) async throws -> String {
        let reflectQuery = """
        Synthesize a coaching picture for this athlete/performer. Include:
        - Their current psychological state across mind, body, soul, craft
        - The most active growth edges right now
        - Key patterns and contradictions in the profile
        - What this person most needs from their Coach today
        Context of today's session: \(query.isEmpty ? "general check-in" : query)
        """
        let request = ReflectRequest(
            query: reflectQuery,
            budget: "mid",
            maxTokens: 1024,
            tags: ["layer:dimensions", "layer:sessions", "layer:journal"],
            tagsMatch: "any_strict"
        )
        return try await client.reflect(bankId: bankId, request: request).text
    }

    /// Architecture read — Challenge/Threat state and Human Architecture layers
    private func reflectArchitecture(bankId: String, userId: String, query: String) async throws -> String {
        let reflectQuery = """
        Reflect on this person's Human Architecture:
        - Root System (core values, identity, purpose)
        - Belief System (self-belief, limiting beliefs, growth edges)
        - Emotional Regulation (Challenge vs Threat state patterns, triggers, resources)
        - Behavioral Patterns (what do they default to under pressure?)
        - Performance Layer (how does inner state translate to outer results?)
        What is their likely Challenge/Threat state entering today's session?
        Context: \(query.isEmpty ? "general check-in" : query)
        """
        let request = ReflectRequest(
            query: reflectQuery,
            budget: "mid",
            maxTokens: 1024,
            tags: ["layer:dimensions", "layer:signals", "layer:sessions"],
            tagsMatch: "any_strict"
        )
        return try await client.reflect(bankId: bankId, request: request).text
    }

    // MARK: - Targeted dimension recall

    /// Recall a specific dimension by number (1-21). Useful for deep dives.
    public func recallDimension(_ number: Int, userId: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "dimension \(number) profile signal evidence",
            budget: "low",
            maxTokens: 512,
            tags: ["dim:\(number)"],
            tagsMatch: "any_strict"
        )
        return try await client.recall(bankId: userId, request: request).results
    }

    /// Recall all dimensions for a pillar (mind | body | soul | craft).
    public func recallPillar(_ pillar: Pillar, userId: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "\(pillar.rawValue) pillar profile dimensions",
            budget: "mid",
            maxTokens: 2048,
            tags: ["layer:dimensions", "pillar:\(pillar.rawValue)"],
            tagsMatch: "all_strict"
        )
        return try await client.recall(bankId: userId, request: request).results
    }

    /// Recall all flags of a given severity. Used by the Clinical Profiling Agent.
    public func recallFlags(severity: FlagSeverity, userId: String) async throws -> [RecallFact] {
        let request = RecallRequest(
            query: "signal flag \(severity.rawValue)",
            budget: "mid",
            maxTokens: 1024,
            tags: ["layer:signals", "severity:\(severity.rawValue)"],
            tagsMatch: "all_strict"
        )
        return try await client.recall(bankId: userId, request: request).results
    }
}

// MARK: - Supporting types

public enum RecallBudget: String {
    case low  = "low"
    case mid  = "mid"
    case high = "high"
}

/// Structured context block assembled from Hindsight before each session.
/// Serialize this to inject into the coaching AI's system prompt.
public struct CoachSessionContext: Sendable {
    public let recentSessions:   [RecallFact]
    public let openThreads:      [RecallFact]
    public let journal:          [RecallFact]
    public let signalFlags:      [RecallFact]
    public let activeDimensions: [RecallFact]
    public let bio:              [RecallFact]
    public let coachingPicture:  String       // synthesized via reflect()
    public let architectureRead: String       // synthesized via reflect()
    public let programState:     [RecallFact]
    public let managementItems:  [RecallFact]

    /// Renders a plain-text context block for injection into a system prompt.
    /// Engineers: adjust heading style to match your prompt template.
    public func renderForPrompt() -> String {
        var sections: [String] = []

        if !coachingPicture.isEmpty {
            sections.append("## Coaching Picture\n\(coachingPicture)")
        }
        if !architectureRead.isEmpty {
            sections.append("## Human Architecture Read\n\(architectureRead)")
        }
        if !journal.isEmpty {
            sections.append("## Most Recent Journal Entry\n" + journal.map(\.text).joined(separator: "\n\n"))
        }
        if !openThreads.isEmpty {
            sections.append("## Open Threads\n" + openThreads.map(\.text).joined(separator: "\n"))
        }
        if !signalFlags.isEmpty {
            sections.append("## Active Signal Flags\n" + signalFlags.map(\.text).joined(separator: "\n\n"))
        }
        if !recentSessions.isEmpty {
            sections.append("## Recent Sessions\n" + recentSessions.map(\.text).joined(separator: "\n\n"))
        }
        if !activeDimensions.isEmpty {
            sections.append("## Relevant Profile Dimensions\n" + activeDimensions.map(\.text).joined(separator: "\n\n"))
        }
        if !bio.isEmpty {
            sections.append("## Biographical Context\n" + bio.map(\.text).joined(separator: "\n\n"))
        }
        if !programState.isEmpty {
            sections.append("## Program State\n" + programState.map(\.text).joined(separator: "\n"))
        }
        if !managementItems.isEmpty {
            sections.append("## Goals / Habits / Todos\n" + managementItems.map(\.text).joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n---\n\n")
    }
}
