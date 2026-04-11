import Foundation

enum UITestHarness {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    static var shouldResetStorage: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-reset")
    }
}
