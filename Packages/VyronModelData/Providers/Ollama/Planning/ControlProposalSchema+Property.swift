extension ControlProposalSchema {
    struct Property: Encodable {
        let type: [String]
        let `enum`: [String]?
        let maxLength: Int?
        let minimum: Int?
        let maximum: Int?

        init(
            _ type: [String],
            values: [String]? = nil,
            maxLength: Int? = nil,
            minimum: Int? = nil,
            maximum: Int? = nil
        ) {
            self.type = type
            self.enum = values
            self.maxLength = maxLength
            self.minimum = minimum
            self.maximum = maximum
        }
    }
}
