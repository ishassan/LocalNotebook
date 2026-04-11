import Foundation

struct PythonPackage: Identifiable, Hashable, Sendable {
    enum Segment: String, CaseIterable, Identifiable {
        case all = "All"
        case pinned = "Pinned"
        case user = "User"

        var id: String { rawValue }
    }

    let name: String
    let version: String
    let summary: String
    let isUserVisible: Bool

    var id: String { name }
}

enum PythonPackageCatalog {
    static let bundled: [PythonPackage] = [
        PythonPackage(
            name: "matplotlib",
            version: "Lite",
            summary: "Lightweight plotting compatibility layer for charts and figures.",
            isUserVisible: true
        ),
        PythonPackage(
            name: "packaging",
            version: "25.0",
            summary: "Core utilities for Python package versions, specifiers, and metadata.",
            isUserVisible: true
        ),
        PythonPackage(
            name: "pyparsing",
            version: "3.2.5",
            summary: "Parsing library used by packaged scientific and notebook tooling.",
            isUserVisible: true
        ),
        PythonPackage(
            name: "python-dateutil",
            version: "2.9.0.post0",
            summary: "Date and time helpers that extend Python's standard datetime support.",
            isUserVisible: true
        ),
        PythonPackage(
            name: "six",
            version: "1.17.0",
            summary: "Compatibility helpers used by several bundled Python dependencies.",
            isUserVisible: true
        )
    ]
}
