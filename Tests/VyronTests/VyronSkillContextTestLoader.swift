import Foundation
@testable import Vyron

actor VyronSkillContextTestLoader {
    private(set) var requests: [VyronSkillContextRequest] = []
    private var continuations: [Int: CheckedContinuation<VyronSkillRequestContext, any Error>] = [:]

    func load(_ request: VyronSkillContextRequest) async throws -> VyronSkillRequestContext {
        requests.append(request)
        let index = requests.count
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }

    func complete(_ index: Int, text: String) {
        continuations.removeValue(forKey: index)?.resume(returning: VyronSkillRequestContext(text: text, commands: []))
    }

    func resolve(_ index: Int, context: VyronSkillRequestContext) {
        continuations.removeValue(forKey: index)?.resume(returning: context)
    }
}
