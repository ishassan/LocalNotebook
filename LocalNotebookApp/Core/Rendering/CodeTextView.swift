import SwiftUI
import UIKit

struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var colorScheme: ColorScheme = .dark
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.spellCheckingType = .no
        view.backgroundColor = UIColor.clear
        view.textContainerInset = UIEdgeInsets(top: 14, left: 2, bottom: 14, right: 2)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.typingAttributes = CodeAttributedStringRenderer.typingAttributes(
            fontSize: fontSize,
            colorScheme: colorScheme
        )
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text || !context.coordinator.hasAppliedInitialText {
            let selectedRange = uiView.selectedRange
            uiView.attributedText = CodeAttributedStringRenderer.attributedString(
                code: text,
                fontSize: fontSize,
                colorScheme: colorScheme
            )
            uiView.selectedRange = min(selectedRange.location, uiView.attributedText.length) == selectedRange.location
                ? selectedRange
                : NSRange(location: uiView.attributedText.length, length: 0)
            context.coordinator.hasAppliedInitialText = true
        }
        uiView.isEditable = isEditable
        uiView.typingAttributes = CodeAttributedStringRenderer.typingAttributes(
            fontSize: fontSize,
            colorScheme: colorScheme
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        var hasAppliedInitialText = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            text.wrappedValue = textView.text
            textView.attributedText = CodeAttributedStringRenderer.attributedString(
                code: textView.text,
                fontSize: (textView.font ?? CodeTypography.font(size: 16)).pointSize,
                colorScheme: textView.traitCollection.userInterfaceStyle == .dark ? .dark : .light
            )
            textView.selectedRange = NSRange(location: min(selectedRange.location, textView.attributedText.length), length: 0)
        }
    }
}

struct CodeDisplayView: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
        view.textContainer.lineFragmentPadding = 0
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = CodeAttributedStringRenderer.attributedString(
            code: text,
            fontSize: fontSize,
            colorScheme: colorScheme
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}

struct CodeLineNumberView: View {
    let text: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        Text(lineNumbers)
            .font(Font(CodeTypography.font(size: fontSize)))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.38) : Color.black.opacity(0.45))
            .lineSpacing(4)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: gutterWidth, alignment: .trailing)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .padding(.leading, 6)
    }

    private var lineNumbers: String {
        let count = max(1, text.components(separatedBy: "\n").count)
        let digits = max(2, String(count).count)
        return (1...count)
            .map { String(format: "%\(digits)d", $0) }
            .joined(separator: "\n")
    }

    private var gutterWidth: CGFloat {
        let count = max(1, text.components(separatedBy: "\n").count)
        let digits = max(2, String(count).count)
        return CGFloat(digits) * fontSize * 0.68 + 10
    }
}

enum CodeTypography {
    static func font(size: CGFloat) -> UIFont {
        UIFont(name: "SFMono-Regular", size: size)
            ?? UIFont(name: "Menlo-Regular", size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

private enum CodeAttributedStringRenderer {
    static func typingAttributes(fontSize: CGFloat, colorScheme: ColorScheme) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return [
            .font: CodeTypography.font(size: fontSize),
            .foregroundColor: colorScheme == .dark ? UIColor(white: 0.94, alpha: 1) : UIColor(white: 0.12, alpha: 1),
            .paragraphStyle: paragraph
        ]
    }

    static func attributedString(code: String, fontSize: CGFloat, colorScheme: ColorScheme) -> NSAttributedString {
        highlightedCode(code, fontSize: fontSize, colorScheme: colorScheme)
    }

    private static func highlightedCode(_ code: String, fontSize: CGFloat, colorScheme: ColorScheme) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let result = NSMutableAttributedString(
            string: code,
            attributes: typingAttributes(fontSize: fontSize, colorScheme: colorScheme)
        )

        apply(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: colorScheme == .dark ? UIColor(red: 0.78, green: 0.86, blue: 0.55, alpha: 1) : UIColor(red: 0.22, green: 0.48, blue: 0.18, alpha: 1), to: result)
        apply(pattern: #"\b(import|from|as|def|class|return|if|elif|else|for|while|try|except|finally|with|in|not|and|or|lambda|yield|pass|break|continue|True|False|None)\b"#, color: colorScheme == .dark ? UIColor(red: 0.92, green: 0.47, blue: 0.73, alpha: 1) : UIColor(red: 0.70, green: 0.14, blue: 0.47, alpha: 1), to: result)
        apply(pattern: #"#.*$"#, color: colorScheme == .dark ? UIColor(white: 0.48, alpha: 1) : UIColor(white: 0.42, alpha: 1), to: result, options: [.anchorsMatchLines])
        apply(pattern: #"\b\d+(\.\d+)?\b"#, color: colorScheme == .dark ? UIColor(red: 0.70, green: 0.82, blue: 1.0, alpha: 1) : UIColor(red: 0.11, green: 0.39, blue: 0.76, alpha: 1), to: result)

        return result
    }

    private static func apply(
        pattern: String,
        color: UIColor,
        to attributedString: NSMutableAttributedString,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let source = attributedString.string
        let range = NSRange(source.startIndex..., in: source)
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            attributedString.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
