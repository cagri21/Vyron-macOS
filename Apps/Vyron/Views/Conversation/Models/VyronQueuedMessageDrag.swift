import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct VyronQueuedMessageDrag: Codable, Transferable, Sendable {
    let conversationID: UUID
    let messageID: UUID

    // Match this native transfer type to the app's UTExportedTypeDeclarations.
    static let contentType = UTType(exportedAs: "ai.vyron.queued-message", conformingTo: .data)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}
