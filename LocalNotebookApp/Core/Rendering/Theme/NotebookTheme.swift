import SwiftUI

enum NotebookTheme {
    static let cardCornerRadius: CGFloat = 18
    static let accent = Color(red: 0.06, green: 0.42, blue: 0.73)

    static func background(for colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.13),
                    Color(red: 0.11, green: 0.15, blue: 0.22),
                    Color(red: 0.06, green: 0.09, blue: 0.14)
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
            Color.white.opacity(0.08)
        default:
            Color.white.opacity(0.7)
        }
    }
}
