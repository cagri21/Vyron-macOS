import Foundation
import XCTest
@testable import Vyron

@MainActor
extension AppModel {
    @discardableResult
    func beginTestForegroundResponse(generationID: UUID = UUID()) -> VyronResponseIdentity {
        let response = VyronResponseIdentity(
            generationID: generationID,
            conversationID: selectedConversationID ?? UUID(),
            messageID: selectedConversation?.messages.last?.id ?? UUID()
        )
        foregroundRun.begin(response)
        return response
    }

    func withTestDevelopmentSettlement(assertWhileSettling: () -> Void) async {
        await withCheckedContinuation { continuation in
            let response = beginTestForegroundResponse()
            foregroundRun.beginDevelopment(response)
            foregroundRun.start(response) {}
            if !foregroundRun.stop(didSettle: { continuation.resume() }) {
                XCTFail("Expected a development response to enter stop settlement")
                continuation.resume()
            }
            assertWhileSettling()
        }
    }
}
