import SwiftUI

struct VyronAutomationAdvancedControls: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var model: AutomationModel

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronAutomationCenterStyle.sectionSpacing) {
            actionSection
            browserSection
            monitorSection
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: VyronAutomationAdvancedControlsStyle.panelSpacing) {
            Eyebrow(text: VyronAppText.automationManualControls)
            Text(VyronAppText.automationElementHint)
                .font(VyronAutomationTypography.caption)
                .foregroundStyle(palette.muted)
                .lineSpacing(VyronAutomationAdvancedControlsStyle.hintLineSpacing)
            HStack(spacing: VyronAutomationAdvancedControlsStyle.controlSpacing) {
                TextField(VyronAppText.automationElementID, text: $model.elementID)
                    .textFieldStyle(.roundedBorder)
                    .font(VyronAutomationTypography.monospacedBody)
                    .frame(width: VyronAutomationAdvancedControlsStyle.elementIDWidth)
                Button(VyronAppText.automationClick) { model.reviewClick() }
                    .font(VyronAutomationTypography.body)
                    .disabled(model.snapshot == nil)
                Spacer()
                Picker(VyronAppText.automationKey, selection: $model.selectedKey) {
                    ForEach(VyronAutomationManualKey.allCases, id: \.self) { key in
                        Text(key.title).tag(key.rawValue)
                    }
                }
                .font(VyronAutomationTypography.caption)
                .frame(width: VyronAutomationAdvancedControlsStyle.keyPickerWidth)
                Button(VyronAppText.automationSendKey) { model.reviewKey(model.selectedKey) }
                    .font(VyronAutomationTypography.body)
            }
            HStack(alignment: .top, spacing: VyronAutomationAdvancedControlsStyle.controlSpacing) {
                TextField(VyronAppText.automationTextPlaceholder, text: $model.textToType, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(VyronAutomationTypography.body)
                    .lineLimit(VyronAutomationAdvancedControlsStyle.textEntryLines)
                Button(VyronAppText.automationTypeText) { model.reviewType() }
                    .font(VyronAutomationTypography.body)
                    .disabled(model.snapshot == nil)
            }
        }
        .disabled(
            !model.accessibilityGranted || model.selectedApplication == nil || model.isExecuting || model.isPlanning
                || model.isFollowingTask
        )
    }

    private var browserSection: some View {
        VStack(alignment: .leading, spacing: VyronAutomationAdvancedControlsStyle.panelSpacing) {
            Eyebrow(text: VyronAppText.automationBrowser)
            HStack(spacing: VyronAutomationAdvancedControlsStyle.controlSpacing) {
                Picker(VyronAppText.automationOpenIn, selection: $model.selectedBrowserID) {
                    Text(VyronAppText.automationDefaultBrowser)
                        .tag(VyronAutomationBrowserSelection.systemDefault.rawValue)
                    ForEach(model.browsers) { browser in Text(browser.name).tag(browser.id) }
                }
                .font(VyronAutomationTypography.body)
                .frame(width: VyronAutomationAdvancedControlsStyle.browserPickerWidth)
                Spacer()
                ForEach(VyronAutomationBrowserCommand.allCases, id: \.self) { command in
                    Button {
                        model.reviewKey(command.rawValue)
                    } label: {
                        Image(systemName: command.symbol)
                            .font(VyronAutomationTypography.body)
                            .frame(
                                width: VyronAutomationAdvancedControlsStyle.browserCommandWidth,
                                height: VyronAutomationAdvancedControlsStyle.browserCommandHeight
                            )
                    }
                    .help(VyronAppText.automationBrowserCommandHint(command.title))
                    .disabled(!model.accessibilityGranted || model.selectedApplication == nil)
                }
            }
            HStack(spacing: VyronAutomationAdvancedControlsStyle.controlSpacing) {
                TextField(VyronAutomationCenterText.urlPlaceholder, text: $model.browserURL)
                    .textFieldStyle(.roundedBorder)
                    .font(VyronAutomationTypography.monospacedBody)
                Button(VyronAppText.automationOpenURL) { model.reviewURL() }
                    .font(VyronAutomationTypography.body)
                    .disabled(model.browserURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(VyronAppText.automationBrowserHint)
                .font(VyronAutomationTypography.smallCaption)
                .foregroundStyle(palette.muted)
                .lineSpacing(VyronAutomationAdvancedControlsStyle.hintLineSpacing)
        }
        .disabled(model.isExecuting || model.isPlanning || model.isFollowingTask)
    }

    private var monitorSection: some View {
        VStack(alignment: .leading, spacing: VyronAutomationAdvancedControlsStyle.panelSpacing) {
            HStack {
                Eyebrow(text: VyronAppText.automationWatchChanges)
                Spacer()
                Picker(VyronAppText.automationEvery, selection: $model.monitorInterval) {
                    ForEach(VyronAutomationMonitorInterval.allCases, id: \.self) { interval in
                        Text(VyronAppText.automationSeconds(interval.rawValue)).tag(interval.rawValue)
                    }
                }
                .font(VyronAutomationTypography.caption)
                .frame(width: VyronAutomationAdvancedControlsStyle.monitorIntervalWidth)
                Toggle(
                    VyronAppText.automationMonitor,
                    isOn: Binding(
                        get: { model.isMonitoring },
                        set: { enabled in
                            if enabled {
                                model.startMonitoring()
                            } else {
                                model.stopMonitoring()
                            }
                        }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(VyronAutomationTypography.caption)
                .disabled(
                    !model.accessibilityGranted || model.selectedApplication == nil || model.isPlanning
                        || model.isExecuting || model.isFollowingTask
                )
            }
            Text(VyronAppText.automationMonitorHint)
                .font(VyronAutomationTypography.caption)
                .foregroundStyle(palette.muted)
                .lineSpacing(VyronAutomationAdvancedControlsStyle.hintLineSpacing)
            if model.events.isEmpty {
                Text(VyronAppText.automationChangesHint)
                    .font(VyronAutomationTypography.caption)
                    .foregroundStyle(
                        palette.muted.opacity(VyronAutomationAdvancedControlsStyle.monitorEmptyHintOpacity)
                    )
                    .padding(.vertical, VyronAutomationAdvancedControlsStyle.monitorEmptyHintPadding)
            } else {
                monitorEvents
                Button(VyronAppText.automationClearEvents) { model.events = [] }
                    .font(VyronAutomationTypography.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.muted)
            }
        }
    }

    private var monitorEvents: some View {
        VStack(alignment: .leading, spacing: VyronAutomationAdvancedControlsStyle.monitorEventListSpacing) {
            ForEach(model.events) { event in
                HStack(alignment: .top, spacing: VyronAutomationAdvancedControlsStyle.monitorEventSpacing) {
                    Text(event.date, style: .time)
                        .font(VyronAutomationTypography.monospacedSmallCaption)
                        .foregroundStyle(palette.accent)
                        .frame(width: VyronAutomationAdvancedControlsStyle.monitorEventTimeWidth, alignment: .leading)
                    Text(event.summary)
                        .font(VyronAutomationTypography.monospacedCaption)
                        .lineSpacing(VyronAutomationAdvancedControlsStyle.hintLineSpacing)
                        .textSelection(.enabled)
                }
                .padding(.vertical, VyronAutomationAdvancedControlsStyle.monitorEventVerticalPadding)
                if event.id != model.events.last?.id {
                    Rectangle()
                        .fill(palette.border)
                        .frame(height: VyronAutomationAdvancedControlsStyle.monitorEventDividerHeight)
                }
            }
        }
        .padding(.horizontal, VyronAutomationAdvancedControlsStyle.monitorEventListInset)
        .background(
            palette.surface,
            in: RoundedRectangle(cornerRadius: VyronAutomationAdvancedControlsStyle.monitorEventListRadius)
        )
    }
}
