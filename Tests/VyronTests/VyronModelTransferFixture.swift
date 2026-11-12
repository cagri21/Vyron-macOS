import XCTest
@testable import Vyron
import VyronCore

@MainActor
enum VyronModelTransferFixture {
    @discardableResult
    static func start(
        in downloads: VyronModelDownloads,
        progress: ModelPullProgress? = nil
    ) -> VyronModelTransfer {
        let transfer = VyronModelTransfer(tag: "fixture-coder:q4", kind: .ggufImport)
        downloads.start(
            transfer,
            operation: VyronModelTransferOperation(
                execute: { update in
                    if let progress { update(progress) }
                    try await Task.sleep(for: .seconds(30))
                    XCTFail("The transfer fixture should be cancelled at teardown.")
                    return transfer.tag
                },
                refreshModels: {},
                complete: { _ in }
            )
        )
        return transfer
    }
}
