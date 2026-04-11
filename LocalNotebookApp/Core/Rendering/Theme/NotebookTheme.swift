import SwiftUI

enum NotebookTheme {
    static let cardCornerRadius: CGFloat = 18
    static let accent = Color(red: 0.18, green: 0.56, blue: 0.98)

    static func background(for colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.01, blue: 0.02),
                    Color(red: 0.03, green: 0.04, blue: 0.06),
                    Color(red: 0.01, green: 0.01, blue: 0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.97, blue: 0.94), Color(red: 0.92, green: 0.95, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func panelFill(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.04)
        default:
            Color.white.opacity(0.7)
        }
    }
}
