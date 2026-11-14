import SwiftUI

struct VyronAppearanceColorControl: View {
    @Environment(VyronAppearanceState.self) private var appearance
    @Environment(\.vyronPalette) private var palette
    @State private var isOpen = false
    @State private var hexInput = ""
    @State private var isInvalid = false
    let slot: VyronAppearanceColorSlot
    let scheme: ColorScheme

    private var color: Color { appearance.palette(for: scheme).color(for: slot) }
    private var hex: String { VyronAppearanceColor(color: color)?.hex ?? "" }

    private var hasOverride: Bool {
        appearance.hasColorOverride(for: slot, scheme: scheme)
    }

    private var activeColor: Binding<Color> {
        Binding {
            color
        } set: { chosenColor in
            if let value = VyronAppearanceColor(color: chosenColor) {
                appearance.setColor(value, for: slot, scheme: scheme)
            }
        }
    }

    var body: some View {
        Button {
            hexInput = hex
            isInvalid = false
            isOpen.toggle()
        } label: {
            VyronAppearancePill {
                Circle()
                    .fill(color)
                    .overlay { Circle().strokeBorder(palette.border) }
                    .frame(
                        width: VyronAppearanceSettingsStyle.swatchSize,
                        height: VyronAppearanceSettingsStyle.swatchSize
                    )
                    .accessibilityHidden(true)
                Text(verbatim: slot == .accent && !hasOverride ? VyronAppearanceText.defaultAccent : hex)
                    .monospacedDigit()
                if slot == .accent {
                    Image(systemName: VyronSymbols.chevronDown)
                        .font(VyronAppearanceSettingsStyle.chevron)
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slot.title)
        .accessibilityValue(hex)
        .accessibilityIdentifier("vyron.appearance.\(scheme == .dark ? "dark" : "light").\(slot)")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            colorEditor
        }
        .onChange(of: hex) { _, newValue in
            if isOpen {
                hexInput = newValue
                isInvalid = false
            }
        }
    }

    private var colorEditor: some View {
        VStack(alignment: .leading, spacing: VyronAppearanceSettingsStyle.controlSpacing) {
            ColorPicker(VyronAppearanceText.chooseColor, selection: activeColor, supportsOpacity: false)
            HStack {
                TextField(VyronAppearanceText.hexColor, text: $hexInput)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .accessibilityLabel(VyronAppearanceText.hexColor)
                    .onChange(of: hexInput) { _, _ in isInvalid = false }
                    .onSubmit(applyHex)
                Button(VyronAppearanceText.applyColor, action: applyHex)
            }
            if isInvalid {
                Text(VyronAppearanceText.invalidHex)
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(VyronAppearanceText.useThemeColor) {
                appearance.setColor(nil, for: slot, scheme: scheme)
                isOpen = false
            }
            .disabled(!hasOverride)
        }
        .font(VyronAppearanceSettingsStyle.controlText)
        .foregroundStyle(palette.text)
        .padding(VyronAppearanceSettingsStyle.popoverInset)
        .frame(width: VyronAppearanceSettingsStyle.popoverWidth)
        .background(palette.surface)
    }

    private func applyHex() {
        guard let value = VyronAppearanceColor(hex: hexInput) else {
            isInvalid = true
            return
        }
        appearance.setColor(value, for: slot, scheme: scheme)
        isOpen = false
    }
}
