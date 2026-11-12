import Foundation
import VyronDevelopment

struct VyronOfficeProcessingResult: Sendable {
    let artifacts: [VyronOfficeArtifact]
    let warnings: [String]
}
