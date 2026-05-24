import Foundation

// MARK: - Configuration

/// Configure once at app startup, e.g. in AppDelegate or a DI container.
public struct HindsightConfig {
    /// Base URL of your Hindsight Cloud instance.
    /// Engineers: get this from your Vectorize Cloud dashboard.
    /// Example: "https://api.vectorize.io/v1/default"
    public let baseURL: String

    /// API key for Hindsight. Store in Keychain in production — never in source.
    public let apiKey: String

    public init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

// MARK: - Request / Response Types

public struct RetainItem: Encodable {
    public let content: String
    public let context: String?
    public let timestamp: String?         // ISO 8601
    public let documentId: String?        // for idempotent upserts
    public let updateMode: String?        // "replace" | "append"
    public let tags: [String]?
    public let metadata: [String: String]?
    public let observationScopes: String? // "per_tag" | "all_combinations" | "combined"

    enum CodingKeys: String, CodingKey {
        case content, context, timestamp, tags, metadata
        case documentId       = "document_id"
        case updateMode       = "update_mode"
        case observationScopes = "observation_scopes"
    }

    public init(
        content: String,
        context: String? = nil,
        timestamp: String? = nil,
        documentId: String? = nil,
        updateMode: String? = "replace",
        tags: [String]? = nil,
        metadata: [String: String]? = nil,
        observationScopes: String? = "combined"
    ) {
        self.content = content
        self.context = context
        self.timestamp = timestamp
        self.documentId = documentId
        self.updateMode = updateMode
        self.tags = tags
        self.metadata = metadata
        self.observationScopes = observationScopes
    }
}

public struct RetainRequest: Encodable {
    public let items: [RetainItem]
    public let async: Bool?

    public init(items: [RetainItem], async: Bool? = nil) {
        self.items = items
        self.async = async
    }
}

public struct RetainResponse: Decodable {
    public let success: Bool
    public let bankId: String
    public let itemsCount: Int
    public let isAsync: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case bankId      = "bank_id"
        case itemsCount  = "items_count"
        case isAsync     = "async"
    }
}

public struct RecallRequest: Encodable {
    public let query: String
    public let budget: String?     // "low" | "mid" | "high"
    public let maxTokens: Int?
    public let tags: [String]?
    public let tagsMatch: String?  // "any" | "any_strict" | "all" | "all_strict"
    public let types: [String]?    // ["world", "experience", "observation"]

    enum CodingKeys: String, CodingKey {
        case query, budget, tags, types
        case maxTokens = "max_tokens"
        case tagsMatch = "tags_match"
    }

    public init(
        query: String,
        budget: String? = "mid",
        maxTokens: Int? = 4096,
        tags: [String]? = nil,
        tagsMatch: String? = "any_strict",
        types: [String]? = nil
    ) {
        self.query = query
        self.budget = budget
        self.maxTokens = maxTokens
        self.tags = tags
        self.tagsMatch = tagsMatch
        self.types = types
    }
}

public struct RecallFact: Decodable, Sendable {
    public let id: String
    public let text: String
    public let type: String
    public let context: String?
    public let tags: [String]?
    public let metadata: [String: String]?
    public let occurredStart: String?
    public let documentId: String?

    enum CodingKeys: String, CodingKey {
        case id, text, type, context, tags, metadata
        case occurredStart = "occurred_start"
        case documentId    = "document_id"
    }
}

public struct RecallResponse: Decodable {
    public let results: [RecallFact]
}

public struct ReflectRequest: Encodable {
    public let query: String
    public let budget: String?
    public let maxTokens: Int?
    public let tags: [String]?
    public let tagsMatch: String?

    enum CodingKeys: String, CodingKey {
        case query, budget, tags
        case maxTokens = "max_tokens"
        case tagsMatch = "tags_match"
    }

    public init(
        query: String,
        budget: String? = "mid",
        maxTokens: Int? = 4096,
        tags: [String]? = nil,
        tagsMatch: String? = "any_strict"
    ) {
        self.query = query
        self.budget = budget
        self.maxTokens = maxTokens
        self.tags = tags
        self.tagsMatch = tagsMatch
    }
}

public struct ReflectResponse: Decodable {
    public let text: String
}

// MARK: - Bank Configuration

public struct CreateBankRequest: Encodable {
    public let retainMission: String?
    public let observationsMission: String?
    public let reflectMission: String?
    public let dispositionSkepticism: Int?
    public let dispositionLiteralism: Int?
    public let dispositionEmpathy: Int?

    enum CodingKeys: String, CodingKey {
        case retainMission        = "retain_mission"
        case observationsMission  = "observations_mission"
        case reflectMission       = "reflect_mission"
        case dispositionSkepticism = "disposition_skepticism"
        case dispositionLiteralism = "disposition_literalism"
        case dispositionEmpathy   = "disposition_empathy"
    }

    public init(
        retainMission: String? = nil,
        observationsMission: String? = nil,
        reflectMission: String? = nil,
        dispositionSkepticism: Int? = nil,
        dispositionLiteralism: Int? = nil,
        dispositionEmpathy: Int? = nil
    ) {
        self.retainMission        = retainMission
        self.observationsMission  = observationsMission
        self.reflectMission       = reflectMission
        self.dispositionSkepticism = dispositionSkepticism
        self.dispositionLiteralism = dispositionLiteralism
        self.dispositionEmpathy   = dispositionEmpathy
    }
}

private struct EmptyDecodable: Decodable {}

// MARK: - Client

public actor HindsightClient {
    private let config: HindsightConfig
    private let session: URLSession

    public init(config: HindsightConfig) {
        self.config = config
        self.session = URLSession.shared
    }

    // MARK: Retain

    public func retain(bankId: String, items: [RetainItem], async isAsync: Bool = false) async throws -> RetainResponse {
        let body = RetainRequest(items: items, async: isAsync ? true : nil)
        return try await post(path: "/banks/\(bankId)/memory/retain", body: body)
    }

    // MARK: Recall

    public func recall(bankId: String, request: RecallRequest) async throws -> RecallResponse {
        return try await post(path: "/banks/\(bankId)/memory/recall", body: request)
    }

    // MARK: Reflect

    public func reflect(bankId: String, request: ReflectRequest) async throws -> ReflectResponse {
        return try await send(method: "POST", path: "/banks/\(bankId)/memory/reflect", body: request)
    }

    // MARK: Bank

    /// Upserts the bank and sets missions + disposition in one call.
    /// Call once at app startup (idempotent — safe to re-run).
    public func configureBank(bankId: String, config: CreateBankRequest) async throws {
        _ = try await send(method: "PUT", path: "/banks/\(bankId)", body: config) as EmptyDecodable
    }

    // MARK: Private

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body
    ) async throws -> Response {
        guard let url = URL(string: config.baseURL + path) else {
            throw HindsightError.invalidURL(config.baseURL + path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw HindsightError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        return try await send(method: "POST", path: path, body: body)
    }
}

public enum HindsightError: Error, LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid Hindsight URL: \(url)"
        case .httpError(let code, let body): return "Hindsight HTTP \(code): \(body)"
        }
    }
}
