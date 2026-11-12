// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static var automationTarget: String {
        VyronResourceBundle.string("appAutomationTarget", fallback: "Target")
    }
    static var automationTaskExample: String {
        VyronResourceBundle.string("appAutomationTaskExample", fallback: "For example, find the project’s documentation in this browser")
    }
    static var automationTaskHint: String {
        VyronResourceBundle.string("appAutomationTaskHint", fallback: "Describe your goal. Vyron reads the selected app, proposes the next step, and checks progress after each action you approve. Your selected app stays fixed.")
    }
    static var automationText: String {
        VyronResourceBundle.string("appAutomationText", fallback: "Text")
    }
    static var automationTextPlaceholder: String {
        VyronResourceBundle.string("appAutomationTextPlaceholder", fallback: "Text to place in the selected field")
    }
    static var automationThermalCritical: String {
        VyronResourceBundle.string("appAutomationThermalCritical", fallback: "Critical")
    }
    static var automationThermalFair: String {
        VyronResourceBundle.string("appAutomationThermalFair", fallback: "Fair")
    }
    static var automationThermalNominal: String {
        VyronResourceBundle.string("appAutomationThermalNominal", fallback: "Nominal")
    }
    static var automationThermalSerious: String {
        VyronResourceBundle.string("appAutomationThermalSerious", fallback: "Serious")
    }
    static var automationThermalState: String {
        VyronResourceBundle.string("appAutomationThermalState", fallback: "Thermal state")
    }
    static var automationTitle: String {
        VyronResourceBundle.string("appAutomationTitle", fallback: "Mac & browser")
    }
    static var automationTypeText: String {
        VyronResourceBundle.string("appAutomationTypeText", fallback: "Type text…")
    }
    static var automationUpKey: String {
        VyronResourceBundle.string("appAutomationUpKey", fallback: "Up")
    }
    static var automationURL: String {
        VyronResourceBundle.string("appAutomationURL", fallback: "URL")
    }
    static var automationWatchChanges: String {
        VyronResourceBundle.string("appAutomationWatchChanges", fallback: "05 / Watch for changes")
    }
    static var automationYourGoal: String {
        VyronResourceBundle.string("appAutomationYourGoal", fallback: "Your goal")
    }
    static var inspectorActivity: String {
        VyronResourceBundle.string("appInspectorActivity", fallback: "Activity")
    }
    static var inspectorActivityHint: String {
        VyronResourceBundle.string("appInspectorActivityHint", fallback: "The agent’s work appears here.")
    }
    static var inspectorAddedFile: String {
        VyronResourceBundle.string("appInspectorAddedFile", fallback: "Added file")
    }
    static var inspectorAfter: String {
        VyronResourceBundle.string("appInspectorAfter", fallback: "After")
    }
    static var inspectorBefore: String {
        VyronResourceBundle.string("appInspectorBefore", fallback: "Before")
    }
    static var inspectorChangedFile: String {
        VyronResourceBundle.string("appInspectorChangedFile", fallback: "Changed file")
    }
    static var inspectorChanges: String {
        VyronResourceBundle.string("appInspectorChanges", fallback: "Changes")
    }
    static func inspectorChangesCount(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "appInspectorChangesCount",
            fallback: "Changes %d",
            arguments: [p1]
        )
    }
    static var inspectorChangesHint: String {
        VyronResourceBundle.string("appInspectorChangesHint", fallback: "Shows edits made through the agent’s file tools. Commands can also change project files. Revert preserves any newer edits you made.")
    }
    static var inspectorClear: String {
        VyronResourceBundle.string("appInspectorClear", fallback: "Clear")
    }
    static var inspectorCommandOutput: String {
        VyronResourceBundle.string("appInspectorCommandOutput", fallback: "Local command output")
    }
    static var inspectorCompletedEditsHint: String {
        VyronResourceBundle.string("appInspectorCompletedEditsHint", fallback: "Completed edits appear here with the original version and a reviewable diff.")
    }
    static var inspectorCopyDiff: String {
        VyronResourceBundle.string("appInspectorCopyDiff", fallback: "Copy diff")
    }
    static var inspectorCopyPreview: String {
        VyronResourceBundle.string("appInspectorCopyPreview", fallback: "Copy file preview")
    }
    static var inspectorDiff: String {
        VyronResourceBundle.string("appInspectorDiff", fallback: "Diff")
    }
    static var inspectorFileDidNotExist: String {
        VyronResourceBundle.string("appInspectorFileDidNotExist", fallback: "This file did not exist before the task.")
    }
    static var inspectorFiles: String {
        VyronResourceBundle.string("appInspectorFiles", fallback: "Files")
    }
    static func inspectorFilesCount(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "appInspectorFilesCount",
            fallback: "%d files",
            arguments: [p1]
        )
    }
    static var inspectorFilesHint: String {
        VyronResourceBundle.string("appInspectorFilesHint", fallback: "The agent finds the files it needs. Open a file here to preview it.")
    }
}
