# MasteryMemory — iOS Reference Implementation

Swift Package that maps the **Mastery Living Profile** to the **Hindsight memory API**. Hand this to engineers as a production-ready starting point.

---

## What this is

The Mastery coaching AI maintains a **Living Profile** for every user — a structured psychological portrait built up from every conversation. This package handles the two directions of that data flow:

- **Write path** — after every conversation the extraction LLM produces an `ExtractionPackage` (JSON); this package persists it to Hindsight in tagged, queryable form
- **Read path** — before every coaching session this package assembles and synthesizes the context the Coach AI needs

---

## Architecture

```
ExtractionPackage (from LLM)
        │
        ▼
LivingProfileService.persist(_:)
        │
        ▼
ProfileRetainService         ←── maps each layer to retain() calls
        │
        ▼
HindsightClient.retain()     ←── REST POST /banks/{bankId}/memory/retain


Before session:
LivingProfileService.buildSessionContext(query:budget:)
        │
        ├── ProfileRecallService.recall*()   → factual retrieval
        └── ProfileRecallService.reflect*()  → agentic synthesis
                │
                ▼
        CoachSessionContext.renderForPrompt()  → injected into system prompt
```

---

## The 9 Living Profile Layers

| Layer | What it holds | Hindsight tag |
|-------|---------------|---------------|
| 1 — Bio | Biographical facts (origin, career, family, personality) | `layer:bio` |
| 2 — 21 Dimensions | Psychological profile across 21 canonical dimensions | `layer:dimensions` + `dim:<1-21>` |
| 3 — Recent Sessions | Session briefs, open threads, commitments, practice responses | `layer:sessions` |
| 4 — Timeline | Life events, milestones, breakthroughs, conversation log | `layer:timeline` |
| 5 — Signals | Incongruence, avoidance, distress, breakthrough flags | `layer:signals` |
| 6 — Coach's Journal | Coach-voice narrative written after every session | `layer:journal` |
| 7 — Program State | Which skill arc, which phase, practices prescribed | `layer:program` |
| 8 — Management | Goals, habits, to-dos and their lifecycle actions | `layer:management` |
| 9 — Architecture | Synthesized via `reflect()` — not stored as raw facts | (reflect query) |

---

## The 21 Profile Dimensions

Canonical numbers never change. The extraction prompt references them by number.

| # | Dimension | Pillar |
|---|-----------|--------|
| 1 | Identity & Self-Belief | Mind |
| 2 | Vision/Purpose | Mind |
| 3 | Mental State | Mind |
| 4 | Fear | Mind |
| 5 | Self-Talk | Mind |
| 6 | Pressure/Competition | Mind |
| 7 | Motivation/Drive | Mind |
| 8 | Spirituality or Religion | Soul |
| 9 | Process | Craft |
| 10 | Performance | Craft |
| 11 | Goals | Mind |
| 12 | Shame & Vulnerability | Soul |
| 13 | Setbacks | Mind |
| 14 | Relationships | Soul |
| 15 | Craft/Skill Development | Craft |
| 16 | Body/Physical State | Body |
| 17 | Family & Origin | Soul |
| 18 | Growth | Mind |
| 19 | Life Outside Performance | Soul |
| 20 | Relevant Right Now | Mind |
| 21 | Money & Security | Soul |

---

## Hindsight bank structure

- **One bank per user** — `bankId = userId`
- **`observation_scopes: per_tag`** — Hindsight builds observations scoped to each tag, enabling tag-filtered recall
- **`document_id` for idempotency** — every write is an upsert; re-running extraction for the same session is safe

### document_id conventions

| Layer | document_id format | update_mode |
|-------|--------------------|-------------|
| Bio | `bio:<userId>:<category>` | replace |
| Dimensions | `dim:<userId>:<dimensionNumber>` | replace |
| Session brief | `brief:<sessionId>` | replace |
| Coach's Journal | `journal:<userId>:latest` | replace |
| Signal flags | `flag:<sessionId>:<index>` | replace |
| Program state | `program:<userId>` | replace |
| Management goals | `mgmt-goals:<userId>` | replace |
| Management habits | `mgmt-habits:<userId>` | replace |
| Management todos | `mgmt-todos:<userId>` | replace |
| Timeline events | `timeline:<sessionId>:<index>` | replace |
| Conversation log | `convlog:<sessionId>` | replace |

---

## Integration

### 1. Add the package

In Xcode: **File → Add Package Dependencies** → paste the repo URL.  
In `Package.swift`: add `.package(url: "...", from: "1.0.0")` and `"MasteryMemory"` to your target dependencies.

### 2. Configure once at startup

```swift
import MasteryMemory

// AppDelegate or DI container
let config = HindsightConfig(
    baseURL: "https://api.vectorize.io/v1/default",   // from Vectorize Cloud dashboard
    apiKey: Keychain.read("hindsight-api-key")         // never hardcode
)
let profile = LivingProfileService(config: config, userId: currentUser.id)
```

### 3. Persist after every conversation

```swift
// Triggered by pom_data_package_ready event
func onExtractionComplete(jsonData: Data) async throws {
    let package = try JSONDecoder().decode(ExtractionPackage.self, from: jsonData)
    try await profile.persist(package)
}
```

### 4. Build context before every session

```swift
func prepareCoachingSession(focus: String) async throws -> String {
    let context = try await profile.buildSessionContext(
        query: focus,
        budget: .mid
    )
    return context.renderForPrompt()   // inject into system prompt
}
```

---

## Extraction trigger

The extraction LLM runs once after every conversation, triggered by `pom_data_package_ready`. It produces a single `ExtractionPackage` JSON object. Engineers: the extraction prompt is maintained separately — this package only handles the Swift-side persistence and retrieval.

**Empty fields in the extraction package are correct.** Most sessions will only touch a few layers. Do not treat `nil` arrays as errors.

**Contradictions are data.** When `direction == .contradiction`, store the record as-is. Do not resolve or merge with existing profile data. Contradictions are surfaced to the Coach as tension to explore.

---

## Engineers: verify before shipping

- [ ] Confirm Hindsight REST paths from Vectorize Cloud dashboard (`/banks/{bankId}/memory/retain` etc.)
- [ ] Confirm `observation_scopes: per_tag` is supported on your Hindsight plan
- [ ] Store API key in Keychain — never in source or UserDefaults
- [ ] Add retry logic / exponential backoff to `HindsightClient.post()`
- [ ] Add request timeout to `URLRequest` (suggest 30s)
- [ ] Decide whether to call `retain()` async (fire-and-forget after session) or await
- [ ] Wire `pom_data_package_ready` event to `LivingProfileService.persist(_:)`
- [ ] Surface `.escalate` severity flags to the Clinical Profiling Agent
- [ ] Add Xcode build scheme and CI test target

---

## File map

```
Sources/MasteryMemory/
  HindsightClient.swift       — REST client (retain / recall / reflect)
  ExtractionModels.swift      — Codable models matching Universal Extraction Schema
  ProfileRetainService.swift  — maps ExtractionPackage layers to retain() calls
  ProfileRecallService.swift  — assembles pre-session context from recall() + reflect()
  LivingProfileService.swift  — top-level orchestrator

Tests/MasteryMemoryTests/
  ExtractionModelsTests.swift — JSON decode round-trip tests
```
