import XCTest
@testable import LocalNotebook

final class NotebookCodecTests: XCTestCase {
    func testRoundTripPreservesUnknownFieldsAndCellIDs() throws {
        let json = """
        {
          "cells": [
            {
              "cell_type": "code",
              "id": "abc_123",
              "metadata": {"custom": {"nested": true}},
              "execution_count": 3,
              "outputs": [
                {
                  "output_type": "display_data",
                  "data": {"text/plain": "42"},
                  "metadata": {},
                  "vendor_field": "keep-me"
                }
              ],
              "source": ["x = 42\\n", "x"],
              "vendor_cell_field": "keep-this"
            }
          ],
          "metadata": {"vendor_meta": {"enabled": true}},
          "nbformat": 4,
          "nbformat_minor": 5,
          "vendor_root_field": "preserve"
        }
        """.data(using: .utf8)!

        let codec = NotebookCodec()
        let notebook = try codec.decode(json)
        let encoded = try codec.encode(notebook)
        let decodedAgain = try codec.decode(encoded)

        XCTAssertEqual(decodedAgain.cells.first?.id, "abc_123")
        XCTAssertEqual(decodedAgain.additionalFields["vendor_root_field"], .string("preserve"))
        XCTAssertEqual(decodedAgain.metadata["vendor_meta"]?.objectValue?["enabled"], .bool(true))
        XCTAssertEqual(decodedAgain.cells.first?.additionalFields["vendor_cell_field"], .string("keep-this"))
        XCTAssertEqual(decodedAgain.cells.first?.outputs.first?.additionalFields["vendor_field"], .string("keep-me"))
    }

    func testAttachmentsAndStringSourceArePreserved() throws {
        let notebook = NotebookDocument(
            metadata: [:],
            cells: [
                NotebookCell(
                    id: "markdown_1",
                    cellType: .markdown,
                    source: .string("![inline](attachment:test.png)"),
                    attachments: ["test.png": ["image/png": "abc123"]]
                )
            ]
        )

        let codec = NotebookCodec()
        let roundTrip = try codec.decode(codec.encode(notebook))

        XCTAssertEqual(roundTrip.cells.first?.attachments["test.png"]?["image/png"], "abc123")
        XCTAssertEqual(roundTrip.cells.first?.source.joined, "![inline](attachment:test.png)")
    }
}
