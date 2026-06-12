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
