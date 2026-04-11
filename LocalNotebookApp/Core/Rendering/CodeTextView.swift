import SwiftUI
import UIKit

struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
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
        view.textContainerInset = UIEdgeInsets(top: 12, left: 2, bottom: 12, right: 2)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        uiView.isEditable = isEditable
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
