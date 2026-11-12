import Foundation

struct VyronChatHandoffPresentation: Identifiable {
    let sourceID: UUID
    let initialRequest: String?
    let destination: VyronChatHandoffSelection?
    let requiresDestinationSelection: Bool

    var id: UUID { sourceID }

    init(
        sourceID: UUID,
        initialRequest: String? = nil,
        destination: VyronChatHandoffSelection? = nil,
        requiresDestinationSelection: Bool = false
    ) {
        self.sourceID = sourceID
        self.initialRequest = initialRequest
        self.destination = destination
        self.requiresDestinationSelection = requiresDestinationSelection
    }
}
