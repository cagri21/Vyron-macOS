import SwiftUI

struct VyronVoiceSettingsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var voice: VyronVoiceModel

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronVoiceStyle.padding) {
            Label(VyronVoiceText.title, systemImage: VyronSymbols.liveVoice)
                .font(VyronVoiceStyle.title)
                .foregroundStyle(palette.text)
            Text(VyronVoiceText.description)
                .font(VyronVoiceStyle.body)
                .foregroundStyle(palette.muted)
            HStack(spacing: VyronVoiceStyle.padding) {
                Picker(VyronVoiceText.voice, selection: $voice.selectedVoiceID) {
                    Text(VyronVoiceText.systemDefault).tag("")
                    ForEach(voice.voices) { option in
                        Text(verbatim: "\(option.name) · \(languageName(option.language))").tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                Button {
                    if isPreviewing {
                        voice.end()
                    } else {
                        voice.previewVoice()
                    }
                } label: {
                    Label(
                        isPreviewing ? VyronVoiceText.stopPreview : VyronVoiceText.preview,
                        systemImage: isPreviewing ? VyronSymbols.stop : VyronSymbols.speaker
                    )
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(voice.isActive && !isPreviewing)
            }
            .font(VyronVoiceStyle.body)
            if voice.voices.isEmpty {
                Text(VyronVoiceText.noVoices).foregroundStyle(palette.warning)
            }
            Text(VyronVoiceText.voiceHint)
            Text(VyronVoiceText.recognitionLanguage)
            Text(VyronVoiceText.privacy)
        }
        .font(VyronVoiceStyle.caption)
        .foregroundStyle(palette.muted)
        .padding(VyronVoiceStyle.padding)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronVoiceStyle.radius))
        .onDisappear {
            if isPreviewing { voice.end() }
        }
    }

    private var isPreviewing: Bool { voice.phase == .speaking && !voice.isLiveConversation }

    private func languageName(_ language: String) -> String {
        localizationLocale.localizedString(forIdentifier: language) ?? language
    }
}
