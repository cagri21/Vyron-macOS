/// Raw values identify preferences persisted by earlier versions of Vyron.
enum VyronUserDefaultsKey: String {
    case queueFollowUpMessages = "queueFollowUpMessages"
    case workspacePath = "workspacePath"
    case recentWorkspacePaths = "recentWorkspacePaths"
    case selectedSidebarProjectPath = "selectedSidebarProjectPath"
    case projectCommandApprovalMode = "projectCommandApprovalMode"
    case selectedLocalModel = "selectedLocalModel"
    case automaticModelSelection = "automaticModelSelection"
    case pausedModelDownloads = "pausedModelDownloads"
    case automaticallySetUpSkills = "automaticallySetUpSkills"
    case selectedSpeechVoiceID = "selectedSpeechVoiceID"
    case officePythonExecutable = "officePythonExecutable"
}
