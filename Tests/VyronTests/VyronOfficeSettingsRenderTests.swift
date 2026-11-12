import AppKit
import SwiftUI
import XCTest
import VyronLocalization
@testable import Vyron

/// Captures the production Office settings without opening windows or checking a runtime.
@MainActor
final class VyronOfficeSettingsRenderTests: XCTestCase {
    func testCaptureOfficeSettingsInEverySupportedLanguage() throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_OFFICE_SETTINGS"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_OFFICE_SETTINGS=1 for offscreen Office settings verification.")
        }
        let defaults = UserDefaults.standard
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/office", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for language in [VyronLanguage.english, .turkish, .ukrainian] {
            var arguments = previousArguments
            arguments[VyronLocalizationDefaultsKey.language.rawValue] = language.rawValue
            arguments[VyronUserDefaultsKey.officePythonExecutable.rawValue] = ""
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let renderer = ImageRenderer(content: VyronSettingsCard {
                VyronOfficeSettingsView()
            }
                .padding(VyronSettingsStyle.rowInset)
                .frame(width: VyronSettingsStyle.minimumContentWidth)
                .background(Palette.canvas)
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.colorScheme, .dark)
            )
            renderer.scale = 2
            guard let image = renderer.cgImage else {
                throw XCTSkip("BLOCKED: offscreen ImageRenderer unavailable; no app/window fallback permitted.")
            }
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("settings-" + language.rawValue + ".png"), options: .atomic)

            XCTAssertEqual(image.width, Int(VyronSettingsStyle.minimumContentWidth * 2))
            XCTAssertGreaterThan(image.height, 200)
            XCTAssertLessThan(image.height, 1_600, "Office setup guidance should fit the standard settings column.")
        }
    }
}
