import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronCompatibleToolCall: Codable {
    let id: String
    let type: String
    let function: VyronCompatibleToolFunction

    init(_ call: DevelopmentToolCall) throws {
        guard let id = call.id, !id.isEmpty, id.count <= 512 else {
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.missingNativeToolCallID)
        }
        self.id = id
        type = "function"
        function = VyronCompatibleToolFunction(
            name: call.function.name,
            arguments: String(decoding: try JSONEncoder().encode(call.function.arguments), as: UTF8.self)
        )
    }

    func nativeCall() throws -> DevelopmentToolCall {
        guard type == "function", !id.isEmpty, id.count <= 512, function.arguments.utf8.count <= 64_000 else {
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.invalidNativeToolCall)
        }
        let arguments = try JSONDecoder().decode(
            [String: DevelopmentJSONValue].self,
            from: Data(function.arguments.utf8)
        )
        return DevelopmentToolCall(name: function.name, arguments: arguments, id: id)
    }
}
