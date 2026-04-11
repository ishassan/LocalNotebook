import Foundation
import OSLog

enum AppLogger {
    static let documents = Logger(subsystem: "com.ishassan.localnotebook", category: "documents")
    static let execution = Logger(subsystem: "com.ishassan.localnotebook", category: "execution")
    static let ui = Logger(subsystem: "com.ishassan.localnotebook", category: "ui")
}
