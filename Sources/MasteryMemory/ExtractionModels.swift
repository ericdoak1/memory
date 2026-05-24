import Foundation

// MARK: - Extraction Package
// This is the full JSON object produced by the post-conversation extraction prompt.
// One package per conversation. Engineers: this maps exactly to the Universal
// Extraction Schema spec. The LLM fills what the transcript supports — most
// fields will be empty on any given session. That is correct behavior.

public struct ExtractionPackage: Codable {
    public let metadata: SessionMetadata

    // Layer 1
    public let bioUpdates: [BioUpdate]?

    // Layer 2
    public let dimensionUpdates: [DimensionUpdate]?

    // Layer 3
    public let sessionBrief: SessionBrief

    // Layer 4
    public let timelineEvents: [TimelineEvent]?
    public let conversationLog: ConversationLogEntry

    // Layer 5
    public let signalFlags: [SignalFlag]?

    // Layer 6 — always filled
    public let coachesJournal: CoachesJournal

    // Layer 7 (Program State)
    public let programStateUpdate: ProgramStateUpdate?

    // Layer 8 (Management System)
    public let managementUpdates: ManagementUpdates?

    enum CodingKeys: String, CodingKey {
        case metadata
        case bioUpdates           = "bio_updates"
        case dimensionUpdates     = "dimension_updates"
        case sessionBrief         = "session_brief"
        case timelineEvents       = "timeline_events"
        case conversationLog      = "conversation_log"
        case signalFlags          = "signal_flags"
        case coachesJournal       = "coaches_journal"
        case programStateUpdate   = "program_state_update"
        case managementUpdates    = "management_updates"
    }
}

// MARK: - Metadata

public struct SessionMetadata: Codable {
    public let sessionId: String
    public let userId: String
    public let conversationType: ConversationType
    public let timestampStart: String   // ISO 8601
    public let timestampEnd: String     // ISO 8601
    public let sessionDurationMinutes: Int
    public let dayNumber: Int           // day in 100-day arc
    public let currentSkill: InnerSkill?

    enum CodingKeys: String, CodingKey {
        case sessionId              = "session_id"
        case userId                 = "user_id"
        case conversationType       = "conversation_type"
        case timestampStart         = "timestamp_start"
        case timestampEnd           = "timestamp_end"
        case sessionDurationMinutes = "session_duration_minutes"
        case dayNumber              = "day_number"
        case currentSkill           = "current_skill"
    }
}

public enum ConversationType: String, Codable {
    case onboarding, coaching, checkIn = "check_in", deepDive = "deep_dive"
    case innerWork = "inner_work", visualization, meditation, breathwork
    case journaling, goalSetting = "goal_setting", general
}

public enum InnerSkill: String, Codable {
    case gratitude, selfBelief = "self_belief", awareness, fopo
    case emotionalRegulation = "emotional_regulation", focus, selfTalk = "self_talk"
    case resilience, courage, adaptability, identity, craft
}

// MARK: - Layer 1: Bio Updates

public struct BioUpdate: Codable {
    public let category: BioCategory
    public let content: String
    public let sourceQuote: String
    public let confidence: ConfidenceLevel

    enum CodingKeys: String, CodingKey {
        case category, content, confidence
        case sourceQuote = "source_quote"
    }
}

public enum BioCategory: String, Codable {
    case identity, origin, family, earlyLife = "early_life"
    case education, sportCareer = "sport_career", keyLifeEvents = "key_life_events"
    case people, dailyLife = "daily_life", personality
}

public enum ConfidenceLevel: String, Codable {
    case explicit, inferred
}

// MARK: - Layer 2: 21 Dimension Updates

public struct DimensionUpdate: Codable {
    public let dimensionNumber: Int         // 1-21
    public let dimensionName: String
    public let pillar: Pillar
    public let signal: String               // psychological read, not a transcript quote
    public let evidence: String             // verbatim or near-verbatim from transcript
    public let direction: SignalDirection
    public let weight: SignalWeight

    enum CodingKeys: String, CodingKey {
        case pillar, signal, evidence, direction, weight
        case dimensionNumber = "dimension_number"
        case dimensionName   = "dimension_name"
    }
}

public enum Pillar: String, Codable {
    case mind, body, soul, craft
}

public enum SignalDirection: String, Codable {
    case newSignal = "new_signal"   // first time this dimension has been touched
    case deepening                   // adds resolution to what's already known
    case shift                       // something has changed from stored profile
    case contradiction               // conflicts with stored profile — flag, don't resolve
}

public enum SignalWeight: String, Codable {
    case low, medium, high
}

/// The 21 profile dimensions. Engineers: dimension numbers are canonical.
/// Do not reorder. The extraction prompt references them by number.
public enum ProfileDimension: Int, CaseIterable {
    case identityAndSelfBelief   = 1
    case visionPurpose           = 2
    case mentalState             = 3
    case fear                    = 4
    case selfTalk                = 5
    case pressureCompetition     = 6
    case motivationDrive         = 7
    case spiritualityReligion    = 8
    case process                 = 9
    case performance             = 10
    case goals                   = 11
    case shameVulnerability      = 12
    case setbacks                = 13
    case relationships           = 14
    case craftSkillDevelopment   = 15
    case bodyPhysicalState       = 16
    case familyOrigin            = 17
    case growth                  = 18
    case lifeOutsidePerformance  = 19
    case relevantRightNow        = 20
    case moneyAndSecurity        = 21

