import Foundation
import XCTest
import VyronAutomation
@testable import Vyron

@MainActor
final class VyronPermissionsViewModelTests: XCTestCase {
    func testPassiveRefreshReadsEveryPaneAndReflectsChangesWithoutPrompting() {
        var readings: [VyronMacPrivacyPane: VyronPermissionStatus] = [
            .accessibility: .notGranted,
            .screenRecording: .granted,
            .microphone: .restricted,
            .speechRecognition: .notRequested
        ]
        var queriedPanes: [VyronMacPrivacyPane] = []
        let model = VyronPermissionsViewModel(access: .init(
            status: { pane in
                queriedPanes.append(pane)
                return readings[pane] ?? .unavailable
            },
            request: { _ in XCTFail("Refreshing must not request access.") },
            openSettings: { _ in
                XCTFail("Refreshing must not open System Settings.")
                return false
            }
        ))

        model.refresh()
        XCTAssertEqual(queriedPanes, VyronMacPrivacyPane.allCases)
        for (pane, status) in readings {
            XCTAssertEqual(model.status(for: pane), status)
        }

        readings[.accessibility] = .granted
        readings[.screenRecording] = .notGranted
        readings[.speechRecognition] = .granted
        model.refresh()

        XCTAssertEqual(queriedPanes, VyronMacPrivacyPane.allCases + VyronMacPrivacyPane.allCases)
        for (pane, status) in readings {
            XCTAssertEqual(model.status(for: pane), status)
        }
    }

    func testOpeningSettingsRoutesToEachPrivacyPaneAndClearsAnEarlierError() {
        var openedURLs: [String?] = []
        let model = VyronPermissionsViewModel(access: .init(
            status: { _ in .notGranted },
            request: { _ in XCTFail("Opening System Settings must not request access.") },
            openSettings: { pane in
                openedURLs.append(pane.settingsURL?.absoluteString)
                return pane != .accessibility
            }
        ))

        for pane in VyronMacPrivacyPane.allCases {
            model.openSettings(for: pane)
            XCTAssertEqual(model.showsSettingsError, pane == .accessibility)
        }
        XCTAssertEqual(openedURLs, [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        ])
    }

    func testExplicitRequestSkipsDecidedStatesAndRefreshesAfterCompletion() async {
        var readings: [VyronMacPrivacyPane: VyronPermissionStatus] = [
            .accessibility: .granted,
            .screenRecording: .notGranted,
            .microphone: .notRequested,
            .speechRecognition: .restricted
        ]
        var requests: [VyronMacPrivacyPane] = []
        weak var observedModel: VyronPermissionsViewModel?
        let model = VyronPermissionsViewModel(access: .init(
            status: { pane in readings[pane] ?? .unavailable },
            request: { pane in
                requests.append(pane)
                XCTAssertEqual(observedModel?.pendingRequest, pane)
                XCTAssertEqual(observedModel?.isRequesting, true)
                readings[pane] = .granted
                readings[.screenRecording] = .granted
            },
            openSettings: { _ in false }
        ))
        observedModel = model

        model.queueRequest(for: .microphone)
        XCTAssertNil(model.pendingRequest)
        model.refresh()
        for pane in [VyronMacPrivacyPane.accessibility, .screenRecording, .speechRecognition] {
            model.queueRequest(for: pane)
            XCTAssertNil(model.pendingRequest)
            await model.requestPendingAccess()
        }
        XCTAssertTrue(requests.isEmpty)

        model.queueRequest(for: .microphone)
        XCTAssertEqual(model.pendingRequest, .microphone)
        XCTAssertTrue(requests.isEmpty)
        await model.requestPendingAccess()

        XCTAssertEqual(requests, [.microphone])
        XCTAssertNil(model.pendingRequest)
        XCTAssertFalse(model.isRequesting)
        XCTAssertEqual(model.status(for: .microphone), .granted)
        XCTAssertEqual(model.status(for: .screenRecording), .granted)
        model.queueRequest(for: .microphone)
        XCTAssertNil(model.pendingRequest)
    }

    func testCancellationBeforeRequestClearsThePendingActionAndAllowsRetry() async {
        var requests: [VyronMacPrivacyPane] = []
        let model = VyronPermissionsViewModel(access: .init(
            status: { pane in pane == .microphone ? .notRequested : .unavailable },
            request: { requests.append($0) },
            openSettings: { _ in false }
        ))
        model.refresh()
        model.queueRequest(for: .microphone)
        let cancelledRequest = Task { await model.requestPendingAccess() }
        cancelledRequest.cancel()
        await cancelledRequest.value

        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(model.pendingRequest)
        XCTAssertFalse(model.isRequesting)

        model.queueRequest(for: .microphone)
        await model.requestPendingAccess()
        XCTAssertEqual(requests, [.microphone])
    }
}
