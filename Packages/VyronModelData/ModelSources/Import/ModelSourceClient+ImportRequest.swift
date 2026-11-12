extension ModelSourceClient {
    struct ImportRequest: Encodable { let model: String; let files: [String: String]; let stream = true }
}
