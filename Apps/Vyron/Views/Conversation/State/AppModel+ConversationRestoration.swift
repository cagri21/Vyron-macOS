extension AppModel {
    func restoreConversationHistory() -> Bool {
        do {
            conversations = try historyStore.load()
        } catch {
            errorMessage = VyronStatusText.historyOpenFailed(error.localizedDescription)
            do {
                if try historyStore.createRecoveryCopyIfPresent() {
                    errorMessage = VyronStatusText.historyRecoveryCopy
                }
            } catch {
                historyIsWritable = false
                errorMessage = VyronStatusText.historyUnavailable
            }
        }
        var recoveredActivity = false
        for ci in conversations.indices {
            for mi in conversations[ci].messages.indices {
                guard var activity = conversations[ci].messages[mi].activity,
                    activity.state == .working
                else { continue }
                // A saved in-progress response cannot still be running after relaunch.
                let interruptedAt = activity.latestRecordedAt
                activity.record(VyronStatusText.interruptedOnClose, at: interruptedAt)
                activity.finish(.stopped, at: interruptedAt)
                conversations[ci].messages[mi].activity = activity
                recoveredActivity = true
            }
        }
        return recoveredActivity
    }
}
