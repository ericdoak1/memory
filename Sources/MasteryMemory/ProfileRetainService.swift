import Foundation

// MARK: - Profile Retain Service
//
// Translates an ExtractionPackage (produced after every conversation) into
// Hindsight retain() calls. One bank per user (bankId = userId). Tags are the
// primary recall surface — use them consistently.
//
// Tag taxonomy:
//   layer:<name>          — which Living Profile layer this item belongs to
//   dim:<number>          — which of the 21 dimensions (Layer 2 items only)
//   pillar:<name>         — mind | body | soul | craft
//   session:<sessionId>   — ties every item to its originating session
//   flag:<type>           — for Layer 5 signal flags
//   severity:<level>      — note | monitor | escalate (signal flags only)
//
// document_id strategy:
//   Bio items:             "bio:<userId>:<category>"   — one record per category, replaced
//   Dimension items:       "dim:<userId>:<number>"     — one record per dimension, replaced
//   Coach's Journal:       "journal:<userId>:latest"   — always the most recent entry
//   Coaching Picture:      "picture:<userId>"          — replaced each session
//   Signal flags:          "flag:<sessionId>:<index>"  — append (no update_mode replace)
//   Session brief:         "brief:<sessionId>"         — immutable, written once
//   Timeline events:       "timeline:<sessionId>:<index>"
//   Conversation log:      "convlog:<sessionId>"
//   Program state:         "program:<userId>"
//   Management (goals):    "mgmt-goals:<userId>"
//   Management (habits):   "mgmt-habits:<userId>"
//   Management (todos):    "mgmt-todos:<userId>"

