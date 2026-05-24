import XCTest
@testable import MasteryMemory

final class ExtractionModelsTests: XCTestCase {

    // MARK: - Full round-trip decode

    func testDecodeMinimalPackage() throws {
        let json = """
        {
          "metadata": {
            "session_id": "sess-001",
            "user_id": "user-abc",
            "conversation_type": "coaching",
            "timestamp_start": "2026-05-24T10:00:00Z",
            "timestamp_end": "2026-05-24T10:45:00Z",
            "session_duration_minutes": 45,
            "day_number": 12
          },
          "session_brief": {
            "summary": "Explored fear of failure before the championship.",
            "emotional_arc": {
              "start": "anxious, guarded",
              "end": "grounded, clearer",
              "shift": "moved from avoidance to curiosity"
            }
          },
          "coaches_journal": {
            "entry": "Today you did something brave — you named the fear instead of hiding behind preparation.",
            "dimensions_tagged": [4, 1, 6]
          },
          "conversation_log": {
            "date": "2026-05-24",
            "type": "coaching",
            "brief": "Fear of failure exploration ahead of championship."
          }
        }
        """
        let package = try JSONDecoder().decode(ExtractionPackage.self, from: Data(json.utf8))
        XCTAssertEqual(package.metadata.sessionId, "sess-001")
        XCTAssertEqual(package.metadata.userId, "user-abc")
        XCTAssertEqual(package.metadata.conversationType, .coaching)
        XCTAssertEqual(package.metadata.dayNumber, 12)
        XCTAssertNil(package.metadata.currentSkill)
        XCTAssertNil(package.bioUpdates)
        XCTAssertNil(package.dimensionUpdates)
        XCTAssertEqual(package.sessionBrief.summary, "Explored fear of failure before the championship.")
        XCTAssertEqual(package.sessionBrief.emotionalArc.end, "grounded, clearer")
        XCTAssertNil(package.timelineEvents)
        XCTAssertNil(package.signalFlags)
        XCTAssertEqual(package.coachesJournal.dimensionsTagged, [4, 1, 6])
        XCTAssertNil(package.programStateUpdate)
        XCTAssertNil(package.managementUpdates)
    }

    func testDecodeFullPackage() throws {
        let json = fullPackageJSON
        let package = try JSONDecoder().decode(ExtractionPackage.self, from: Data(json.utf8))

        // Layer 1
        XCTAssertEqual(package.bioUpdates?.count, 1)
        XCTAssertEqual(package.bioUpdates?.first?.category, .sportCareer)
        XCTAssertEqual(package.bioUpdates?.first?.confidence, .explicit)

        // Layer 2
        XCTAssertEqual(package.dimensionUpdates?.count, 2)
        let dim4 = package.dimensionUpdates?.first(where: { $0.dimensionNumber == 4 })
        XCTAssertEqual(dim4?.direction, .deepening)
        XCTAssertEqual(dim4?.weight, .high)

        // Layer 5
        XCTAssertEqual(package.signalFlags?.count, 1)
        XCTAssertEqual(package.signalFlags?.first?.severity, .monitor)

        // Layer 7
        XCTAssertEqual(package.programStateUpdate?.skillProgress?.skillName, "FOPO")

        // Layer 8
        XCTAssertEqual(package.managementUpdates?.goals?.count, 1)
        XCTAssertEqual(package.managementUpdates?.goals?.first?.action, .created)
    }

    // MARK: - ProfileDimension metadata

    func testAllDimensionsHaveNames() {
        for dim in ProfileDimension.allCases {
            XCTAssertFalse(dim.name.isEmpty, "Dimension \(dim.rawValue) has no name")
        }
    }

    func testDimensionPillarAssignments() {
        XCTAssertEqual(ProfileDimension.identityAndSelfBelief.pillar, .mind)
        XCTAssertEqual(ProfileDimension.bodyPhysicalState.pillar, .body)
        XCTAssertEqual(ProfileDimension.spiritualityReligion.pillar, .soul)
        XCTAssertEqual(ProfileDimension.craftSkillDevelopment.pillar, .craft)
    }

    // MARK: - Fixtures

    private let fullPackageJSON = """
    {
      "metadata": {
        "session_id": "sess-002",
        "user_id": "user-abc",
        "conversation_type": "deep_dive",
        "timestamp_start": "2026-05-24T14:00:00Z",
        "timestamp_end": "2026-05-24T15:00:00Z",
        "session_duration_minutes": 60,
        "day_number": 13,
        "current_skill": "fopo"
      },
      "bio_updates": [
        {
          "category": "sport_career",
          "content": "Played professional basketball for 8 years before transitioning to coaching.",
          "source_quote": "I played pro ball for about eight years, then hung up my shoes.",
          "confidence": "explicit"
        }
      ],
      "dimension_updates": [
        {
          "dimension_number": 4,
          "dimension_name": "Fear",
          "pillar": "mind",
          "signal": "Fear of failure is the dominant fear, specifically tied to public perception after performance.",
          "evidence": "I don't care about losing — I care about what people think when I lose.",
          "direction": "deepening",
          "weight": "high"
        },
        {
          "dimension_number": 1,
          "dimension_name": "Identity & Self-Belief",
          "pillar": "mind",
          "signal": "Identity is still heavily tied to performance outcomes rather than process.",
          "evidence": "When I play well I feel like myself. Bad game and I don't know who I am.",
          "direction": "new_signal",
          "weight": "medium"
        }
      ],
      "session_brief": {
        "summary": "Deep exploration of FOPO and its roots in early athletic identity formation.",
        "emotional_arc": {
          "start": "defended, intellectual",
          "end": "open, some vulnerability",
          "shift": "cracked the intellectual armor; touched the emotional layer underneath"
        },
        "open_threads": [
          { "thread": "Explore the early memory of the critical coach — seems load-bearing", "priority": "follow_up_next_session" }
        ],
        "commitments": [
          { "commitment": "Notice FOPO moments without judgment this week", "timeframe": "7 days" }
        ]
      },
      "timeline_events": [
        {
          "event_type": "breakthrough",
          "date": "2026-05-24",
          "description": "First time person acknowledged FOPO by name and connected it to identity.",
          "dimensions_touched": [4, 1]
        }
      ],
      "conversation_log": {
        "date": "2026-05-24",
        "type": "deep_dive",
        "brief": "FOPO deep dive; breakthrough moment on identity-fear link."
      },
      "signal_flags": [
        {
          "flag_type": "avoidance_pattern",
          "description": "Uses intellectual analysis to avoid emotional contact with fear.",
          "evidence": "Every time we approached the feeling directly he pivoted to theory.",
          "severity": "monitor"
        }
      ],
      "coaches_journal": {
        "entry": "Something shifted today. You let me see past the analysis and into the feeling underneath. That takes courage. The fear you've been carrying — that people will think less of you when you struggle — is old and heavy. We're just beginning to look at it, and that's enough for today.",
        "dimensions_tagged": [4, 1, 12]
      },
      "program_state_update": {
        "skill_progress": {
          "skill_name": "FOPO",
          "phase_before": "awareness",
          "phase_after": "contact",
          "notes": "First genuine emotional contact with the fear. Good moment to consolidate before pushing deeper."
        },
        "practices_prescribed": ["FOPO noticing journal — 7 days"]
      },
      "management_updates": {
        "goals": [
          { "action": "created", "description": "Notice and log FOPO moments daily for 7 days without judgment" }
        ]
      }
    }
    """
}
