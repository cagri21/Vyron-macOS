import Foundation

/// A borrowed file descriptor returned to the caller, which must close it after the operation.
struct VyronOfficeParent {
    let descriptor: Int32
    let leaf: String
}
