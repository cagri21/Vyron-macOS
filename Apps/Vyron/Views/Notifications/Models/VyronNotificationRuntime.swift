struct VyronNotificationRuntime {
    var liveResponses: Set<VyronNotificationResponseID> = []
    var attention: [VyronNotificationAttention] = []
    var scheduledItems: [VyronNotificationItem] = []
}
