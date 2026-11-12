import AppKit
import SwiftUI
import VyronCore

struct VyronUserInputQuestionView<Actions: View>: View {
    let question: VyronUserInputQuestion
    @Binding var answer: String
    let submit: () -> Void
    @ViewBuilder let actions: Actions
    @State private var customAnswer = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: VyronUserInputStyle.sectionSpacing) {
            Text(verbatim: question.question)
                .font(VyronUserInputStyle.question)
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: VyronUserInputStyle.rowSpacing) {
                ForEach(question.options.indices, id: \.self) { index in
                    let option = question.options[index]
                    VyronUserInputOptionRow(
                        option: option,
                        number: index + 1,
                        isSelected: customAnswer.isEmpty && answer == option.label
                    ) {
                        customAnswer = ""
                        answer = option.label
                    }
                }
            }
            HStack(alignment: .bottom, spacing: VyronUserInputStyle.controlSpacing) {
                customInput
                actions
            }
            if answer.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count
                > VyronUserInputLimits.maximumAnswerBytes {
                Text(VyronQuestionText.answerTooLong)
                    .font(VyronUserInputStyle.description)
                    .foregroundStyle(Palette.warning)
            }
        }
    }

    private var customInput: some View {
        HStack(alignment: .firstTextBaseline, spacing: VyronUserInputStyle.controlSpacing) {
            Image(systemName: VyronSymbols.pencil)
                .font(VyronUserInputStyle.icon)
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            TextField("", text: Binding(
                get: { customAnswer },
                set: { value in
                    customAnswer = value
                    answer = value
                }
            ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(VyronUserInputStyle.input)
                .foregroundStyle(Palette.text)
                .lineLimit(1...4)
                .overlay(alignment: .topLeading) {
                    if customAnswer.isEmpty {
                        Text(VyronQuestionText.answerPlaceholder)
                            .font(VyronUserInputStyle.input)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .focused($inputFocused)
                .accessibilityLabel(question.question)
                .accessibilityHint(VyronQuestionText.answerPlaceholder)
                .onKeyPress(.return, phases: .down) { keyPress in
                    let modifiers = keyPress.modifiers.subtracting(.capsLock)
                    guard inputFocused, modifiers.isEmpty || modifiers == .command else { return .ignored }
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextInputClient, editor.hasMarkedText() {
                        return .ignored
                    }
                    submit()
                    return .handled
                }
        }
        .padding(.vertical, VyronUserInputStyle.actionVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: VyronUserInputStyle.actionSize, alignment: .leading)
    }
}
