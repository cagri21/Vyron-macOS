import XCTest
import VyronAutomation
@testable import Vyron

final class VyronChatAppOpenRequestTests: XCTestCase {
    func testResolvesExplicitAppNamesAndBundleIdentifiers() {
        let photos = application("Photos", identifier: "com.apple.Photos")
        let quickTime = application("QuickTime Player", identifier: "com.apple.QuickTimePlayerX")
        let catalog = [photos, quickTime]

        XCTAssertEqual(VyronChatAppOpenRequest.resolve("open photos app", applications: catalog), photos)
        XCTAssertEqual(VyronChatAppOpenRequest.resolve("Open QuickTime Player", applications: catalog), quickTime)
        XCTAssertEqual(VyronChatAppOpenRequest.resolve("Can you open the Photos app?", applications: catalog), photos)
        XCTAssertEqual(VyronChatAppOpenRequest.resolve("Launch COM.APPLE.PHOTOS", applications: catalog), photos)
        XCTAssertEqual(VyronChatAppOpenRequest.resolve("Please open Photos.app.", applications: catalog), photos)
    }

    func testExactNamesTakePrecedenceOverDecorations() {
        let archive = application("Archive", identifier: "com.example.archive")
        let namedApp = application("The Archive App", identifier: "com.example.the-archive-app")

        XCTAssertEqual(
            VyronChatAppOpenRequest.resolve("Open the Archive App", applications: [archive, namedApp]),
            namedApp
        )
    }

    func testAmbiguousNamesAndPartialMatchesStayUnresolved() {
        let photos = application("Photos", identifier: "com.apple.Photos")
        let otherPhotos = application("Photos", identifier: "com.example.photos")
        let catalog = [photos, otherPhotos]

        XCTAssertNil(VyronChatAppOpenRequest.resolve("Open Photos", applications: catalog))
        XCTAssertNil(VyronChatAppOpenRequest.resolve("Open Photo", applications: catalog))
        XCTAssertEqual(VyronChatAppOpenRequest.resolve("Open com.apple.Photos", applications: catalog), photos)
    }

    func testQuotedAndInformationalRequestsDoNotReadTheAppCatalog() {
        let prompts = ["\"Open Photos\"", "> Open Photos", "How do I open Photos?", "Open Photos\nThen start a slideshow"]

        for prompt in prompts {
            XCTAssertNil(VyronChatAppOpenRequest.resolve(prompt, applications: unexpectedCatalogRead()))
        }
    }

    func testMultiStepCommandsStayUnresolved() {
        let photos = application("Photos", identifier: "com.apple.Photos")

        XCTAssertNil(VyronChatAppOpenRequest.resolve("Open Photos and start a slideshow", applications: [photos]))
    }

    private func application(_ name: String, identifier: String) -> DesktopApplication {
        DesktopApplication(id: identifier, name: name, bundleIdentifier: identifier, processIdentifier: 0)
    }

    private func unexpectedCatalogRead() -> [DesktopApplication] {
        XCTFail("Unexpected app catalog read")
        return []
    }
}
