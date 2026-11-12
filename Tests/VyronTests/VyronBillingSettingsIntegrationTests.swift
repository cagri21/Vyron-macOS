import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronBillingSettingsIntegrationTests: XCTestCase {
    func testOpeningBillingSettingsPreservesTheTaskAndDoesNotRetrieveKeysOrContactProviders() async throws {
        let fixture = VyronBalanceTestHarness()
        let test = VyronQueueTestHarness(balanceDependencies: fixture.model.dependencies)
        addTeardownBlock {
            await test.model.connectionBalances.shutdown()
            await test.cleanUp()
            await fixture.cleanUp()
        }
        let profile = fixture.profile("OpenAI", endpoint: "https://api.openai.com/v1")
        test.model.modelSelection.connectionProfiles = [profile]
        test.model.modelSelection.activeConnectionID = profile.id
        test.model.composer.draft = "Preserve this unfinished task."
        let selectedModel = test.model.modelSelection.selectedModel
        let connectionRevision = test.model.modelSelection.connectionRevision
        test.model.openSettings(.billing)
        XCTAssertEqual(test.model.appNavigation.destination, .settings)
        XCTAssertEqual(test.model.appNavigation.settingsSection, .billing)
        XCTAssertEqual(test.model.modelSelection.activeConnectionID, profile.id)
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertEqual(test.model.modelSelection.connectionRevision, connectionRevision)
        XCTAssertEqual(test.model.composer.draft, "Preserve this unfinished task.")
        XCTAssertTrue(fixture.credentials.requests.isEmpty)
        let requests = await fixture.repository.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(VyronSettingsSection.billing.searchTerms.contains(VyronBillingText.apiCreditBalance))
        test.model.returnToWorkspace()
        XCTAssertEqual(test.model.composer.draft, "Preserve this unfinished task.")
    }
}
