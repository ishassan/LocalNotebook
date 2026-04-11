import SwiftUI

struct OutputRenderer: View {
    let output: NotebookOutput

    var body: some View {
        Group {
            switch output.outputType {
            case "stream":
                outputText(output.text?.joined ?? "", isError: output.name == "stderr")
            case "error":
                outputText(([output.ename, output.evalue].compactMap { $0 }.joined(separator: ": ") + "\n" + output.traceback.joined()), isError: true)
            default:
                richOutput
            }
        }
    }

    @ViewBuilder
    private var richOutput: some View {
        if let png = output.data["image/png"]?.stringValue,
           let data = Data(base64Encoded: png),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let markdown = output.data["text/markdown"]?.stringValue {
            MarkdownPreviewView(markdown: markdown)
        } else if let html = output.data["text/html"]?.stringValue ?? output.data["image/svg+xml"]?.stringValue {
            HTMLContentView(html: html)
                .frame(minHeight: 120, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let text = output.data["text/plain"]?.stringValue ?? output.text?.joined {
            outputText(text, isError: false)
        }
    }

    private func outputText(_ text: String, isError: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(isError ? .red : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(isError ? Color.red.opacity(0.08) : Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("output-text")
    }
}
