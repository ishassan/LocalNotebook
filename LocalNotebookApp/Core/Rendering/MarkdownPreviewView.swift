import SwiftUI
import UIKit

struct MarkdownPreviewView: View {
    let markdown: String
    let onOpenAnchor: ((String) -> Void)?

    init(markdown: String, onOpenAnchor: ((String) -> Void)? = nil) {
        self.markdown = markdown
        self.onOpenAnchor = onOpenAnchor
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MarkdownTextView(
            markdown: markdown,
            colorScheme: colorScheme,
            onOpenAnchor: onOpenAnchor
        )
    }
}

private struct MarkdownTextView: UIViewRepresentable {
    let markdown: String
    let colorScheme: ColorScheme
    let onOpenAnchor: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.delegate = context.coordinator
        textView.dataDetectorTypes = []
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.onOpenAnchor = onOpenAnchor
        let attributed = MarkdownAttributedStringCache.shared.attributedString(
            markdown: markdown,
            colorScheme: colorScheme
        )
        if uiView.attributedText != attributed {
            uiView.attributedText = attributed
        }
        uiView.linkTextAttributes = [
            .foregroundColor: UIColor(
                red: colorScheme == .dark ? 0.51 : 0.04,
                green: colorScheme == .dark ? 0.81 : 0.42,
                blue: colorScheme == .dark ? 1.0 : 0.68,
                alpha: 1
            ),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenAnchor: ((String) -> Void)?

        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            if url.scheme == "localnotebook",
               url.host == "anchor" {
                let fragment = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                if !fragment.isEmpty {
                    onOpenAnchor?(fragment)
                    return false
                }
            }

            if let fragment = url.fragment, !fragment.isEmpty {
                onOpenAnchor?(fragment)
                return false
            }

            if url.absoluteString.hasPrefix("#") {
                let fragment = String(url.absoluteString.dropFirst())
                if !fragment.isEmpty {
                    onOpenAnchor?(fragment)
                    return false
                }
            }

            UIApplication.shared.open(url)
            return false
        }
    }
}

@MainActor
private final class MarkdownAttributedStringCache {
    static let shared = MarkdownAttributedStringCache()

    private let cache = NSCache<NSString, NSAttributedString>()

    func attributedString(markdown: String, colorScheme: ColorScheme) -> NSAttributedString {
        let key = "\(colorScheme == .dark ? "dark" : "light")::\(markdown)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let attributed = render(markdown: markdown, colorScheme: colorScheme)
        cache.setObject(attributed, forKey: key)
        return attributed
    }

    private func render(markdown: String, colorScheme: ColorScheme) -> NSAttributedString {
        MarkdownAttributedStringRenderer.attributedString(markdown: markdown, colorScheme: colorScheme)
    }
}

private enum MarkdownAttributedStringRenderer {
    static func attributedString(markdown: String, colorScheme: ColorScheme) -> NSAttributedString {
        let prepared = MarkdownHTMLRenderer.prepare(markdown)
        let lines = prepared.sanitizedMarkdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        let result = NSMutableAttributedString()
        var paragraphLines: [String] = []
        var codeFenceLanguage: String?
        var codeFenceLines: [String] = []

        func appendBlock(_ block: NSAttributedString) {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(block)
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraphText = paragraphLines.joined(separator: "\n")
            appendBlock(
                inlineAttributedString(
                    for: paragraphText,
                    attributes: paragraphAttributes(colorScheme: colorScheme)
                )
            )
            paragraphLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if codeFenceLanguage != nil {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    appendBlock(codeBlock(codeFenceLines.joined(separator: "\n"), colorScheme: colorScheme))
                    codeFenceLanguage = nil
                    codeFenceLines.removeAll(keepingCapacity: true)
                } else {
                    codeFenceLines.append(line)
                }
                continue
            }

            if let fence = MarkdownHTMLRenderer.parseCodeFence(line) {
                flushParagraph()
                codeFenceLanguage = fence
                codeFenceLines.removeAll(keepingCapacity: true)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = MarkdownHTMLRenderer.parseHeading(line) {
                flushParagraph()
                appendBlock(headingBlock(heading.text, level: heading.level, colorScheme: colorScheme))
                continue
            }

            if let quote = MarkdownHTMLRenderer.parseBlockquote(line) {
                flushParagraph()
                appendBlock(blockquoteBlock(quote, colorScheme: colorScheme))
                continue
            }

            if let listItem = MarkdownHTMLRenderer.parseListItem(line) {
                flushParagraph()
                appendBlock(listBlock(listItem, colorScheme: colorScheme))
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                appendBlock(horizontalRule(colorScheme: colorScheme))
                continue
            }

            paragraphLines.append(trimmed)
        }

        if codeFenceLanguage != nil {
            appendBlock(codeBlock(codeFenceLines.joined(separator: "\n"), colorScheme: colorScheme))
        }

        flushParagraph()
        return result
    }

    private static func headingBlock(_ text: String, level: Int, colorScheme: ColorScheme) -> NSAttributedString {
        let sizes: [CGFloat] = [30, 26, 22, 20, 18, 17]
        let font = UIFont.systemFont(ofSize: sizes[max(0, min(level - 1, sizes.count - 1))], weight: .bold)
        return inlineAttributedString(
            for: text,
            attributes: blockAttributes(
                font: font,
                color: colorScheme == .dark ? .white : .label,
                paragraphSpacing: 10
            )
        )
    }