    public var name: String {
        switch self {
        case .identityAndSelfBelief:  return "Identity & Self-Belief"
        case .visionPurpose:          return "Vision/Purpose"
        case .mentalState:            return "Mental State"
        case .fear:                   return "Fear"
        case .selfTalk:               return "Self-Talk"
        case .pressureCompetition:    return "Pressure/Competition"
        case .motivationDrive:        return "Motivation/Drive"
        case .spiritualityReligion:   return "Spirituality or Religion"
        case .process:                return "Process"
        case .performance:            return "Performance"
        case .goals:                  return "Goals"
        case .shameVulnerability:     return "Shame & Vulnerability"
        case .setbacks:               return "Setbacks"
        case .relationships:          return "Relationships"
        case .craftSkillDevelopment:  return "Craft/Skill Development"
        case .bodyPhysicalState:      return "Body/Physical State"
        case .familyOrigin:           return "Family & Origin"
        case .growth:                 return "Growth"
        case .lifeOutsidePerformance: return "Life Outside Performance"
        case .relevantRightNow:       return "Relevant Right Now"
        case .moneyAndSecurity:       return "Money & Security"
        }
    }

    public var pillar: Pillar {
        switch self {
        case .identityAndSelfBelief, .visionPurpose, .mentalState, .fear,
             .selfTalk, .pressureCompetition, .motivationDrive:
            return .mind
        case .bodyPhysicalState:
            return .body
        case .spiritualityReligion, .shameVulnerability, .familyOrigin,
             .relationships, .lifeOutsidePerformance, .moneyAndSecurity:
            return .soul
        case .craftSkillDevelopment, .process, .performance:
            return .craft
        case .goals, .setbacks, .growth, .relevantRightNow:
            return .mind  // cross-cutting; assigned to mind by default
        }
    }
}

// MARK: - Layer 3: Session Brief

public struct SessionBrief: Codable {
    public let summary: String
    public let emotionalArc: EmotionalArc
    public let openThreads: [OpenThread]?
    public let commitments: [Commitment]?
    public let practiceResponses: [PracticeResponse]?

    enum CodingKeys: String, CodingKey {
        case summary
        case emotionalArc     = "emotional_arc"
        case openThreads      = "open_threads"
        case commitments
        case practiceResponses = "practice_responses"
    }
}

public struct EmotionalArc: Codable {
    public let start: String
    public let end: String
    public let shift: String
}

public struct OpenThread: Codable {
    public let thread: String
    public let priority: ThreadPriority
}

public enum ThreadPriority: String, Codable {
    case followUpNextSession = "follow_up_next_session"
    case monitor
    case park
}

public struct Commitment: Codable {
    public let commitment: String
    public let timeframe: String?
}

public struct PracticeResponse: Codable {
    public let practiceType: String
    public let practiceName: String?
    public let response: String

    enum CodingKeys: String, CodingKey {
        case response
        case practiceType = "practice_type"
        case practiceName = "practice_name"
    }
}

// MARK: - Layer 4: Timeline

public struct TimelineEvent: Codable {
    public let eventType: TimelineEventType
    public let date: String?
    public let description: String
    public let dimensionsTouched: [Int]?

    enum CodingKeys: String, CodingKey {
        case date, description
        case eventType        = "event_type"
        case dimensionsTouched = "dimensions_touched"
    }
}

public enum TimelineEventType: String, Codable {
    case lifeEvent = "life_event", milestone, breakthrough
    case setback, practiceCompleted = "practice_completed", conversation
}

public struct ConversationLogEntry: Codable {
    public let date: String
    public let type: ConversationType
    public let brief: String
}

// MARK: - Layer 5: Signal Flags

public struct SignalFlag: Codable {
    public let flagType: FlagType
    public let description: String
    public let evidence: String
    public let severity: FlagSeverity

    enum CodingKeys: String, CodingKey {
        case description, evidence, severity
        case flagType = "flag_type"
    }
}

public enum FlagType: String, Codable {
    case incongruence
    case avoidancePattern   = "avoidance_pattern"
    case approachShift      = "approach_shift"
    case distressSignal     = "distress_signal"
    case breakthroughSignal = "breakthrough_signal"
}

public enum FlagSeverity: String, Codable {
    case note       // store, no action
    case monitor    // watch for recurrence
    case escalate   // surface to Clinical Profiling Agent immediately
}

// MARK: - Layer 6: Coach's Journal

public struct CoachesJournal: Codable {
    /// 3-5 sentences in Coach's voice. Written for the person — they will see this.
    public let entry: String
    public let dimensionsTagged: [Int]

    enum CodingKeys: String, CodingKey {
        case entry
        case dimensionsTagged = "dimensions_tagged"
    }
}

// MARK: - Layer 7: Program State

public struct ProgramStateUpdate: Codable {
    public let skillProgress: SkillProgress?
    public let practicesPrescribed: [String]?
    public let arcNotes: String?

    enum CodingKeys: String, CodingKey {
        case skillProgress     = "skill_progress"
        case practicesPrescribed = "practices_prescribed"
        case arcNotes          = "arc_notes"
    }
}

public struct SkillProgress: Codable {
    public let skillName: String
    public let phaseBefore: String
    public let phaseAfter: String
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case notes
        case skillName   = "skill_name"
        case phaseBefore = "phase_before"
        case phaseAfter  = "phase_after"
    }
}

// MARK: - Layer 8: Management System

public struct ManagementUpdates: Codable {
    public let goals: [ManagementItem]?
    public let habits: [ManagementItem]?
    public let todos: [ManagementItem]?
}

public struct ManagementItem: Codable {
    public let action: ManagementAction
    public let description: String
}

public enum ManagementAction: String, Codable {
    case created, modified, completed, abandoned, dropped, deferred
}
