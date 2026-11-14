import SwiftUI
import VyronCore

struct VyronUserInputRequestView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    let request: VyronUserInputRequest
    @State private var draft = VyronUserInputDraft()
    @State private var contentHeight = VyronUserInputStyle.maximumQuestionsHeight

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronUserInputStyle.sectionSpacing) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: VyronUserInputStyle.questionSpacing) {
                    ForEach(request.questions) { question in
                        VyronUserInputQuestionView(
                            question: question,
                            answer: Binding(
                                get: { draft.value(for: question.id) },
                                set: { draft.setValue($0, for: question.id) }
                            ),
                            submit: submit
                        ) {
                            if question.id == request.questions.last?.id { actions }
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    contentHeight = height
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, VyronUserInputStyle.maximumQuestionsHeight))
        }
        .padding(VyronUserInputStyle.padding)
        .background(palette.field, in: RoundedRectangle(cornerRadius: VyronUserInputStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: VyronUserInputStyle.radius).stroke(palette.border))
        .disabled(!isCurrentRequest)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(VyronQuestionText.waitingForAnswer)
    }

    private var isCurrentRequest: Bool { model.selectedUserInputRequest?.id == request.id }

    private var header: some View {
        HStack(spacing: VyronUserInputStyle.controlSpacing) {
            Label(VyronQuestionText.title, systemImage: VyronSymbols.question)
            Spacer(minLength: 0)
            Button {
                guard isCurrentRequest else { return }
                model.stopGeneration()
            } label: {
                Image(systemName: VyronSymbols.close)
                    .frame(width: VyronUserInputStyle.actionSize, height: VyronUserInputStyle.actionSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(VyronQuestionText.dismiss)
            .accessibilityLabel(VyronQuestionText.dismiss)
        }
        .font(VyronUserInputStyle.option)
        .foregroundStyle(palette.muted)
    }

    private var actions: some View {
        HStack(spacing: VyronUserInputStyle.controlSpacing) {
            Button(VyronQuestionText.skip) {
                guard isCurrentRequest, let response = draft.responseSkippingUnanswered(
                    to: request, skippedAnswer: VyronQuestionText.skippedAnswer
                ) else { return }
                model.respondToUserInput(response)
            }
            .padding(.horizontal, VyronUserInputStyle.actionHorizontalPadding)
            .padding(.vertical, VyronUserInputStyle.actionVerticalPadding)
            .background(palette.selection, in: Capsule())
            .overlay(Capsule().stroke(palette.border))
            .disabled(draft.responseSkippingUnanswered(
                to: request, skippedAnswer: VyronQuestionText.skippedAnswer
            ) == nil)

            Button(VyronQuestionText.send, action: submit)
                .foregroundStyle(palette.onAccent)
                .padding(.horizontal, VyronUserInputStyle.actionHorizontalPadding)
                .padding(.vertical, VyronUserInputStyle.actionVerticalPadding)
                .background(palette.text, in: Capsule())
                .opacity(draft.response(to: request) == nil ? 0.4 : 1)
                .disabled(draft.response(to: request) == nil)
        }
        .font(VyronUserInputStyle.option)
        .foregroundStyle(palette.text)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func submit() {
        guard isCurrentRequest, let response = draft.response(to: request) else { return }
        model.respondToUserInput(response)
    }
}
