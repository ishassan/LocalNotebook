import SwiftUI

enum NotebookTheme {
    static let cardCornerRadius: CGFloat = 18
    static let accent = Color(red: 0.06, green: 0.42, blue: 0.73)
    static let warmBackground = LinearGradient(
        colors: [Color(red: 0.98, green: 0.97, blue: 0.94), Color(red: 0.92, green: 0.95, blue: 0.99)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
