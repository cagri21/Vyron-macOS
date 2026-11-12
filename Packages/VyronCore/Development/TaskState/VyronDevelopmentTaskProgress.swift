struct VyronDevelopmentTaskProgress: Codable, Sendable, Equatable {
    var fileEvidence = VyronDevelopmentTaskFileEvidence()
    var checks: [VyronDevelopmentCheckProgress] = []
    var integrations: [VyronDevelopmentIntegrationProgress] = []
    var context = VyronDevelopmentTaskContext()

    var files: [VyronDevelopmentFileProgress] {
        get { fileEvidence.files }
        set { fileEvidence.files = newValue }
    }

    var fileOperations: [VyronDevelopmentFileOperationEvidence] { fileEvidence.operations }
    var fileOperationIntents: [VyronDevelopmentFileOperationIntent] { fileEvidence.intents }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fileEvidence = VyronDevelopmentTaskFileEvidence(
            files: try values.decode([VyronDevelopmentFileProgress].self, forKey: .files),
            operations: try values.decodeIfPresent(
                [VyronDevelopmentFileOperationEvidence].self, forKey: .fileOperations
            ) ?? [],
            intents: try values.decodeIfPresent(
                [VyronDevelopmentFileOperationIntent].self, forKey: .fileOperationIntents
            ) ?? []
        )
        checks = try values.decode([VyronDevelopmentCheckProgress].self, forKey: .checks)
        integrations = try values.decode([VyronDevelopmentIntegrationProgress].self, forKey: .integrations)
        context = try values.decode(VyronDevelopmentTaskContext.self, forKey: .context)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(files, forKey: .files)
        try values.encode(checks, forKey: .checks)
        try values.encode(integrations, forKey: .integrations)
        try values.encode(context, forKey: .context)
        if !fileOperations.isEmpty { try values.encode(fileOperations, forKey: .fileOperations) }
        if !fileOperationIntents.isEmpty { try values.encode(fileOperationIntents, forKey: .fileOperationIntents) }
    }
}
