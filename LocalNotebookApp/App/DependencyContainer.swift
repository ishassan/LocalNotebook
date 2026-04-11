import Foundation

@MainActor
final class DependencyContainer {
    let appSession = AppSessionStore()
}
