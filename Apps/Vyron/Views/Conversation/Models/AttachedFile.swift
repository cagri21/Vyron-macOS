struct AttachedFile: Identifiable {
    var id: String { path }
    let path: String
    let content: String
}
