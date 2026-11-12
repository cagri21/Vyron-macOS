extension ModelSourceClient {
    struct HubFile: Decodable { let type: String; let path: String; let size: Int64? }
}
