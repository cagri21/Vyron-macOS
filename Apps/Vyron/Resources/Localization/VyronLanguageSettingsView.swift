import SwiftUI

struct VyronLanguageSettingsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var localization: VyronLocalization

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading) {
            Picker(VyronLanguageText.title, selection: $localization.language) {
                ForEach(VyronLanguage.allCases) { language in
                    Text(verbatim: language.nativeName).tag(language)
                }
            }
            Text(VyronLanguageText.hint)
                .font(.caption)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
