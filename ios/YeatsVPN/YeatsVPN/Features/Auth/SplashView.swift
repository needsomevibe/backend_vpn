import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var appear = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DS.blue)
                    .frame(width: 180, height: 180)
                    .blur(radius: 60)
                    .opacity(appear ? 0.45 : 0)

                ConnectionRings(color: DS.blue, isActive: true)
                    .frame(width: 172, height: 172)

                LogoMark(size: 96)
                    .scaleEffect(appear ? 1 : 0.7)
                    .opacity(appear ? 1 : 0)
            }

            VStack(spacing: 8) {
                Text("Remna")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Private. Fast. Quiet.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 14)

            Spacer()

            HStack(spacing: 10) {
                ProgressView()
                    .tint(DS.blue)
                Text("Preparing secure tunnel")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassSurface(cornerRadius: 22, strokeOpacity: 0.7)
            .opacity(appear ? 1 : 0)
            .padding(.bottom, 60)
        }
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                appear = true
            }
            try? await Task.sleep(for: .milliseconds(550))
            await environment.bootstrap()
        }
    }
}
