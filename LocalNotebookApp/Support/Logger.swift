import Foundation
import OSLog

enum AppLogger {
    static let documents = Logger(subsystem: "com.localnotebook.ios", category: "documents")
    static let execution = Logger(subsystem: "com.localnotebook.ios", category: "execution")
    static let ui = Logger(subsystem: "com.localnotebook.ios", category: "ui")
}
