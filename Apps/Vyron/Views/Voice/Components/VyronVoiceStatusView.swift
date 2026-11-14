import SwiftUI

struct VyronVoiceStatusView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var voice: VyronVoiceModel

    var body: some View {
        let _ = localizationLocale
        if voice.isActive || voice.errorMessage != nil {
            VStack(alignment: .leading, spacing: VyronVoiceStyle.spacing) {
                if let error = voice.errorMessage {
                    HStack(alignment: .top, spacing: VyronVoiceStyle.spacing) {
                        Image(systemName: VyronSymbols.warning).foregroundStyle(palette.warning)
                        Text(verbatim: error).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button(VyronVoiceText.retry) { voice.retryLastSession() }
                            .foregroundStyle(palette.accent)
                        Button { voice.dismissError() } label: { Image(systemName: VyronSymbols.close) }
                            .help(VyronVoiceText.dismissError)
                            .accessibilityLabel(VyronVoiceText.dismissError)
                    }
                    if !voice.transcript.isEmpty {
                        Text(verbatim: voice.transcript).textSelection(.enabled)
                    }
                } else {
                    HStack(spacing: VyronVoiceStyle.spacing) {
                        Image(systemName: VyronSymbols.liveVoice).foregroundStyle(palette.accent)
                        Text(status)
                            .accessibilityAddTraits(.updatesFrequently)
                        Spacer(minLength: 0)
                        if voice.isLiveConversation && (voice.phase == .speaking || voice.phase == .thinking) {
                            Button(VyronVoiceText.interrupt) { voice.interrupt() }
                                .foregroundStyle(palette.accent)
                        }
                        Button { voice.end() } label: { Image(systemName: VyronSymbols.close) }
                            .help(voice.isLiveConversation ? VyronVoiceText.endLive : VyronVoiceText.stopDictation)
                            .accessibilityLabel(
                                voice.isLiveConversation ? VyronVoiceText.endLive : VyronVoiceText.stopDictation
                            )
                    }
                    if voice.isLiveConversation && !voice.transcript.isEmpty {
                        Text(verbatim: voice.transcript).textSelection(.enabled)
                    } else if voice.phase == .listening {
                        Text(voice.isLiveConversation ? VyronVoiceText.listeningHint : VyronVoiceText.dictationHint)
                            .foregroundStyle(palette.muted)
                    }
                }
            }
            .font(VyronVoiceStyle.caption)
            .buttonStyle(.plain)
            .padding(VyronVoiceStyle.padding)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronVoiceStyle.radius))
        }
    }

    private var status: String {
        switch voice.phase {
        case .idle: VyronVoiceText.inactive
        case .requestingPermission: VyronVoiceText.requestingPermission
        case .listening: VyronVoiceText.listening
        case .thinking: VyronVoiceText.thinking
        case .speaking: VyronVoiceText.speaking
        }
    }
}
