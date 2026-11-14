import SwiftUI
import VyronAutomation
import VyronCore

struct AutomationCenter: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var chat: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AutomationModel()
    @State private var showAdvancedControls = false

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronAutomationCenterStyle.flushSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: VyronAutomationCenterStyle.headerSpacing) {
                    Eyebrow(text: VyronAppText.automationHeading)
                    Text(VyronAppText.automationTitle)
                        .font(VyronAutomationTypography.title)
                    Text(VyronAppText.automationDescription)
                        .font(VyronAutomationTypography.body).foregroundStyle(palette.muted)
                }
                Spacer()
                Button {
                    model.close()
                    dismiss()
                } label: {
                    Image(systemName: VyronSymbols.close).font(VyronAutomationTypography.closeIcon)
                }
                .buttonStyle(QuietButtonStyle()).help(VyronAppText.automationClose)
            }
            .padding(VyronAutomationCenterStyle.windowInset)
            performance
                .padding(.horizontal, VyronAutomationCenterStyle.windowInset)
                .padding(.bottom, VyronAutomationCenterStyle.performanceBottomInset)
            Rectangle().fill(palette.border).frame(height: VyronAutomationCenterStyle.dividerThickness)
            HStack(alignment: .top, spacing: VyronAutomationCenterStyle.flushSpacing) {
                applicationPanel.frame(width: VyronAutomationCenterStyle.applicationPanelWidth)
                Rectangle().fill(palette.border).frame(width: VyronAutomationCenterStyle.dividerThickness)
                ScrollView {
                    VStack(alignment: .leading, spacing: VyronAutomationCenterStyle.sectionSpacing) {
                        if let error = model.error {
                            HStack(alignment: .top, spacing: VyronAutomationCenterStyle.statusIconSpacing) {
                                Image(systemName: VyronSymbols.warning)
                                Text(error).textSelection(.enabled)
                            }
                            .font(VyronAutomationTypography.body).foregroundStyle(palette.warning)
                            .padding(VyronAutomationCenterStyle.warningInset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                palette.warning.opacity(VyronAutomationCenterStyle.warningOpacity),
                                in: RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.cardRadius)
                            )
                        }
                        VyronComputerPreviewView(model: model)
                        VyronAutomationPlannerView(model: model)
                        snapshotSection
                        DisclosureGroup(VyronAppText.automationAdvanced, isExpanded: $showAdvancedControls) {
                            VyronAutomationAdvancedControls(model: model)
                                .padding(.top, VyronAutomationCenterStyle.advancedTopInset)
                        }
                        .font(VyronAutomationTypography.body).foregroundStyle(palette.muted)
                    }
                    .padding(VyronAutomationCenterStyle.contentInset)
                }
            }
            Rectangle().fill(palette.border).frame(height: VyronAutomationCenterStyle.dividerThickness)
            HStack(spacing: VyronAutomationCenterStyle.statusIconSpacing) {
                Image(systemName: VyronSymbols.access).foregroundStyle(palette.accent)
                Text(
                    model.status
                        ?? VyronAppText.automationReviewHint
                )
                .lineLimit(VyronAutomationCenterStyle.footerLineLimit)
                Spacer(minLength: VyronAutomationCenterStyle.flushSpacing)
            }
            .font(VyronAutomationTypography.caption).foregroundStyle(palette.muted)
            .padding(.horizontal, VyronAutomationCenterStyle.windowInset)
            .padding(.vertical, VyronAutomationCenterStyle.footerVerticalInset)
        }
        .background(palette.canvas)
        .foregroundStyle(palette.text)
        .tint(palette.controlAccent)
        .frame(width: VyronAutomationCenterStyle.windowWidth, height: VyronAutomationCenterStyle.windowHeight)
        .onAppear { model.configure(chat: chat) }
        .onChange(of: chat.computerWork.pendingAgentGoal?.id) { _, _ in
            if let request = chat.computerWork.pendingAgentGoal { model.acceptPendingGoal(request) }
        }
        .onDisappear { model.close() }
        .confirmationDialog(
            VyronAppText.automationReviewAction,
            isPresented: $model.showConfirmation,
            titleVisibility: .visible,
            presenting: model.pendingAction
        ) { _ in
            Button(VyronAppText.automationExecute) { model.executePending() }
            Button(VyronAppText.settingsCancel, role: .cancel) { model.cancelReview() }
        } message: { action in
            Text(action.details)
        }
    }

    private var performance: some View {
        HStack(spacing: VyronAutomationCenterStyle.metricSpacing) {
            metric(
                VyronAppText.automationCPU,
                value: model.systemStatus?.cpuUtilization.map {
                    VyronAutomationCenterText.cpuPercent($0 * VyronAutomationCenterStyle.percentScale)
                } ?? VyronAppText.automationMeasuring,
                icon: VyronSymbols.cpu
            )
            metric(
                VyronAppText.automationMemoryFree,
                value: model.systemStatus.map { formatBytes($0.memoryFreeBytes) } ?? VyronAppText.automationMeasuring,
                icon: VyronSymbols.memoryChip
            )
            metric(
                VyronAppText.automationDiskFree,
                value: model.systemStatus.map { formatBytes($0.diskFreeBytes) } ?? VyronAppText.automationMeasuring,
                icon: VyronSymbols.internalDrive
            )
            metric(
                VyronAppText.automationThermalState,
                value: model.systemStatus.map { VyronAutomationLabels.thermalState($0.thermalState) }
                    ?? VyronAppText.automationMeasuring,
                icon: VyronSymbols.thermometerMedium
            )
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: VyronAutomationCenterStyle.metricSpacing) {
            Image(systemName: icon).foregroundStyle(palette.muted).font(VyronAutomationTypography.body)
            VStack(alignment: .leading, spacing: VyronAutomationCenterStyle.metricLabelSpacing) {
                Text(title).font(VyronAutomationTypography.tinyCaption).foregroundStyle(palette.muted)
                Text(value).font(VyronAutomationTypography.monospacedMetric)
            }
            Spacer(minLength: VyronAutomationCenterStyle.flushSpacing)
        }
        .padding(VyronAutomationCenterStyle.metricInset).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.surface.opacity(VyronAutomationCenterStyle.subtleSurfaceOpacity),
            in: RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.tileRadius)
        )
    }

    private var applicationPanel: some View {
        VStack(alignment: .leading, spacing: VyronAutomationCenterStyle.applicationPanelSpacing) {
            HStack {
                Eyebrow(
                    text: model.isAgentMode ? VyronAppText.automationAvailableApps : VyronAppText.automationRunningApps
                )
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: VyronSymbols.refresh).font(VyronAutomationTypography.caption)
                }
                .buttonStyle(.plain).foregroundStyle(palette.muted).help(VyronAppText.automationRefreshApps)
            }
            ScrollView {
                VStack(spacing: VyronAutomationCenterStyle.applicationListSpacing) {
                    ForEach(model.applications) { app in
                        Button {
                            model.selectedApplicationID = app.id
                        } label: {
                            HStack(spacing: VyronAutomationCenterStyle.applicationRowSpacing) {
                                Image(systemName: VyronSymbols.openWindow).foregroundStyle(
                                    model.selectedApplicationID == app.id ? palette.accent : palette.muted
                                )
                                VStack(
                                    alignment: .leading, spacing: VyronAutomationCenterStyle.applicationLabelSpacing
                                ) {
                                    Text(app.name)
                                        .font(VyronAutomationTypography.emphasizedBody)
                                        .lineLimit(VyronAutomationCenterStyle.applicationNameLineLimit)
                                    if app.processIdentifier == 0 {
                                        Text(VyronAppText.automationInstalledNotOpen)
                                            .font(VyronAutomationTypography.tinyCaption).foregroundStyle(palette.muted)
                                    }
                                }
                                Spacer(minLength: VyronAutomationCenterStyle.flushSpacing)
                                if model.selectedApplicationID == app.id {
                                    Circle().fill(palette.accent)
                                        .frame(
                                            width: VyronAutomationCenterStyle.selectionIndicatorSize,
                                            height: VyronAutomationCenterStyle.selectionIndicatorSize
                                        )
                                }
                            }
                            .padding(VyronAutomationCenterStyle.applicationRowInset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                model.selectedApplicationID == app.id ? palette.raised : Color.clear,
                                in: RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.tileRadius)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isExecuting || model.isPlanning || model.isFollowingTask)
                    }
                }
            }
            Spacer(minLength: VyronAutomationCenterStyle.flushSpacing)
            Rectangle().fill(palette.border).frame(height: VyronAutomationCenterStyle.dividerThickness)
            permissionRow(VyronAppText.automationMacControl, granted: model.accessibilityGranted)
            Text(VyronAppText.automationControlRequired)
                .font(VyronAutomationTypography.caption).foregroundStyle(palette.muted)
                .lineSpacing(VyronAutomationCenterStyle.explanationLineSpacing)
            if !model.accessibilityGranted {
                Button(VyronAppText.automationAllowControl) { model.requestAccessibility() }
                    .buttonStyle(AccentButtonStyle())
                Text(model.permissionLocation)
                    .font(VyronAutomationTypography.smallCaption).foregroundStyle(palette.muted)
                    .lineSpacing(VyronAutomationCenterStyle.explanationLineSpacing)
            }
            Button(VyronAppText.automationPrivacySettings) { model.openPrivacySettings() }
                .font(VyronAutomationTypography.caption).buttonStyle(.plain).foregroundStyle(palette.muted)
        }
        .padding(VyronAutomationCenterStyle.applicationPanelInset)
        .background(palette.sidebar)
    }

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Text(title).font(VyronAutomationTypography.emphasizedCaption)
            Spacer()
            Image(systemName: granted ? VyronSymbols.selected : VyronSymbols.dashedCircle)
                .font(VyronAutomationTypography.body).foregroundStyle(granted ? palette.success : palette.muted)
        }
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: VyronAutomationCenterStyle.snapshotSectionSpacing) {
            HStack {
                Eyebrow(text: VyronAppText.automationCurrentAppState)
                Spacer()
                if let app = model.selectedApplication {
                    Text(app.name).font(VyronAutomationTypography.emphasizedCaption).foregroundStyle(palette.accent)
                }
                Button(VyronAppText.automationActivate) { model.reviewActivate() }
                    .font(VyronAutomationTypography.caption).buttonStyle(.plain).foregroundStyle(palette.muted)
                    .disabled(
                        model.selectedApplication == nil || model.selectedApplication?.processIdentifier == 0
                            || model.isExecuting || model.isPlanning || model.isFollowingTask
                    )
                Button(VyronAppText.automationInspect) { model.inspect() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(
                        !model.accessibilityGranted || model.selectedApplication == nil
                            || model.selectedApplication?.processIdentifier == 0 || model.isExecuting
                            || model.isPlanning || model.isFollowingTask
                    )
            }
            if let snapshot = model.snapshot {
                ScrollView([.horizontal, .vertical]) {
                    Text(snapshot.text)
                        .font(VyronAutomationTypography.monospacedCaption)
                        .lineSpacing(VyronAutomationCenterStyle.snapshotLineSpacing)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(VyronAutomationCenterStyle.snapshotInset)
                }
                .frame(height: VyronAutomationCenterStyle.snapshotHeight)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.cardRadius).stroke(palette.border))
                HStack {
                    TimelineView(
                        .periodic(from: .now, by: VyronAutomationDisplayTiming.clockRefreshInterval)
                    ) { context in
                        let age = max(0, Int(context.date.timeIntervalSince(snapshot.capturedAt)))
                        let isFresh = age < VyronAutomationSnapshotLimits.freshnessSeconds
                        Text(
                            VyronAppText.automationCapturedAge(
                                age,
                                isFresh ? VyronAppText.automationReadyForReview : VyronAppText.automationInspectAgain
                            )
                        )
                        .font(VyronAutomationTypography.smallCaption)
                        .foregroundStyle(isFresh ? palette.muted : palette.warning)
                    }
                    Spacer()
                    Button(VyronAppText.automationDiscussSnapshot) { chat.discussSnapshot(snapshot) }
                        .font(VyronAutomationTypography.emphasizedCaption).buttonStyle(.plain)
                        .foregroundStyle(palette.accent)
                        .disabled(model.isPlanning || model.isFollowingTask || chat.foregroundRun.isGenerating)
                }
            } else {
                VStack(spacing: VyronAutomationCenterStyle.emptySnapshotSpacing) {
                    Image(systemName: VyronSymbols.viewfinder)
                        .font(VyronAutomationTypography.emptySnapshotIcon)
                        .foregroundStyle(palette.accent)
                    Text(VyronAppText.automationSeeExposed)
                        .font(VyronAutomationTypography.body).foregroundStyle(palette.muted)
                    Text(VyronAppText.automationSnapshotDescription)
                        .font(VyronAutomationTypography.smallCaption)
                        .foregroundStyle(palette.muted.opacity(VyronAutomationCenterStyle.emptySnapshotHintOpacity))
                }
                .frame(maxWidth: .infinity).frame(height: VyronAutomationCenterStyle.emptySnapshotHeight)
                .background(
                    palette.surface.opacity(VyronAutomationCenterStyle.subtleSurfaceOpacity),
                    in: RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.cardRadius)
                )
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}
