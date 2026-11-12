import Foundation

struct VyronOfficeRuntimeRequest: Sendable {
    let operation: VyronOfficeOperation
    let input: VyronOfficeInput
    let pages: [Int]
}
