import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var animate = false

    var body: some View {
        VStack(spacing: 26) {
            LogoMark(size: 92)
                .scaleEffect(animate ? 1 : 0.86)
                .opacity(animate ? 1 : 0.2)
            VStack(spacing: 8) {
                Text("Remna")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Private. Fast. Quiet.")
                    .foregroundStyle(.secondary)
                    .font(.headline)
            }
            ProgressView()
                .controlSize(.large)
                .tint(DS.blue)
                .padding(.top, 16)
        }
        .task {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                animate = true
            }
            try? await Task.sleep(for: .milliseconds(450))
            await environment.bootstrap()
        }
    }
}
