import SwiftUI
import VyronCore

struct VyronUserMessageBubble: View {
    let content: String
    let clarificationAnswers: [VyronClarificationAnswer]

    var body: some View {
        VStack(alignment: .leading, spacing: VyronConversationStyle.clarificationPairSpacing) {
            if clarificationAnswers.isEmpty {
                messageText(content, color: Palette.userMessageText)
            } else {
                ForEach(clarificationAnswers.indices, id: \.self) { index in
                    let entry = clarificationAnswers[index]
                    VStack(alignment: .leading, spacing: VyronConversationStyle.clarificationAnswerSpacing) {
                        messageText(entry.question, color: Palette.userMessageHint)
                        messageText(entry.answer, color: Palette.userMessageText)
                    }
                }
            }
        }
        .font(VyronConversationStyle.prose)
        .lineSpacing(VyronConversationStyle.proseLineSpacing)
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, VyronConversationStyle.userHorizontalPadding)
        .padding(.vertical, VyronConversationStyle.userVerticalPadding)
        .background(
            Palette.userMessageBackground,
            in: RoundedRectangle(cornerRadius: VyronConversationStyle.userRadius, style: .continuous)
        )
    }

    private func messageText(_ text: String, color: Color) -> some View {
        Text(verbatim: text).foregroundStyle(color)
    }
}
