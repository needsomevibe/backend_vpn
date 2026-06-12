import Foundation

protocol AuthRefreshing: AnyObject {
    func refreshSession() async throws -> AuthResponse
}

final class APIClient: @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStoring
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    weak var authRefresher: AuthRefreshing?

    init(baseURL: URL, session: URLSession = .shared, tokenStore: TokenStoring) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
        self.decoder = JSONDecoder.yeats
        self.encoder = JSONEncoder()
    }

    func request<Response: Decodable>(_ endpoint: APIEndpoint) async throws -> Response {
        try await perform(endpoint, body: nil)
    }

    func request<Body: Encodable, Response: Decodable>(_ endpoint: APIEndpoint, body: Body) async throws -> Response {
        let data = try encoder.encode(body)
        return try await perform(endpoint, body: data)
    }

    private func perform<Response: Decodable>(_ endpoint: APIEndpoint, body: Data?) async throws -> Response {
        var request = try await buildURLRequest(endpoint, body: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("Invalid server response.")
            }
            if http.statusCode == 401, endpoint.requiresAuth {
                _ = try await authRefresher?.refreshSession()
                request = try await buildURLRequest(endpoint, body: body)
                let (retryData, retryResponse) = try await session.data(for: request)
                return try decode(retryData, response: retryResponse)
            }
            return try decode(data, response: http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func buildURLRequest(_ endpoint: APIEndpoint, body: Data?) async throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = body
        if endpoint.requiresAuth {
            guard let token = await tokenStore.accessToken() else {
                throw APIError.missingToken
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func decode<Response: Decodable>(_ data: Data, response: URLResponse) throws -> Response {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Invalid server response.")
        }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? decoder.decode(ServerErrorEnvelope.self, from: data).error.message) ?? "Request failed."
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.server(status: http.statusCode, message: message)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }
}

private struct ServerErrorEnvelope: Decodable {
    let error: ServerError
}

private struct ServerError: Decodable {
    let message: String
}

extension JSONDecoder {
    static var yeats: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return decoder
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
