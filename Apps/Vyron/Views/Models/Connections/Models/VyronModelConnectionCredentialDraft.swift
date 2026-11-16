import Foundation

struct VyronModelConnectionCredentialDraft {
    var key = ""
    private var hadSavedKey = false
    private(set) var needsReplacement = false

    var hasKey: Bool { !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canSave: Bool { !needsReplacement || hasKey }

    mutating func loadSavedKey(_ savedKey: String) {
        key = savedKey
        hadSavedKey = hasKey
        needsReplacement = false
    }

    mutating func clearForServerChange() {
        key = ""
        needsReplacement = hadSavedKey
    }
}
