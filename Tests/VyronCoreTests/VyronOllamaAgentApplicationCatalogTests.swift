import XCTest
@testable import VyronModelData
import VyronModelDomain

final class VyronOllamaAgentApplicationCatalogTests: XCTestCase {
    func testRequestedClosedApplicationsAreRankedBeforeTheCatalogIsBounded() {
        let fillerApps = (0..<VyronOllamaPlanningLimits.maximumCandidateApplications).map {
            AgentApplication(id: "org.example.app\($0)", name: "Application \($0)")
        }
        let penpot = AgentApplication(id: "com.authormore.penpotdesktop", name: "Penpot Desktop", isRunning: false)
        let quickTime = AgentApplication(id: "com.apple.QuickTimePlayerX", name: "QuickTime Player", isRunning: false)
        let apps = fillerApps + [penpot, quickTime]

        for (goal, expected) in [
            ("Open Penpot", penpot), ("Open the quick time app", quickTime),
            ("Open QUICKTIME PLAYER", quickTime), ("Open com.authormore.penpotdesktop", penpot)
        ] {
            let candidates = VyronOllamaAgentApplicationCatalog.rankedApplications(
                apps, goal: goal, snapshotApplicationID: nil
            )
            XCTAssertEqual(candidates.first, expected, goal)
            XCTAssertEqual(candidates.count, VyronOllamaPlanningLimits.maximumCandidateApplications)
        }
    }

    func testUnrelatedGoalsStillPrioritizeTheSnapshotAndBrowser() {
        let browser = AgentApplication(id: "com.apple.Safari", name: "Safari")
        let snapshotApp = AgentApplication(id: "com.apple.TextEdit", name: "TextEdit")
        let other = AgentApplication(id: "org.example.note", name: "Notes")
        let duplicate = AgentApplication(id: snapshotApp.id, name: "Duplicate", isRunning: false)

        let candidates = VyronOllamaAgentApplicationCatalog.rankedApplications(
            [other, browser, snapshotApp, duplicate], goal: "Read the website", snapshotApplicationID: snapshotApp.id
        )
        XCTAssertEqual(candidates, [snapshotApp, browser, other])
    }
}
