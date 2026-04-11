import SwiftUI
import WebKit

struct MarkdownPreviewView: View {
    let markdown: String
    let onOpenAnchor: ((String) -> Void)?

    init(markdown: String, onOpenAnchor: ((String) -> Void)? = nil) {
        self.markdown = markdown
        self.onOpenAnchor = onOpenAnchor
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AutoSizingHTMLView(
            html: MarkdownHTMLRenderer.htmlDocument(
                for: markdown,
                colorScheme: colorScheme
            ),
            onOpenAnchor: onOpenAnchor
        )
    }
}

private struct AutoSizingHTMLView: UIViewRepresentable {
    let html: String
    let onOpenAnchor: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "anchorClick")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                document.addEventListener('click', function(event) {
                  const anchor = event.target.closest('a');
                  if (!anchor) return;
                  const href = anchor.getAttribute('href') || '';
                  if (!href.startsWith('#')) return;
                  event.preventDefault();
                  const fragment = href.slice(1);
                  window.webkit.messageHandlers.anchorClick.postMessage(fragment);
                });
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onOpenAnchor = onOpenAnchor
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        uiView.loadHTMLString(html, baseURL: nil)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.scrollView.contentSize.width,
            height: max(1, context.coordinator.contentHeight)
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var lastHTML = ""
        var contentHeight: CGFloat = 1
        var onOpenAnchor: ((String) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] value, _ in
                guard let self else { return }
                let measuredHeight = (value as? NSNumber).map(CGFloat.init(truncating:)) ?? 1
                contentHeight = max(1, ceil(measuredHeight))
                webView.invalidateIntrinsicContentSize()
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "anchorClick",
                  let fragment = message.body as? String,
                  !fragment.isEmpty else { return }
            onOpenAnchor?(fragment)
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if let fragment = url.fragment, !fragment.isEmpty {
                onOpenAnchor?(fragment)
                decisionHandler(.cancel)
                return
            }

            if url.scheme != "about" {
                Task { @MainActor in
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

enum MarkdownHTMLRenderer {
    struct PreparedMarkdown {
        let sanitizedMarkdown: String
        let anchorIDs: [String]
    }

    static func htmlDocument(for markdown: String, colorScheme: ColorScheme) -> String {
        let prepared = prepare(markdown)
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            :root {
              color-scheme: \(colorScheme == .dark ? "dark" : "light");
              --text: \(colorScheme == .dark ? "#F2F4F8" : "#111827");
              --muted: \(colorScheme == .dark ? "#C6CFDB" : "#374151");
              --link: \(colorScheme == .dark ? "#82CFFF" : "#0B6AAE");
              --code-bg: \(colorScheme == .dark ? "rgba(255,255,255,0.08)" : "rgba(17,24,39,0.06)");
              --code-text: \(colorScheme == .dark ? "#F8FAFC" : "#111827");
              --rule: \(colorScheme == .dark ? "rgba(255,255,255,0.12)" : "rgba(17,24,39,0.12)");
            }
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
            }
            body {
              color: var(--text);
              font: -apple-system-body;
              line-height: 1.55;
              overflow-wrap: break-word;
            }
            h1, h2, h3, h4, h5, h6 {
              color: var(--text);
              line-height: 1.2;
              margin: 0 0 0.6em;
            }
            h1 { font-size: 1.7em; }
            h2 { font-size: 1.45em; }
            h3 { font-size: 1.25em; }
            h4, h5, h6 { font-size: 1.05em; }
            p {
              margin: 0 0 0.9em;
            }
            ul, ol {
              margin: 0 0 0.9em 1.25em;
              padding: 0;
            }
            li {
              margin: 0.2em 0;
            }
            li > ul, li > ol {
              margin-top: 0.35em;
              margin-bottom: 0.35em;
            }
            a {
              color: var(--link);
              text-decoration: none;
            }
            code {
              background: var(--code-bg);
              color: var(--code-text);
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.92em;
              padding: 0.1em 0.3em;
              border-radius: 6px;
            }
            pre {
              background: var(--code-bg);
              color: var(--code-text);
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.92em;
              line-height: 1.45;
              padding: 0.8em 0.95em;
              border-radius: 12px;
              overflow-x: auto;
              white-space: pre-wrap;
              margin: 0 0 0.9em;
            }
            pre code {
              background: transparent;
              padding: 0;
            }
            hr {
              border: none;
              border-top: 1px solid var(--rule);
              margin: 1em 0;
            }
            blockquote {
              margin: 0 0 0.9em;
              padding-left: 0.9em;
              border-left: 3px solid var(--rule);
              color: var(--muted);
            }
          </style>
        </head>
        <body>\(renderBlocks(prepared.sanitizedMarkdown, isPrepared: true))</body>
        </html>
        """
    }

    static func renderBlocks(_ markdown: String) -> String {
        renderBlocks(markdown, isPrepared: false)
    }

    static func anchorIDs(in markdown: String) -> [String] {
        prepare(markdown).anchorIDs
    }

    static func prepare(_ markdown: String) -> PreparedMarkdown {
        guard let regex = try? NSRegularExpression(pattern: "(?i)<a\\s+(?:id|name)\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]\\s*>\\s*</a>") else {
            return PreparedMarkdown(sanitizedMarkdown: markdown, anchorIDs: [])
        }

        let source = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else {
            return PreparedMarkdown(sanitizedMarkdown: markdown, anchorIDs: [])
        }

        var sanitized = markdown
        var anchorIDs: [String] = []
        for match in matches.reversed() {
            let fullRange = match.range(at: 0)
            let idRange = match.range(at: 1)
            if let swiftIDRange = Range(idRange, in: markdown) {
                anchorIDs.insert(String(markdown[swiftIDRange]), at: 0)
            }
            if let swiftFullRange = Range(fullRange, in: sanitized) {
                sanitized.replaceSubrange(swiftFullRange, with: "")
            }
        }

        return PreparedMarkdown(sanitizedMarkdown: sanitized, anchorIDs: anchorIDs)
    }

    private static func renderBlocks(_ markdown: String, isPrepared: Bool) -> String {
        let prepared = isPrepared ? PreparedMarkdown(sanitizedMarkdown: markdown, anchorIDs: []) : prepare(markdown)
        let sanitizedLines = prepared.sanitizedMarkdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var html: [String] = []
        var paragraphLines: [String] = []
        var listStack: [String] = []
        var codeFenceLanguage: String?
        var codeFenceLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let content = paragraphLines
                .map { renderInline($0) }
                .joined(separator: "<br>")
            html.append("<p>\(content)</p>")
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func closeLists(to depth: Int = 0) {
            while listStack.count > depth {
                html.append("</li></\(listStack.removeLast())>")
            }
        }

        for line in sanitizedLines {
            if codeFenceLanguage != nil {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    let languageClass = codeFenceLanguage?.isEmpty == false ? " class=\"language-\(escapeHTML(codeFenceLanguage!))\"" : ""
                    html.append("<pre><code\(languageClass)>\(escapeHTML(codeFenceLines.joined(separator: "\n")))</code></pre>")
                    codeFenceLanguage = nil
                    codeFenceLines.removeAll(keepingCapacity: true)
                } else {
                    codeFenceLines.append(line)
                }
                continue
            }

            if let fence = parseCodeFence(line) {
                flushParagraph()
                closeLists()
                codeFenceLanguage = fence
                codeFenceLines.removeAll(keepingCapacity: true)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                closeLists()
                html.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                closeLists()
                html.append("<hr>")
                continue
            }

            if let quote = parseBlockquote(line) {
                flushParagraph()
                closeLists()
                html.append("<blockquote>\(renderInline(quote))</blockquote>")
                continue
            }

            if let listItem = parseListItem(line) {
                flushParagraph()
                let targetDepth = listItem.depth + 1

                while listStack.count > targetDepth {
                    html.append("</li></\(listStack.removeLast())>")
                }

                if listStack.count == targetDepth {
                    if listStack.last == listItem.type {
                        html.append("</li><li>")
                    } else {
                        html.append("</li></\(listStack.removeLast())>")
                        html.append("<\(listItem.type)><li>")
                        listStack.append(listItem.type)
                    }
                } else {
                    while listStack.count < targetDepth {
                        html.append("<\(listItem.type)><li>")
                        listStack.append(listItem.type)
                    }
                }

                html.append(renderInline(listItem.text))
                continue
            }

            closeLists()
            paragraphLines.append(trimmed)
        }

        if codeFenceLanguage != nil {
            html.append("<pre><code>\(escapeHTML(codeFenceLines.joined(separator: "\n")))</code></pre>")
        }

        flushParagraph()
        closeLists()
        return html.joined()
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let content = trimmed.dropFirst(hashes.count)
        guard content.first == " " else { return nil }
        return (hashes.count, content.trimmingCharacters(in: .whitespaces))
    }

    private static func parseCodeFence(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    private static func parseBlockquote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    private static func parseListItem(_ line: String) -> (depth: Int, type: String, text: String)? {
        let leadingSpaces = line.prefix { $0 == " " }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return (leadingSpaces / 2, "ul", String(trimmed.dropFirst(2)))
        }

        let scalars = Array(trimmed)
        var digits = 0
        while digits < scalars.count, scalars[digits].isNumber {
            digits += 1
        }
        guard digits > 0,
              digits + 1 < scalars.count,
              scalars[digits] == ".",
              scalars[digits + 1] == " " else {
            return nil
        }

        return (leadingSpaces / 2, "ol", String(trimmed.dropFirst(digits + 2)))
    }

    private static func renderInline(_ text: String) -> String {
        var rendered = escapeHTML(text)
        var codeSpans: [String] = []

        rendered = replacing(pattern: "`([^`]+)`", in: rendered) { match in
            let placeholder = "__CODE_SPAN_\(codeSpans.count)__"
            codeSpans.append("<code>\(match[1])</code>")
            return placeholder
        }

        rendered = replacing(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", in: rendered) { match in
            "<a href=\"\(match[2])\">\(match[1])</a>"
        }

        rendered = replacing(pattern: "\\*\\*([^*]+)\\*\\*", in: rendered) { match in
            "<strong>\(match[1])</strong>"
        }

        rendered = replacing(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", in: rendered) { match in
            "<em>\(match[1])</em>"
        }

        for (index, codeSpan) in codeSpans.enumerated() {
            rendered = rendered.replacingOccurrences(of: "__CODE_SPAN_\(index)__", with: codeSpan)
        }

        return rendered
    }

    private static func replacing(
        pattern: String,
        in input: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return input
        }

        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        guard !matches.isEmpty else { return input }

        var result = input
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            var groups: [String] = []
            for index in 0..<match.numberOfRanges {
                if let groupRange = Range(match.range(at: index), in: result) {
                    groups.append(String(result[groupRange]))
                } else {
                    groups.append("")
                }
            }
            result.replaceSubrange(range, with: transform(groups))
        }
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