    private static func blockquoteBlock(_ text: String, colorScheme: ColorScheme) -> NSAttributedString {
        let attrs = blockAttributes(
            font: .italicSystemFont(ofSize: 16),
            color: colorScheme == .dark ? UIColor(red: 0.78, green: 0.81, blue: 0.86, alpha: 1) : .secondaryLabel,
            paragraphSpacing: 8,
            firstLineHeadIndent: 12,
            headIndent: 12
        )
        return inlineAttributedString(for: text, attributes: attrs)
    }

    private static func listBlock(
        _ item: (depth: Int, type: String, text: String),
        colorScheme: ColorScheme
    ) -> NSAttributedString {
        let indent = CGFloat(item.depth) * 18
        let prefix = item.type == "ol" ? "1. " : "• "
        let attrs = blockAttributes(
            font: .systemFont(ofSize: 16),
            color: colorScheme == .dark ? .white : .label,
            paragraphSpacing: 4,
            firstLineHeadIndent: indent,
            headIndent: indent + 20
        )
        let result = NSMutableAttributedString(
            string: String(repeating: "\u{00a0}", count: item.depth * 2) + prefix,
            attributes: attrs
        )
        result.append(inlineAttributedString(for: item.text, attributes: attrs))
        return result
    }

    private static func codeBlock(_ text: String, colorScheme: ColorScheme) -> NSAttributedString {
        let attrs = blockAttributes(
            font: .monospacedSystemFont(ofSize: 14, weight: .regular),
            color: colorScheme == .dark ? .white : .label,
            paragraphSpacing: 8
        ).merging([
            .backgroundColor: colorScheme == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.06)
        ]) { _, new in new }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private static func horizontalRule(colorScheme: ColorScheme) -> NSAttributedString {
        NSAttributedString(
            string: "──────────",
            attributes: blockAttributes(
                font: .systemFont(ofSize: 12),
                color: colorScheme == .dark ? UIColor.white.withAlphaComponent(0.35) : UIColor.black.withAlphaComponent(0.25),
                paragraphSpacing: 8
            )
        )
    }

    private static func paragraphAttributes(colorScheme: ColorScheme) -> [NSAttributedString.Key: Any] {
        blockAttributes(
            font: .systemFont(ofSize: 16),
            color: colorScheme == .dark ? .white : .label,
            paragraphSpacing: 8
        )
    }

    private static func blockAttributes(
        font: UIFont,
        color: UIColor,
        paragraphSpacing: CGFloat,
        firstLineHeadIndent: CGFloat = 0,
        headIndent: CGFloat = 0
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.firstLineHeadIndent = firstLineHeadIndent
        paragraphStyle.headIndent = headIndent
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func inlineAttributedString(
        for text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes)

        applyInline(pattern: "`([^`]+)`", to: result, baseAttributes: attributes) { match in
            var codeAttributes = attributes
            codeAttributes[.font] = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            codeAttributes[.backgroundColor] = UIColor.black.withAlphaComponent(0.06)
            return NSAttributedString(string: match[1], attributes: codeAttributes)
        }

        applyInline(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", to: result, baseAttributes: attributes) { match in
            var linkAttributes = attributes
            let destination = match[2]
            if destination.hasPrefix("#"),
               let encoded = String(destination.dropFirst()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "localnotebook://anchor/\(encoded)") {
                linkAttributes[.link] = url
            } else if let url = URL(string: destination) {
                linkAttributes[.link] = url
            }
            return NSAttributedString(string: match[1], attributes: linkAttributes)
        }

        applyInline(pattern: "\\*\\*([^*]+)\\*\\*", to: result, baseAttributes: attributes) { match in
            var boldAttributes = attributes
            let baseFont = (attributes[.font] as? UIFont) ?? .systemFont(ofSize: 16)
            boldAttributes[.font] = UIFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            return NSAttributedString(string: match[1], attributes: boldAttributes)
        }

        applyInline(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", to: result, baseAttributes: attributes) { match in
            var italicAttributes = attributes
            let baseFont = (attributes[.font] as? UIFont) ?? .systemFont(ofSize: 16)
            italicAttributes[.font] = UIFont.italicSystemFont(ofSize: baseFont.pointSize)
            return NSAttributedString(string: match[1], attributes: italicAttributes)
        }

        return result
    }

    private static func applyInline(
        pattern: String,
        to attributedString: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any],
        replacement: ([String]) -> NSAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let source = attributedString.string
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        for match in matches.reversed() {
            var groups: [String] = []
            for index in 0..<match.numberOfRanges {
                if let range = Range(match.range(at: index), in: source) {
                    groups.append(String(source[range]))
                } else {
                    groups.append("")
                }
            }
            attributedString.replaceCharacters(in: match.range, with: replacement(groups))
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
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              font-size: 16px;
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

        let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
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

    static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let content = trimmed.dropFirst(hashes.count)
        guard content.first == " " else { return nil }
        return (hashes.count, content.trimmingCharacters(in: .whitespaces))
    }

    static func parseCodeFence(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    static func parseBlockquote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    static func parseListItem(_ line: String) -> (depth: Int, type: String, text: String)? {
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
