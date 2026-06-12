import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

struct APIEndpoint {
    let path: String
    let method: HTTPMethod
    let requiresAuth: Bool

    static let register = APIEndpoint(path: "/auth/register", method: .post, requiresAuth: false)
    static let login = APIEndpoint(path: "/auth/login", method: .post, requiresAuth: false)
    static let apple = APIEndpoint(path: "/auth/apple", method: .post, requiresAuth: false)
    static let refresh = APIEndpoint(path: "/auth/refresh", method: .post, requiresAuth: false)
    static let me = APIEndpoint(path: "/me", method: .get, requiresAuth: true)
    static let vpnProfile = APIEndpoint(path: "/vpn/profile", method: .get, requiresAuth: true)
    static let vpnUsage = APIEndpoint(path: "/vpn/usage", method: .get, requiresAuth: true)
}
