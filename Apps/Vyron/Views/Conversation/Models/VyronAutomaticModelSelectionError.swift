import Foundation

struct VyronAutomaticModelSelectionError: LocalizedError {
    var errorDescription: String? {
        VyronStatusText.noAutomaticModel
    }
}
