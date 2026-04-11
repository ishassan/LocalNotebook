import XCTest
@testable import LocalNotebook

final class MarkdownRenderingTests: XCTestCase {
    func testMarkdownHTMLRendererPreservesHeadingAndListStructure() {
        let markdown = """
        # Week 1: some content

        #Table of contents

        - [1 - Object Storage](#1)
          - [1.1 - Configure S3 Bucket](#1-1)
        """

        let html = MarkdownHTMLRenderer.renderBlocks(markdown)

        XCTAssertTrue(html.contains("<h1>Week 1: some content</h1>"))
        XCTAssertTrue(html.contains("<p>#Table of contents</p>"))
        XCTAssertTrue(html.contains("<ul><li><a href=\"#1\">1 - Object Storage</a><ul><li><a href=\"#1-1\">1.1 - Configure S3 Bucket</a>"))
    }

    func testMarkdownHTMLRendererStripsHiddenAnchorTags() {
        let markdown = """
        <a id='1'></a>
        ## Exercise 1
        """

        let prepared = MarkdownHTMLRenderer.prepare(markdown)
        let html = MarkdownHTMLRenderer.renderBlocks(markdown)

        XCTAssertEqual(prepared.anchorIDs, ["1"])
        XCTAssertFalse(prepared.sanitizedMarkdown.contains("<a id='1'></a>"))
        XCTAssertFalse(html.contains("&lt;a id"))
        XCTAssertTrue(html.contains("<h2>Exercise 1</h2>"))
    }
}
