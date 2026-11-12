import SwiftUI
import VyronCore

struct VyronAutomationPlannerView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var chat: AppModel
    @ObservedObject var model: AutomationModel

    private var isOneAction: Bool { model.plannerMode == VyronAutomationPlannerMode.oneAction.rawValue }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronAutomationPlannerStyle.sectionSpacing) {
            HStack {
                Eyebrow(text: VyronAppText.automationYourGoal)
                Spacer()
                Picker(VyronAppText.automationMode, selection: $model.plannerMode) {
                    ForEach(VyronAutomationPlannerMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented).frame(width: VyronAutomationPlannerStyle.modePickerWidth).controlSize(.small)
                .disabled(model.isPlanning || model.isExecuting || model.isFollowingTask)
                .onChange(of: model.plannerMode) { _, _ in
                    model.proposal = nil
                    model.refresh()
                }
            }
            Text(
                model.isAgentMode
                    ? VyronAppText.automationAgentHint
                    : model.plannerMode == VyronAutomationPlannerMode.reviewSteps.rawValue
                        ? VyronAppText.automationTaskHint
                        : VyronAppText.automationOneActionHint
            )
            .font(VyronAutomationTypography.caption)
            .foregroundStyle(Palette.muted)
            .lineSpacing(VyronAutomationCenterStyle.explanationLineSpacing)
            if model.isAgentMode {
                HStack(spacing: VyronAutomationPlannerStyle.preferenceSpacing) {
                    Toggle(VyronAppText.automationAutoApps, isOn: $model.automaticAppChoice)
                    Toggle(VyronAppText.automationAutoRoutine, isOn: $model.routineAutonomy)
                    Spacer(minLength: VyronAutomationCenterStyle.flushSpacing)
                    Picker(VyronAppText.automationEffort, selection: $model.agentEffort) {
                        Text(VyronAppText.automationAuto).tag(AgentEffort.automatic)
                        Text(VyronAppText.automationQuick).tag(AgentEffort.quick)
                        Text(VyronAppText.automationBalanced).tag(AgentEffort.balanced)
                        Text(VyronAppText.automationDeep).tag(AgentEffort.deep)
                    }.frame(width: VyronAutomationPlannerStyle.effortPickerWidth)
                }
                .toggleStyle(.checkbox).font(VyronAutomationTypography.smallCaption).disabled(model.isFollowingTask)
            }
            if !chat.modelSelection.isBuiltinConnection {
                Text(VyronAppText.automationLocalRequired)
                    .font(VyronAutomationTypography.caption)
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(VyronAutomationCenterStyle.explanationLineSpacing)
            }
            HStack(alignment: .top, spacing: VyronAutomationPlannerStyle.rowSpacing) {
                TextField(
                    model.isAgentMode
                        ? VyronAppText.automationAgentExample
                        : model.plannerMode == VyronAutomationPlannerMode.reviewSteps.rawValue
                            ? VyronAppText.automationTaskExample
                            : VyronAppText.automationActionExample,
                    text: $model.plannerInstruction,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .font(model.isAgentMode ? VyronAutomationTypography.agentInstruction : VyronAutomationTypography.body)
                .lineLimit(
                    model.isAgentMode
                        ? VyronAutomationPlannerStyle.agentInstructionLines
                        : VyronAutomationPlannerStyle.actionInstructionLines
                )
                .disabled(model.isPlanning || model.isFollowingTask)
                if model.isFollowingTask {
                    if model.isPlanning || model.isExecuting {
                        ProgressView().controlSize(.small).padding(VyronAutomationPlannerStyle.progressInset)
                    }
                    Button(VyronAppText.automationStopTask) { model.stopTask() }
                        .font(VyronAutomationTypography.emphasizedBody).foregroundStyle(Palette.warning)
                } else if model.isPlanning {
                    ProgressView().controlSize(.small).padding(VyronAutomationPlannerStyle.progressInset)
                    Button(VyronAppText.automationStop) { model.cancelPlanning() }
                        .font(VyronAutomationTypography.caption).buttonStyle(.plain)
                        .foregroundStyle(Palette.muted)
                } else {
                    Button(
                        !isOneAction ? VyronAppText.automationStartGoal : VyronAppText.automationPlanAction
                    ) {
                        if !isOneAction { model.startTask() } else { model.plan() }
                    }.buttonStyle(AccentButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(
                            !chat.modelSelection.isBuiltinConnection
                                || chat.modelSelection.connectionOperationInProgress
                                || (isOneAction && model.snapshot == nil)
                                || !model.accessibilityGranted
                                || ((!model.isAgentMode || !model.automaticAppChoice)
                                    && model.selectedApplication == nil)
                                || !chat.modelSelection.isConnected || !chat.modelSelection.modelIsAvailable
                                || chat.foregroundRun.isGenerating
                                || chat.modelDownloads.isActive || model.isExecuting
                                || model.plannerInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
            if !isOneAction, !model.taskState.isEmpty || !model.taskEvents.isEmpty {
                VStack(alignment: .leading, spacing: VyronAutomationPlannerStyle.rowSpacing) {
                    HStack(alignment: .top) {
                        Text(model.taskState)
                            .font(VyronAutomationTypography.emphasizedBody)
                            .lineSpacing(VyronAutomationCenterStyle.explanationLineSpacing)
                        Spacer()
                        if model.isFollowingTask {
                            Circle()
                                .fill(Palette.success)
                                .frame(
                                    width: VyronAutomationPlannerStyle.runningIndicatorSize,
                                    height: VyronAutomationPlannerStyle.runningIndicatorSize
                                )
                                .padding(.top, VyronAutomationPlannerStyle.runningIndicatorTopInset)
                        }
                    }
                    Text(
                        model.isAgentMode
                            ? VyronAppText.automationDecisionCounts(
                                model.taskPlanningPasses,
                                model.agentMaximumSteps,
                                model.approvedTaskActions
                            )
                            : VyronAppText.automationPlanningCounts(model.taskPlanningPasses, model.approvedTaskActions)
                    )
                    .font(VyronAutomationTypography.monospacedSmallCaption).foregroundStyle(Palette.muted)
                    if model.isAgentMode, let decision = model.agentDecision {
                        Text(
                            VyronAppText.automationDecisionBudget(
                                VyronAutomationLabels.effort(decision.effort.rawValue),
                                decision.budget.contextTokens.formatted(),
                                decision.budget.outputTokens.formatted(),
                                decision.model
                            )
                        )
                        .font(VyronAutomationTypography.monospacedSmallCaption)
                        .foregroundStyle(Palette.accent)
                        .lineLimit(VyronAutomationPlannerStyle.budgetLineLimit)
                    }
                    if let wake = model.nextAgentWake, model.isFollowingTask {
                        TimelineView(
                            .periodic(from: .now, by: VyronAutomationDisplayTiming.clockRefreshInterval)
                        ) { context in
                            Text(VyronAppText.automationNextCheck(max(0, Int(wake.timeIntervalSince(context.date)))))
                                .font(VyronAutomationTypography.emphasizedCaption).foregroundStyle(Palette.accent)
                        }
                    }
                    if !model.taskEvents.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: VyronAutomationPlannerStyle.rowSpacing) {
                                ForEach(model.taskEvents) { event in
                                    HStack(alignment: .top, spacing: VyronAutomationPlannerStyle.rowSpacing) {
                                        Text(event.date, style: .time)
                                            .font(VyronAutomationTypography.monospacedTinyCaption)
                                            .foregroundStyle(Palette.accent)
                                            .frame(
                                                width: VyronAutomationPlannerStyle.eventTimeWidth,
                                                alignment: .leading
                                            )
                                        Text(event.summary)
                                            .font(VyronAutomationTypography.monospacedSmallCaption)
                                            .foregroundStyle(
                                                Palette.text.opacity(VyronAutomationPlannerStyle.eventTextOpacity)
                                            )
                                            .lineSpacing(VyronAutomationCenterStyle.explanationLineSpacing)
                                            .textSelection(.enabled)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: VyronAutomationPlannerStyle.eventLogMaximumHeight)
                    }
                    Text(
                        model.isAgentMode
                            ? VyronAppText.automationActiveGoalHint
                            : VyronAppText.automationFreshReadsHint
                    )
                    .font(VyronAutomationTypography.smallCaption)
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(VyronAutomationCenterStyle.explanationLineSpacing)
                }
                .padding(VyronAutomationPlannerStyle.taskLogInset)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.cardRadius))
            }
            if let proposal = model.proposal {
                VStack(alignment: .leading, spacing: VyronAutomationPlannerStyle.rowSpacing) {
                    HStack {
                        Label(
                            VyronAutomationCenterText.proposalHeading(
                                proposal.kind == .complete
                                    ? VyronAppText.automationAIReport
                                    : VyronAppText.automationProposal,
                                proposal.kind.rawValue
                            ),
                            systemImage: VyronSymbols.sparkle
                        )
                        .font(VyronAutomationTypography.proposalHeading)
                        .foregroundStyle(Palette.accent)
                        Spacer()
                        if proposal.kind != .complete && proposal.kind != .wait
                            && !(model.isFollowingTask && proposal.kind == .inspect) {
                            Button(VyronAppText.automationReviewExecute) { model.reviewProposal() }
                                .font(VyronAutomationTypography.emphasizedCaption)
                                .buttonStyle(.plain)
                                .foregroundStyle(Palette.accent)
                                .disabled(model.isExecuting || model.isPlanning)
                        }
                    }
                    Text(proposal.explanation)
                        .font(VyronAutomationTypography.body)
                        .lineSpacing(VyronAutomationCenterStyle.explanationLineSpacing)
                        .textSelection(.enabled)
                    if let id = proposal.elementID {
                        detail(VyronAppText.automationElement, VyronAutomationCenterText.elementReference(id))
                    }
                    if let text = proposal.text { detail(VyronAppText.automationText, text) }
                    if let url = proposal.url { detail(VyronAppText.automationURL, url) }
                    if let key = proposal.key { detail(VyronAppText.automationKey, VyronAutomationLabels.key(key)) }
                    detail(
                        VyronAppText.automationTarget,
                        model.selectedApplication?.name ?? VyronAppText.automationSelectedApp
                    )
                }
                .padding(VyronAutomationPlannerStyle.proposalInset)
                .background(
                    Palette.accent.opacity(VyronAutomationPlannerStyle.proposalFillOpacity),
                    in: RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.cardRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VyronAutomationCenterStyle.cardRadius)
                        .stroke(Palette.accent.opacity(VyronAutomationPlannerStyle.proposalBorderOpacity))
                )
            }
        }
    }

    private func detail(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: VyronAutomationPlannerStyle.detailSpacing) {
            Text(VyronAutomationCenterText.detailLabel(name))
                .foregroundStyle(Palette.muted)
                .frame(width: VyronAutomationPlannerStyle.detailLabelWidth, alignment: .leading)
            Text(value).textSelection(.enabled)
        }.font(VyronAutomationTypography.monospacedCaption)
    }
}
