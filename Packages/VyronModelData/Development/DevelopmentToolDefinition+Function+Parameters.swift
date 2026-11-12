import Foundation
import VyronModelDomain

extension DevelopmentToolDefinition.Function {
    struct Parameters: Encodable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
        let additionalProperties = false
        private var schema: [String: DevelopmentJSONValue]? = nil

        init(properties: [String: Property], required: [String]) {
            self.properties = properties; self.required = required
        }
        init(schema: [String: DevelopmentJSONValue]) { properties = [:]; required = []; self.schema = schema }
        func encode(to encoder: Encoder) throws {
            if let schema { try schema.encode(to: encoder); return }
            try Schema(properties: properties, required: required).encode(to: encoder)
        }
    }
}
