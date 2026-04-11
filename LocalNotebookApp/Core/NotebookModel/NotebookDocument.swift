import Foundation

struct NotebookDocument: Hashable, Sendable {
    var nbformat: Int
    var nbformatMinor: Int
    var metadata: [String: JSONValue]
    var cells: [NotebookCell]
    var additionalFields: [String: JSONValue]

    init(
        nbformat: Int = 4,
        nbformatMinor: Int = 5,
        metadata: [String: JSONValue] = [:],
        cells: [NotebookCell] = [],
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.nbformat = nbformat
        self.nbformatMinor = nbformatMinor
        self.metadata = metadata
        self.cells = cells
        self.additionalFields = additionalFields
    }

    static func empty(named title: String = "Untitled") -> NotebookDocument {
        NotebookDocument(
            metadata: [
                "kernelspec": .object([
                    "display_name": .string("Python 3"),
                    "language": .string("python"),
                    "name": .string("python3")
                ]),
                "language_info": .object([
                    "name": .string("python")
                ]),
                "title": .string(title)
            ],
            cells: [
                NotebookCell(cellType: .markdown, source: .string("# \(title)\n")),
                NotebookCell(cellType: .code, source: .string("print('Hello from LocalNotebook')"))
            ]
        )
    }

    var jsonObject: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "nbformat": .int(nbformat),
            "nbformat_minor": .int(nbformatMinor),
            "metadata": .object(metadata),
            "cells": .array(cells.map { .object($0.jsonObject) })
        ]
        additionalFields.forEach { object[$0.key] = $0.value }
        return object
    }
}