public actor ProfileRetainService {
    private let client: HindsightClient

    public init(client: HindsightClient) {
        self.client = client
    }

    // MARK: - Public entry point

    /// Call this once the extraction LLM has produced an ExtractionPackage.
    /// Writes every non-empty layer to Hindsight. Throws on the first network failure.
    public func persist(_ package: ExtractionPackage) async throws {
        let userId           = package.metadata.userId
        let sessionId        = package.metadata.sessionId
        let bankId           = userId
        let sessionTimestamp = package.metadata.timestampStart

        var items: [RetainItem] = []

        // Layer 1 — Bio
        if let updates = package.bioUpdates {
            items += bioItems(updates, userId: userId, sessionId: sessionId, timestamp: sessionTimestamp)
        }

        // Layer 2 — 21 Dimensions
        if let updates = package.dimensionUpdates {
            items += dimensionItems(updates, userId: userId, sessionId: sessionId, timestamp: sessionTimestamp)
        }

        // Layer 3 — Session Brief (always present)
        items += briefItems(package.sessionBrief, sessionId: sessionId, timestamp: sessionTimestamp)

        // Layer 4 — Timeline
        if let events = package.timelineEvents {
            items += timelineItems(events, sessionId: sessionId)
        }
        items.append(conversationLogItem(package.conversationLog, sessionId: sessionId))

        // Layer 5 — Signal Flags
        if let flags = package.signalFlags {
            items += signalFlagItems(flags, sessionId: sessionId, timestamp: sessionTimestamp)
        }

        // Layer 6 — Coach's Journal (always present)
        items.append(journalItem(package.coachesJournal, userId: userId, sessionId: sessionId, timestamp: sessionTimestamp))

        // Layer 7 — Program State
        if let state = package.programStateUpdate {
            items += programStateItems(state, userId: userId, sessionId: sessionId, timestamp: sessionTimestamp)
        }

        // Layer 8 — Management System
        if let mgmt = package.managementUpdates {
            items += managementItems(mgmt, userId: userId, sessionId: sessionId, timestamp: sessionTimestamp)
        }

        // Batch in chunks of 50; use async so the HTTP call returns immediately
        // while Hindsight indexes in the background (post-session write path).
        for batch in items.chunked(into: 50) {
            _ = try await client.retain(bankId: bankId, items: batch, async: true)
        }
    }

    // MARK: - Layer 1: Bio

    private func bioItems(_ updates: [BioUpdate], userId: String, sessionId: String, timestamp: String) -> [RetainItem] {
        updates.map { update in
            let doc = """
            Category: \(update.category.rawValue)
            Confidence: \(update.confidence.rawValue)

            \(update.content)

            Source: "\(update.sourceQuote)"
            """
            return RetainItem(
                content: doc,
                context: "Biographical fact extracted from session \(sessionId). Confidence: \(update.confidence.rawValue).",
                timestamp: timestamp,
                documentId: "bio:\(userId):\(update.category.rawValue)",
                updateMode: "replace",
                tags: ["layer:bio", "session:\(sessionId)", "bio-category:\(update.category.rawValue)"],
                metadata: ["user_id": userId, "session_id": sessionId, "confidence": update.confidence.rawValue]
            )
        }
    }

    // MARK: - Layer 2: 21 Dimensions

    private func dimensionItems(_ updates: [DimensionUpdate], userId: String, sessionId: String, timestamp: String) -> [RetainItem] {
        updates.map { update in
            let doc = """
            Dimension \(update.dimensionNumber): \(update.dimensionName)
            Pillar: \(update.pillar.rawValue)
            Direction: \(update.direction.rawValue)
            Weight: \(update.weight.rawValue)

            Signal: \(update.signal)

            Evidence: "\(update.evidence)"
            """
            return RetainItem(
                content: doc,
                context: "Profile dimension signal from session \(sessionId). Direction '\(update.direction.rawValue)' means: \(directionExplanation(update.direction)).",
                timestamp: timestamp,
                documentId: "dim:\(userId):\(update.dimensionNumber)",
                updateMode: "replace",
                tags: [
                    "layer:dimensions",
                    "dim:\(update.dimensionNumber)",
                    "pillar:\(update.pillar.rawValue)",
                    "session:\(sessionId)"
                ],
                metadata: [
                    "user_id":          userId,
                    "session_id":       sessionId,
                    "dimension_number": String(update.dimensionNumber),
                    "dimension_name":   update.dimensionName,
                    "direction":        update.direction.rawValue,
                    "weight":           update.weight.rawValue
                ]
            )
        }
    }

    private func directionExplanation(_ direction: SignalDirection) -> String {
        switch direction {
        case .newSignal:     return "first time this dimension has surfaced"
        case .deepening:     return "adds resolution to what is already known"
        case .shift:         return "something has changed from the stored profile"
        case .contradiction: return "conflicts with stored profile — do not resolve, hold as tension"
        }
    }

    // MARK: - Layer 3: Session Brief

    private func briefItems(_ brief: SessionBrief, sessionId: String, timestamp: String) -> [RetainItem] {
        var items: [RetainItem] = []

        let doc = """
        Summary: \(brief.summary)

        Emotional Arc:
          Start: \(brief.emotionalArc.start)
          End:   \(brief.emotionalArc.end)
          Shift: \(brief.emotionalArc.shift)
        """
        items.append(RetainItem(
            content: doc,
            context: "Session brief for \(sessionId). Captures the emotional arc and key themes.",
            timestamp: timestamp,
            documentId: "brief:\(sessionId)",
            updateMode: "replace",
            tags: ["layer:sessions", "session:\(sessionId)"],
            metadata: ["session_id": sessionId]
        ))

        if let threads = brief.openThreads, !threads.isEmpty {
            let threadDoc = threads.map { t in
                "[\(t.priority.rawValue)] \(t.thread)"
            }.joined(separator: "\n")
            items.append(RetainItem(
                content: threadDoc,
                context: "Open coaching threads from session \(sessionId). Priority codes: follow_up_next_session > monitor > park.",
                timestamp: timestamp,
                documentId: "threads:\(sessionId)",
                updateMode: "replace",
                tags: ["layer:sessions", "open-threads", "session:\(sessionId)"],
                metadata: ["session_id": sessionId]
            ))
        }

        if let commitments = brief.commitments, !commitments.isEmpty {
            let commitDoc = commitments.map { c in
                c.timeframe.map { "• \(c.commitment) (by \($0))" } ?? "• \(c.commitment)"
            }.joined(separator: "\n")
            items.append(RetainItem(
                content: commitDoc,
                context: "Commitments made by the person in session \(sessionId).",
                timestamp: timestamp,
                documentId: "commitments:\(sessionId)",
                updateMode: "replace",
                tags: ["layer:sessions", "commitments", "session:\(sessionId)"],
                metadata: ["session_id": sessionId]
            ))
        }

        if let responses = brief.practiceResponses, !responses.isEmpty {
            let responseDoc = responses.map { r in
                let name = r.practiceName.map { " (\($0))" } ?? ""
                return "\(r.practiceType)\(name): \(r.response)"
            }.joined(separator: "\n\n")
            items.append(RetainItem(
                content: responseDoc,
                context: "How the person responded to practices in session \(sessionId).",
                timestamp: timestamp,
                documentId: "practice-responses:\(sessionId)",
                updateMode: "replace",
                tags: ["layer:sessions", "practices", "session:\(sessionId)"],
                metadata: ["session_id": sessionId]
            ))
        }

        return items
    }

    // MARK: - Layer 4: Timeline

    private func timelineItems(_ events: [TimelineEvent], sessionId: String) -> [RetainItem] {
        events.enumerated().map { (index, event) in
            let dateStr = event.date ?? "undated"
            let dims = event.dimensionsTouched?.map(String.init).joined(separator: ",") ?? ""
            let doc = """
            Type: \(event.eventType.rawValue)
            Date: \(dateStr)

            \(event.description)
            """
            var metadata: [String: String] = [
                "session_id": sessionId,
                "event_type": event.eventType.rawValue,
                "date": dateStr
            ]
            if !dims.isEmpty { metadata["dimensions_touched"] = dims }

            return RetainItem(
                content: doc,
                timestamp: event.date,
                documentId: "timeline:\(sessionId):\(index)",
                updateMode: "replace",
                tags: ["layer:timeline", "event:\(event.eventType.rawValue)", "session:\(sessionId)"],
                metadata: metadata
            )
        }
    }

    private func conversationLogItem(_ entry: ConversationLogEntry, sessionId: String) -> RetainItem {
        let doc = """
        Date: \(entry.date)
        Type: \(entry.type.rawValue)

        \(entry.brief)
        """
        return RetainItem(
            content: doc,
            context: "Conversation log entry for session \(sessionId).",
            timestamp: entry.date,
            documentId: "convlog:\(sessionId)",
            updateMode: "replace",
            tags: ["layer:timeline", "conv-log", "conv-type:\(entry.type.rawValue)", "session:\(sessionId)"],
            metadata: ["session_id": sessionId, "conv_type": entry.type.rawValue]
        )
    }

    // MARK: - Layer 5: Signal Flags

    private func signalFlagItems(_ flags: [SignalFlag], sessionId: String, timestamp: String) -> [RetainItem] {
        flags.enumerated().map { (index, flag) in
            let doc = """
            Flag: \(flag.flagType.rawValue)
            Severity: \(flag.severity.rawValue)

            \(flag.description)

            Evidence: "\(flag.evidence)"
            """
            return RetainItem(
                content: doc,
                context: "Signal flag from session \(sessionId). Severity '\(flag.severity.rawValue)': \(severityNote(flag.severity)).",
                timestamp: timestamp,
                documentId: "flag:\(sessionId):\(index)",
                updateMode: "replace",
                tags: [
                    "layer:signals",
                    "flag:\(flag.flagType.rawValue)",
                    "severity:\(flag.severity.rawValue)",
                    "session:\(sessionId)"
                ],
                metadata: [
                    "session_id": sessionId,
                    "flag_type":  flag.flagType.rawValue,
                    "severity":   flag.severity.rawValue
                ]
            )
        }
    }

    private func severityNote(_ severity: FlagSeverity) -> String {
        switch severity {
        case .note:     return "store and monitor passively"
        case .monitor:  return "watch for recurrence across sessions"
        case .escalate: return "surface to Clinical Profiling Agent immediately"
        }
    }

    // MARK: - Layer 6: Coach's Journal

    private func journalItem(_ journal: CoachesJournal, userId: String, sessionId: String, timestamp: String) -> RetainItem {
        let dims = journal.dimensionsTagged.map(String.init).joined(separator: ",")
        let doc = """
        \(journal.entry)

        Dimensions addressed: \(dims)
        """
        var tags = ["layer:journal", "session:\(sessionId)"]
        journal.dimensionsTagged.forEach { tags.append("dim:\($0)") }

        return RetainItem(
            content: doc,
            context: "Coach's Journal entry — written in coach's voice, visible to the person. Session \(sessionId).",
            timestamp: timestamp,
            documentId: "journal:\(userId):latest",
            updateMode: "replace",
            tags: tags,
            metadata: ["user_id": userId, "session_id": sessionId, "dimensions": dims]
        )
    }

    // MARK: - Layer 7: Program State

    private func programStateItems(_ state: ProgramStateUpdate, userId: String, sessionId: String, timestamp: String) -> [RetainItem] {
        var items: [RetainItem] = []

        var parts: [String] = []
        if let progress = state.skillProgress {
            var block = "Skill: \(progress.skillName)\nPhase before: \(progress.phaseBefore)\nPhase after:  \(progress.phaseAfter)"
            if let notes = progress.notes { block += "\nNotes: \(notes)" }
            parts.append(block)
        }
        if let prescribed = state.practicesPrescribed, !prescribed.isEmpty {
            parts.append("Practices prescribed:\n" + prescribed.map { "• \($0)" }.joined(separator: "\n"))
        }
        if let notes = state.arcNotes {
            parts.append("Arc notes: \(notes)")
        }

        if !parts.isEmpty {
            items.append(RetainItem(
                content: parts.joined(separator: "\n\n"),
                context: "Program state after session \(sessionId). Tracks skill progression through the 12-skill arc.",
                timestamp: timestamp,
                documentId: "program:\(userId)",
                updateMode: "replace",
                tags: ["layer:program", "session:\(sessionId)"],
                metadata: ["user_id": userId, "session_id": sessionId]
            ))
        }

        return items
    }

    // MARK: - Layer 8: Management System

    private func managementItems(_ updates: ManagementUpdates, userId: String, sessionId: String, timestamp: String) -> [RetainItem] {
        var items: [RetainItem] = []

        if let goals = updates.goals, !goals.isEmpty {
            let doc = goals.map { "[\($0.action.rawValue)] \($0.description)" }.joined(separator: "\n")
            items.append(RetainItem(
                content: doc,
                context: "Goals management updates from session \(sessionId).",
                timestamp: timestamp,
                documentId: "mgmt-goals:\(userId)",
                updateMode: "replace",
                tags: ["layer:management", "mgmt:goals", "session:\(sessionId)"],
                metadata: ["user_id": userId, "session_id": sessionId]
            ))
        }

        if let habits = updates.habits, !habits.isEmpty {
            let doc = habits.map { "[\($0.action.rawValue)] \($0.description)" }.joined(separator: "\n")
            items.append(RetainItem(
                content: doc,
                context: "Habits management updates from session \(sessionId).",
                timestamp: timestamp,
                documentId: "mgmt-habits:\(userId)",
                updateMode: "replace",
                tags: ["layer:management", "mgmt:habits", "session:\(sessionId)"],
                metadata: ["user_id": userId, "session_id": sessionId]
            ))
        }

        if let todos = updates.todos, !todos.isEmpty {
            let doc = todos.map { "[\($0.action.rawValue)] \($0.description)" }.joined(separator: "\n")
            items.append(RetainItem(
                content: doc,
                context: "To-dos management updates from session \(sessionId).",
                timestamp: timestamp,
                documentId: "mgmt-todos:\(userId)",
                updateMode: "replace",
                tags: ["layer:management", "mgmt:todos", "session:\(sessionId)"],
                metadata: ["user_id": userId, "session_id": sessionId]
            ))
        }

        return items
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
