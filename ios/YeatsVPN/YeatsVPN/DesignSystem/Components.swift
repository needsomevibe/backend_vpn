import SwiftUI

// MARK: - Glass surface

/// Applies a translucent material surface with a specular edge and depth shadow.
/// This is the building block for the app's glass look on iOS 17+.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = DS.cardRadius
    var strokeOpacity: Double = 1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(.ultraThinMaterial, in: shape)
            .overlay { shape.fill(DS.glassSheen) }
            .overlay { shape.strokeBorder(DS.glassStroke.opacity(strokeOpacity), lineWidth: 1) }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = DS.cardRadius, strokeOpacity: Double = 1) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }

    /// Ambient, state-tinted backdrop placed behind a screen's content.
    func ambientBackground(tint: Color = DS.blue) -> some View {
        background(AmbientBackground(tint: tint))
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    let content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .glassSurface(cornerRadius: DS.radius)
    }
}

// MARK: - Ambient background

/// Soft, slowly drifting color blobs behind frosted content — the "aurora" that
/// the glass surfaces refract. Re-tints smoothly when the connection state color changes.
struct AmbientBackground: View {
    var tint: Color = DS.blue
    @State private var drift = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            blob(tint.opacity(0.30), size: 360)
                .offset(x: drift ? -130 : -90, y: drift ? -250 : -200)

            blob(DS.cyan.opacity(0.24), size: 320)
                .offset(x: drift ? 150 : 110, y: drift ? -130 : -170)

            blob(tint.opacity(0.18), size: 300)
                .offset(x: drift ? 70 : 30, y: drift ? 330 : 390)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: drift)
        .animation(.easeInOut(duration: 0.7), value: tint)
        .onAppear { drift = true }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 90)
    }
}

// MARK: - Sonar rings

/// Expanding "sonar" rings used behind the connect button while the tunnel is
/// connecting or live. Hidden (and idle) otherwise.
struct ConnectionRings: View {
    let color: Color
    let isActive: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(animate ? 1.4 : 0.82)
                    .opacity(animate ? 0 : 0.55)
                    .animation(
                        .easeOut(duration: 2.6)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.85),
                        value: animate
                    )
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: isActive)
        .onAppear { animate = true }
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [DS.blue, DS.cyan], startPoint: .leading, endPoint: .trailing))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(DS.glassSheen)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: DS.blue.opacity(0.30), radius: 18, y: 10)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .glassSurface(cornerRadius: 16)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Subtle press feedback shared across custom buttons for a tactile, native feel.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Inputs

struct FormField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(DS.blue)
                .frame(width: 22)
            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(title.lowercased().contains("email") ? .emailAddress : .default)
                }
            }
            .font(.body.weight(.medium))
        }
        .padding(16)
        .glassSurface(cornerRadius: 18, strokeOpacity: 0.7)
    }
}

// MARK: - Status / banners

struct StatusPill: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? .green : .secondary)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((isActive ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LogoMark: View {
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [DS.blue, DS.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(DS.glassSheen)
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
        .frame(width: size, height: size)
        .shadow(color: DS.blue.opacity(0.3), radius: 24, y: 12)
    }
}
