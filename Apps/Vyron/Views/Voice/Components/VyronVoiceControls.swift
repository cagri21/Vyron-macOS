import SwiftUI

struct VyronVoiceControls: View {
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var voice: VyronVoiceModel
    let canStart: Bool
    var showsLiveConversation = true

    var body: some View {
        let _ = localizationLocale
        HStack(spacing: VyronVoiceStyle.spacing) {
            Button {
                voice.toggleDictation()
            } label: {
                Image(systemName: isDictating ? VyronSymbols.stop : VyronSymbols.microphone)
                    .frame(width: VyronVoiceStyle.controlSize, height: VyronVoiceStyle.controlSize)
            }
            .help(isDictating ? VyronVoiceText.stopDictation : VyronVoiceText.startDictation)
            .accessibilityLabel(isDictating ? VyronVoiceText.stopDictation : VyronVoiceText.startDictation)
            .disabled(!isDictating && (!canStart || voice.isActive))

            if showsLiveConversation || voice.isLiveConversation {
                Button {
                    voice.toggleLiveConversation()
                } label: {
                    Image(systemName: voice.isLiveConversation ? VyronSymbols.endVoice : VyronSymbols.liveVoice)
                        .foregroundStyle(Palette.text)
                        .frame(width: VyronWorkspaceStyle.actionSize, height: VyronWorkspaceStyle.actionSize)
                        .background(Palette.controlAccent, in: Circle())
                }
                .help(voice.isLiveConversation ? VyronVoiceText.endLive : VyronVoiceText.startLive)
                .accessibilityLabel(voice.isLiveConversation ? VyronVoiceText.endLive : VyronVoiceText.startLive)
                .disabled(!voice.isLiveConversation && (!canStart || voice.isActive))
            }
        }
        .font(VyronVoiceStyle.icon)
        .foregroundStyle(voice.isActive ? Palette.accent : Palette.text)
        .buttonStyle(.plain)
    }

    private var isDictating: Bool { voice.isActive && !voice.isLiveConversation }
}
