import AppKit
import SwiftUI

struct VyronAppearanceFontPicker: View {
    @Environment(VyronAppearanceState.self) private var appearance
    @Environment(\.vyronPalette) private var palette
    @State private var isOpen = false
    @State private var query = ""
    @State private var families: [String] = []

    private var matches: [String] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? families : families.filter { $0.localizedStandardContains(search) }
    }

    var body: some View {
        Button {
            query = ""
            families = NSFontManager.shared.availableFontFamilies.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            isOpen.toggle()
        } label: {
            VyronAppearancePill {
                Text(verbatim: appearance.fontFamily ?? VyronAppearanceText.system)
                    .lineLimit(1)
                Image(systemName: VyronSymbols.chevronDown)
                    .font(VyronAppearanceSettingsStyle.chevron)
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: VyronAppearanceSettingsStyle.popoverWidth, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VyronAppearanceText.font)
        .accessibilityValue(appearance.fontFamily ?? VyronAppearanceText.system)
        .accessibilityIdentifier("vyron.appearance.font")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: VyronAppearanceSettingsStyle.controlSpacing) {
                TextField(VyronAppearanceText.fontSearch, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(VyronAppearanceText.fontSearch)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: VyronAppearanceSettingsStyle.optionInset) {
                        option(nil)
                        Divider()
                        ForEach(matches, id: \.self) { option($0) }
                        if matches.isEmpty {
                            Text(VyronAppearanceText.noFonts)
                                .foregroundStyle(palette.muted)
                                .padding(VyronAppearanceSettingsStyle.optionInset)
                        }
                    }
                }
            }
            .padding(VyronAppearanceSettingsStyle.popoverInset)
            .frame(
                width: VyronAppearanceSettingsStyle.popoverWidth,
                height: VyronAppearanceSettingsStyle.popoverListHeight
            )
        }
    }

    private func option(_ family: String?) -> some View {
        VyronAppearanceOption(
            title: family ?? VyronAppearanceText.system,
            isSelected: family == appearance.fontFamily,
            action: {
                appearance.setFontFamily(family)
                isOpen = false
            },
            mark: { EmptyView() }
        )
        .font(VyronAppearanceSettingsStyle.controlText.font(family: nil))
    }
}
