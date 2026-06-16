import Foundation

protocol AuthRefreshing: AnyObject {
    func refreshSession() async throws -> AuthResponse
}

final class APIClient: @unchecked Sendable {
    let baseURL: URL
    private let lock = NSLock()
    private var _session: URLSession
    private var session: URLSession {
        lock.lock(); defer { lock.unlock() }
        return _session
    }
    private let tokenStore: TokenStoring
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    weak var authRefresher: AuthRefreshing?

    init(baseURL: URL, session: URLSession? = nil, tokenStore: TokenStoring) {
        self.baseURL = baseURL
        self._session = session ?? URLSession(configuration: Self.makeConfiguration())
        self.tokenStore = tokenStore
        self.decoder = JSONDecoder.yeats
        self.encoder = JSONEncoder()
    }

    private static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return config
    }

    /// Recreate the underlying session to drop any stale (e.g. empty) DNS
    /// resolutions cached while the tunnel was coming up. Call after the VPN
    /// tunnel is confirmed connected so subsequent requests re-resolve hosts.
    func resetSession() {
        lock.lock()
        let old = _session
        _session = URLSession(configuration: Self.makeConfiguration())
        lock.unlock()
        old.finishTasksAndInvalidate()
    }

    func request<Response: Decodable>(_ endpoint: APIEndpoint) async throws -> Response {
        let body: Data? = endpoint.method == .post ? Data("{}".utf8) : nil
        return try await perform(endpoint, body: body)
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
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                throw CancellationError()
            }
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
            let envelope = try? decoder.decode(ServerErrorEnvelope.self, from: data)
            let message = envelope?.error?.message ?? envelope?.message ?? "Request failed (\(http.statusCode))."
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
    let error: ServerError?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case error, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try? container.decode(String.self, forKey: .message)
        if let obj = try? container.decode(ServerError.self, forKey: .error) {
            self.error = obj
        } else if let str = try? container.decode(String.self, forKey: .error) {
            self.error = ServerError(message: str)
        } else {
            self.error = nil
        }
    }
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
