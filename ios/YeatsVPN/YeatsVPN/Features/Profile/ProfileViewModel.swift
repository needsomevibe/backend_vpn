import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var user: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        self.user = environment.currentUser
    }

    var plan: Plan? { user?.subscription?.plan }
    var subscription: Subscription? { user?.subscription }
    var devices: [Device] { user?.devices ?? [] }

    var memberSince: String {
        user?.createdAt?.formatted(.dateTime.month(.wide).year()) ?? "Unknown"
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            user = try await environment.authService.me()
            environment.currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        await environment.logout()
    }
}
