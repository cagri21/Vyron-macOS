import Foundation
import CoreGraphics

struct VyronComputerActionFeedback {
    let title: String
    let applicationID: String
    let targetFrame: CGRect?
    let sentAt: Date

    init(title: String, applicationID: String, targetFrame: CGRect? = nil) {
        self.title = title
        self.applicationID = applicationID
        self.targetFrame = targetFrame
        sentAt = Date()
    }
}
