import AppKit
import SwiftUI

struct VyronAppearanceSettingsView: View {
    @Environment(VyronAppearanceState.self) private var appearance
    @Environment(\.vyronPalette) private var palette
    @State private var showsAdvanced = false
    @State private var themeFeedback: String?

    private var alternateScheme: ColorScheme { palette.scheme == .dark ? .light : .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: VyronSettingsStyle.headingSpacing) {
            Text(VyronAppearanceText.visualStyle)
                .font(VyronSettingsStyle.sectionTitle)
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            VyronSettingsCard {
                VyronAppearanceRow(VyronAppearanceText.mode) {
                    VyronAppearanceModePicker()
                }
            }
            VyronSettingsCard {
                themeRow
                separator
                colorRows(for: palette.scheme)
                separator
                VyronAppearanceRow(VyronAppearanceText.font) {
                    VyronAppearanceFontPicker()
                }
            }
            if let themeFeedback {
                Text(verbatim: themeFeedback)
                    .font(VyronSettingsStyle.detail)
                    .foregroundStyle(palette.muted)
            }
            footer
            if showsAdvanced {
                alternateColors
            }
        }
    }

    private var themeRow: some View {
        VyronAppearanceRow(VyronAppearanceText.theme) {
            HStack(spacing: VyronAppearanceSettingsStyle.controlSpacing) {
                themeAction(VyronAppearanceText.pasteTheme, symbol: VyronSymbols.themeImport, action: pasteTheme)
                themeAction(VyronAppearanceText.copyTheme, symbol: VyronSymbols.themeCopy, action: copyTheme)
                VyronAppearanceThemePicker()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showsAdvanced.toggle()
            } label: {
                HStack(spacing: VyronAppearanceSettingsStyle.controlSpacing) {
                    Text(VyronAppearanceText.advanced)
                    Image(systemName: showsAdvanced ? VyronSymbols.chevronDown : VyronSymbols.chevronRight)
                        .font(VyronAppearanceSettingsStyle.chevron)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityAddTraits(showsAdvanced ? .isSelected : [])
            .accessibilityIdentifier("vyron.appearance.advanced")
            Spacer()
            Button {
                appearance.reset()
                themeFeedback = nil
            } label: {
                Text(VyronAppearanceText.reset)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, VyronAppearanceSettingsStyle.pillInset)
                    .frame(minHeight: VyronAppearanceSettingsStyle.pillHeight)
                    .background(.background, in: Capsule())
                    .contentShape(Capsule())
            }
            .disabled(appearance.isDefault)
            .opacity(appearance.isDefault ? 0.5 : 1)
            .accessibilityIdentifier("vyron.appearance.reset")
        }
        .font(VyronSettingsStyle.body)
        .foregroundStyle(palette.muted)
        .buttonStyle(.plain)
        .padding(.top, VyronSettingsStyle.headingSpacing)
    }

    private var alternateColors: some View {
        VStack(alignment: .leading, spacing: VyronSettingsStyle.textSpacing) {
            Text(alternateScheme == .dark ? VyronAppearanceText.darkColors : VyronAppearanceText.lightColors)
                .font(VyronSettingsStyle.sectionTitle)
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            VyronSettingsCard {
                colorRows(for: alternateScheme)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: VyronSettingsStyle.dividerWidth)
            .accessibilityHidden(true)
    }

    private func colorRows(for scheme: ColorScheme) -> some View {
        VStack(spacing: 0) {
            colorRow(.accent, scheme: scheme)
            separator
            colorRow(.background, scheme: scheme)
            separator
            colorRow(.foreground, scheme: scheme)
        }
    }

    private func colorRow(_ slot: VyronAppearanceColorSlot, scheme: ColorScheme) -> some View {
        VyronAppearanceRow(slot.title) {
            VyronAppearanceColorControl(slot: slot, scheme: scheme)
        }
    }

    private func themeAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(VyronAppearanceSettingsStyle.controlIcon)
                .foregroundStyle(palette.muted)
                .frame(width: VyronAppearanceSettingsStyle.pillHeight, height: VyronAppearanceSettingsStyle.pillHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func copyTheme() {
        guard let string = appearance.exportTheme() else {
            themeFeedback = VyronAppearanceText.copyThemeFailed
            return
        }
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        themeFeedback = clipboard.setString(string, forType: .string)
            ? VyronAppearanceText.copiedTheme
            : VyronAppearanceText.copyThemeFailed
    }

    private func pasteTheme() {
        guard let string = NSPasteboard.general.string(forType: .string), appearance.importTheme(string) else {
            themeFeedback = VyronAppearanceText.invalidTheme
            return
        }
        themeFeedback = VyronAppearanceText.importedTheme
    }
}
