import SwiftUI

enum DS {
    static let blue = Color(red: 0.13, green: 0.43, blue: 1.0)
    static let cyan = Color(red: 0.20, green: 0.78, blue: 1.0)
    static let ink = Color.primary
    static let muted = Color.secondary

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                Color(uiColor: .secondarySystemBackground),
                blue.opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardFill: Color {
        Color(uiColor: .secondarySystemBackground).opacity(0.72)
    }

    static let radius: CGFloat = 28
    static let cardRadius: CGFloat = 24
    static let tileRadius: CGFloat = 22

    /// Specular top-light edge that sells the glass illusion on material surfaces.
    static var glassStroke: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.55), .white.opacity(0.12), .white.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Soft sheen layered over a material to add the wet-glass highlight.
    static var glassSheen: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.18), .clear, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension Date {
    var shortDisplay: String {
        formatted(.dateTime.month(.abbreviated).day().year())
    }
}

extension Double {
    var gbDisplay: String {
        "\(String(format: "%.1f", self)) GB"
    }
}
