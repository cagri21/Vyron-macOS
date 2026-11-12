import Darwin

final class VyronProjectFileParent {
    let descriptor: Int32
    let leaf: String

    init(descriptor: Int32, leaf: String) {
        self.descriptor = descriptor
        self.leaf = leaf
    }

    deinit { close(descriptor) }
}
