import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case missingToken
    case unauthorized
    case server(status: Int, message: String)
    case decoding(String)
    case transport(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid server URL."
        case .missingToken: "Please sign in again."
        case .unauthorized: "Your session has expired."
        case let .server(_, message): message
        case let .decoding(message): "Could not read server response: \(message)"
        case let .transport(message): message
        case .offline: "You appear to be offline."
        }
    }
}
