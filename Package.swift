// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vyron",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vyron", targets: ["Vyron"]),
        .executable(name: "VyronChromeHost", targets: ["VyronChromeHost"]),
        .library(name: "VyronCore", targets: ["VyronCore"]),
        .library(name: "VyronRuntime", targets: ["VyronRuntime"]),
        .library(name: "VyronAutomation", targets: ["VyronAutomation"]),
        .library(name: "VyronDevelopment", targets: ["VyronDevelopment"]),
        .library(name: "VyronModelDomain", targets: ["VyronModelDomain"]),
        .library(name: "VyronModelData", targets: ["VyronModelData"])
    ],
    targets: [
        .target(
            name: "VyronCore",
            dependencies: ["VyronDevelopment", "VyronModelDomain", "VyronModelData", "VyronLocalization"],
            path: "Packages/VyronCore",
            resources: [.copy("Office/Resources/vyron_office.py")]
        ),
        .target(name: "VyronRuntime", path: "Packages/VyronRuntime"),
        .target(name: "VyronAutomation", path: "Packages/VyronAutomation"),
        .executableTarget(
            name: "VyronChromeHost",
            dependencies: ["VyronAutomation"],
            path: "Apps/VyronChromeHost"
        ),
        .target(name: "VyronDevelopment", dependencies: ["VyronLocalization"], path: "Packages/VyronDevelopment"),
        .target(
            name: "VyronLocalization",
            path: "Packages/VyronLocalization",
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/tr.lproj"),
                .process("Resources/uk.lproj")
            ]
        ),
        .target(
            name: "VyronModelDomain",
            dependencies: ["VyronLocalization"],
            path: "Packages/VyronModelDomain"
        ),
        .target(
            name: "VyronModelData",
            dependencies: ["VyronModelDomain", "VyronLocalization"],
            path: "Packages/VyronModelData"
        ),
        .executableTarget(
            name: "Vyron",
            dependencies: [
                "VyronCore", "VyronRuntime", "VyronAutomation", "VyronDevelopment",
                "VyronModelDomain", "VyronModelData", "VyronLocalization"
            ],
            path: "Apps/Vyron",
            exclude: [
                "Resources/Localizable.xcstrings",
                "Resources/Symbols.json",
                "Resources/Strings.stencil",
                "Resources/Colors.stencil",
                "Resources/generate_resources.py"
            ],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/tr.lproj"),
                .process("Resources/uk.lproj"),
                .copy("Resources/Theme.xcassets"),
                .copy("Resources/CodexCatalog"),
                .copy("Resources/TrustedSkills")
            ]
        ),
        .testTarget(
            name: "VyronCoreTests",
            dependencies: [
                "VyronCore", "VyronAutomation", "VyronDevelopment", "VyronModelDomain",
                "VyronModelData", "VyronLocalization"
            ]
        ),
        .testTarget(
            name: "VyronTests",
            dependencies: [
                "Vyron", "VyronCore", "VyronAutomation", "VyronModelDomain", "VyronModelData", "VyronLocalization"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
