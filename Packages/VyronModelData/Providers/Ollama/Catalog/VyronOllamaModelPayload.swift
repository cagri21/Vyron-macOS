import Foundation
import VyronModelDomain

struct VyronOllamaModelPayload: Decodable {
    let name: String
    let size: Int64?
    let digest: String?
    let details: Details?
    let remote_model: String?
    let remote_host: String?
    let capabilities: [String]?
    var isRemote: Bool {
        !(remote_model ?? "").isEmpty || !(remote_host ?? "").isEmpty
    }
    var localModel: LocalModel {
        LocalModel(
            name: name,
            size: size ?? 0,
            parameterSize: details?.parameter_size,
            quantization: details?.quantization_level,
            capabilities: capabilities
        )
    }
}
