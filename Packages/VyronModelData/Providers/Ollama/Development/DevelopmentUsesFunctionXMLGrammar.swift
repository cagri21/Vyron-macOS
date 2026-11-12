import Foundation
import VyronModelDomain

func developmentUsesFunctionXMLGrammar(_ model: String) -> Bool {
    String(model.split(separator: "/").last ?? "").lowercased().hasPrefix("qwen3-coder")
}
