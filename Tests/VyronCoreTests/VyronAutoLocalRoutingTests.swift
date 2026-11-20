import Foundation
import XCTest
import VyronModelDomain
@testable import VyronModelData

@MainActor
final class VyronAutoLocalRoutingTests: XCTestCase {
    func testAssessesActualRecentConversationAndReferencesUsingOnlyTheLocalAssessor() async throws {
        let provider = VyronAutoLocalTestProvider(response: wire("local", complexity: "moderate"))
        let request = VyronAutoLocalRequest(
            assessor: LocalModel(name: "assessor:latest", size: 1),
            candidates: [candidate("local"), candidate("connected", location: .connected)],
            context: VyronAutoLocalContext(
                messages: [
                    ChatMessage(role: "system", content: "SYSTEM_DATA_MUST_NOT_BECOME_ROUTER_INSTRUCTION"),
                    ChatMessage(role: "user", content: "Fix the migration without losing saved profiles."),
                    ChatMessage(role: "assistant", content: "The existing identity must remain stable."),
                    ChatMessage(role: "user", content: "Continue with that compatibility requirement.")
                ],
                reference: "Attached source: migration reads legacy-profile.json",
                requiresTools: false,
                requiresImages: false
            ),
            effort: .automatic
        )

        let decision = try await VyronAutoLocalRouter.route(using: provider, request: request)
        let recorded = await provider.recordedRequests()
        let sent = try XCTUnwrap(recorded.first)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(sent.model, "assessor:latest")
        XCTAssertEqual(sent.configuration.effort, .quick)
        XCTAssertEqual(sent.configuration.purpose, .modelAssessment)
        XCTAssertEqual(VyronChatInferenceConfiguration(systemPrompt: nil, effort: .ultra).purpose, .conversation)
        XCTAssertEqual(sent.messages.count, 1)
        XCTAssertTrue(sent.messages[0].images?.isEmpty != false)
        let prompt = sent.messages[0].content
        XCTAssertTrue(prompt.contains("Fix the migration without losing saved profiles."))
        XCTAssertTrue(prompt.contains("Continue with that compatibility requirement."))
        XCTAssertTrue(prompt.contains("migration reads legacy-profile.json"))
        XCTAssertFalse(prompt.contains("SYSTEM_DATA_MUST_NOT_BECOME_ROUTER_INSTRUCTION"))
        XCTAssertTrue(sent.configuration.systemPrompt?.contains("Prefer a local candidate") == true)
        XCTAssertEqual(decision, VyronAutoLocalDecision(
            candidateID: "local", complexity: .moderate, thinkingLevel: nil
        ))
        XCTAssertEqual(decision.effectiveEffort(for: .automatic), .balanced)
    }

    func testConnectedSelectionAndSupportedReasoningAreRetainedWithoutChangingExplicitEffort() async throws {
        let remote = candidate(
            "frontier", location: .connected,
            thinking: .levels(VyronModelThinkingLevels(levels: [.low, .medium, .high]))
        )
        let provider = VyronAutoLocalTestProvider(response: wire("frontier", complexity: "complex", thinking: "high"))
        let decision = try await VyronAutoLocalRouter.route(
            using: provider, request: request(candidates: [candidate("local"), remote], effort: .quick)
        )
        XCTAssertEqual(decision.candidateID, "frontier")
        XCTAssertEqual(decision.complexity, .complex)
        XCTAssertEqual(decision.thinkingLevel, .high)
        XCTAssertEqual(decision.effectiveEffort(for: .automatic), .deep)
        for effort in AgentEffort.allCases where effort != .automatic {
            XCTAssertEqual(decision.effectiveEffort(for: effort), effort)
        }
        let recorded = await provider.recordedRequests()
        XCTAssertEqual(recorded.first?.model, "assessor:latest")
        XCTAssertEqual(recorded.first?.configuration.effort, .quick)
        XCTAssertEqual(recorded.first?.configuration.purpose, .modelAssessment)
        XCTAssertTrue(recorded.first?.messages.first?.content.contains("Requested effort: quick") == true)
    }

    func testReasoningIntensityOverridesComplexityOnlyWhenSupported() async throws {
        let supported = candidate("local", thinking: .levels(VyronModelThinkingLevels(levels: [.low, .high])))
        for (level, expected) in [("low", AgentEffort.quick), ("high", .deep)] {
            let decision = try await VyronAutoLocalRouter.route(
                using: VyronAutoLocalTestProvider(response: wire("local", complexity: "moderate", thinking: level)),
                request: request(candidates: [supported])
            )
            XCTAssertEqual(decision.effectiveEffort(for: .automatic), expected)
        }
        for support in [
            VyronModelThinkingSupport.unverified, .unsupported, .providerDefaultOnly,
            .levels(VyronModelThinkingLevels(levels: [.low]))
        ] {
            let decision = try await VyronAutoLocalRouter.route(
                using: VyronAutoLocalTestProvider(response: wire("local", complexity: "moderate", thinking: "high")),
                request: request(candidates: [candidate("local", thinking: support)])
            )
            XCTAssertNil(decision.thinkingLevel)
            XCTAssertEqual(decision.effectiveEffort(for: .automatic), .balanced)
        }
        let toggle = try await VyronAutoLocalRouter.route(
            using: VyronAutoLocalTestProvider(response: wire("local", complexity: "complex", thinking: "medium")),
            request: request(candidates: [candidate("local", thinking: .boolean)])
        )
        XCTAssertEqual(toggle.thinkingLevel, .medium)
        XCTAssertEqual(toggle.effectiveEffort(for: .automatic), .balanced)
    }

    func testRejectsMalformedOutputUnknownIdentifiersUnknownEnumsAndOversizedOutput() async throws {
        let invalid = [
            "",
            " \n\t ",
            "<think>Choose the local candidate.</think>",
            "<think>Choose the local candidate.</think>" + wire("local"),
            "A local model should answer.",
            "```json\n" + wire("local") + "\n```",
            wire("invented-provider"),
            wire("local", complexity: "unknown"),
            wire("local", thinking: "ultra"),
            #"{"candidateID":"local","complexity":"simple"}"#,
            #"{"candidateID":"local","complexity":"simple","thinkingLevel":null,"runTool":true}"#,
            #"{"candidateID":"local","complexity":1,"thinkingLevel":null}"#,
            String(repeating: " ", count: VyronAutoLocalLimits.maximumResponseBytes) + wire("local")
        ]
        for response in invalid {
            do {
                _ = try await VyronAutoLocalRouter.route(
                    using: VyronAutoLocalTestProvider(response: response), request: request()
                )
                XCTFail("Invalid assessment must stop before continuing: \(response.prefix(100))")
            } catch let error as ModelProviderError {
                guard case .invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testFiltersIncompatibleCapabilitiesAndNeverSuppliesImageBytesToTheAssessor() async throws {
        let chat = candidate("chat")
        let tools = candidate("tools", tools: true)
        let vision = VyronAutoLocalCandidate(
            id: "vision", model: LocalModel(name: "vision-frontier", size: 0, capabilities: ["tools", "vision"]),
            location: .connected, thinkingSupport: .unsupported
        )
        let image = VyronImageAttachment(name: "reference.png", mimeType: "image/png", data: Data("IMAGE_SECRET".utf8))
        let context = VyronAutoLocalContext(
            messages: [ChatMessage(role: "user", content: "Implement this screen.", images: [image])],
            reference: "", requiresTools: true, requiresImages: false
        )
        let scoped = VyronAutoLocalRequest(
            assessor: LocalModel(name: "assessor:latest", size: 1), candidates: [chat, tools, vision],
            context: context, effort: .automatic
        )
        let provider = VyronAutoLocalTestProvider(response: wire("vision"))
        let decision = try await VyronAutoLocalRouter.route(using: provider, request: scoped)
        XCTAssertEqual(decision.candidateID, "vision")
        let recorded = await provider.recordedRequests()
        let prompt = try XCTUnwrap(recorded.first?.messages.first?.content)
        XCTAssertTrue(prompt.contains("Requires images: true"))
        XCTAssertTrue(prompt.contains("\"id\":\"vision\""))
        XCTAssertFalse(prompt.contains("\"id\":\"chat\""))
        XCTAssertFalse(prompt.contains("\"id\":\"tools\""))
        XCTAssertFalse(prompt.contains("IMAGE_SECRET"))
        for id in ["chat", "tools"] {
            do {
                _ = try await VyronAutoLocalRouter.route(
                    using: VyronAutoLocalTestProvider(response: wire(id)), request: scoped
                )
                XCTFail("Capability-incompatible candidates cannot be selected")
            } catch let error as ModelProviderError {
                guard case .invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testBoundsLargeContextWhilePreservingLatestRequestAndBothEndsOfReferences() async throws {
        let longReference = "REFERENCE_START" + String(repeating: "😀\n", count: 12_000) + "REFERENCE_END"
        let longHistory = (0..<20).map { index in
            ChatMessage(role: "user", content: "Old \(index) " + String(repeating: "x", count: 5_000))
        } + [ChatMessage(role: "user", content: "LATEST_REQUEST: fix the issue described above")]
        let scoped = VyronAutoLocalRequest(
            assessor: LocalModel(name: "assessor:latest", size: 1), candidates: [candidate("local")],
            context: VyronAutoLocalContext(
                messages: longHistory, reference: longReference, requiresTools: false, requiresImages: false
            ),
            effort: .automatic
        )
        let provider = VyronAutoLocalTestProvider(response: wire("local"))
        _ = try await VyronAutoLocalRouter.route(using: provider, request: scoped)
        let recorded = await provider.recordedRequests()
        let sent = try XCTUnwrap(recorded.first)
        let prompt = sent.messages[0].content
        XCTAssertLessThanOrEqual(
            prompt.utf8.count + (sent.configuration.systemPrompt?.utf8.count ?? 0),
            VyronAutoLocalLimits.maximumPromptBytes
        )
        XCTAssertTrue(prompt.contains("LATEST_REQUEST: fix the issue described above"))
        XCTAssertTrue(prompt.contains("REFERENCE_START"))
        XCTAssertTrue(prompt.contains("REFERENCE_END"))
        XCTAssertTrue(prompt.contains("context truncated"))
        XCTAssertFalse(prompt.contains("Old 0 "))
    }

    func testCancellationStopsInFlightAssessmentAndCannotReturnAStaleDecision() async throws {
        let response = wire("local")
        let provider = VyronAutoLocalTestProvider { _, _ in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return response
        }
        let scoped = request()
        let task = Task { try await VyronAutoLocalRouter.route(using: provider, request: scoped) }
        await provider.waitUntilRequested()
        let sent = await provider.recordedRequests()
        XCTAssertEqual(sent.first?.model, scoped.assessor.name)
        XCTAssertEqual(sent.first?.configuration.effort, .quick)
        XCTAssertEqual(sent.first?.configuration.purpose, .modelAssessment)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A canceled assessment must not return a selection")
        } catch is CancellationError { }
        let canceledRequests = await provider.recordedRequests()
        XCTAssertEqual(canceledRequests.count, 1, "Cancellation must not start another assessment")

        let stale = VyronAutoLocalTestProvider { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return response
        }
        let staleTask = Task { try await VyronAutoLocalRouter.route(using: stale, request: scoped) }
        do {
            _ = try await staleTask.value
            XCTFail("Cancellation after an answer must still prevent continuation")
        } catch is CancellationError { }
    }

    func testFailedAssessmentCanBeRetriedWithoutRetainingThePreviousFailure() async throws {
        let response = wire("local")
        let provider = VyronAutoLocalTestProvider { _, count in
            if count == 1 { throw ModelProviderError.connectionFailed }
            return response
        }
        do {
            _ = try await VyronAutoLocalRouter.route(using: provider, request: request())
            XCTFail("The first failure must propagate")
        } catch let error as ModelProviderError {
            XCTAssertEqual(error, .connectionFailed)
        }
        let decision = try await VyronAutoLocalRouter.route(using: provider, request: request())
        XCTAssertEqual(decision.candidateID, "local")
        let recorded = await provider.recordedRequests()
        XCTAssertEqual(recorded.count, 2)
        XCTAssertTrue(recorded.allSatisfy {
            $0.model == "assessor:latest" && $0.configuration.effort == .quick
                && $0.configuration.purpose == .modelAssessment
        })
    }

    func testStreamedOutputBudgetRejectsAnOversizedStreamEvenWhenTheFinalStringIsShort() async throws {
        let provider = VyronAutoLocalTestProvider(
            response: wire("local"),
            emittedTokens: [String(repeating: "x", count: VyronAutoLocalLimits.maximumResponseBytes + 1)]
        )
        do {
            _ = try await VyronAutoLocalRouter.route(using: provider, request: request())
            XCTFail("An oversized assessment stream cannot continue")
        } catch let error as ModelProviderError {
            guard case .invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testProviderEmptyAnswerFailurePropagatesWithoutSelectingOrRetrying() async throws {
        let expected = LocalAIError.invalidResponse("The assessment finished without a visible answer.")
        let provider = VyronAutoLocalTestProvider { _, _ in throw expected }
        do {
            _ = try await VyronAutoLocalRouter.route(using: provider, request: request(effort: .ultra))
            XCTFail("An empty-answer provider failure cannot become a routing decision")
        } catch let error as LocalAIError {
            XCTAssertEqual(error, expected)
        }
        let recorded = await provider.recordedRequests()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.model, "assessor:latest")
        XCTAssertEqual(recorded.first?.configuration.effort, .quick)
        XCTAssertEqual(recorded.first?.configuration.purpose, .modelAssessment)
    }

    func testDuplicateIdentifiersEmptyCandidatesAndIneligibleLocalModelsStopBeforeInference() async throws {
        let invalid = [
            [],
            [candidate("same"), candidate("same", location: .connected)],
            [VyronAutoLocalCandidate(
                id: "cloud", model: LocalModel(name: "remote:cloud", size: 0),
                location: .local, thinkingSupport: .unsupported
            )],
            [VyronAutoLocalCandidate(
                id: "large", model: LocalModel(name: "qwen3-coder-next:q4_K_M", size: 52_000_000_000),
                location: .local, thinkingSupport: .unsupported
            )],
            [VyronAutoLocalCandidate(
                id: "embedding", model: LocalModel(name: "text-embedding:latest", size: 1),
                location: .local, thinkingSupport: .unsupported
            )]
        ]
        for candidates in invalid {
            let provider = VyronAutoLocalTestProvider(response: wire("same"))
            do {
                _ = try await VyronAutoLocalRouter.route(using: provider, request: request(candidates: candidates))
                XCTFail("Invalid request must not start inference")
            } catch let error as ModelProviderError {
                guard case .invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
            }
            let recorded = await provider.recordedRequests()
            XCTAssertTrue(recorded.isEmpty)
        }
    }

    func testAlreadyCancelledRequestDoesNotStartAssessment() async throws {
        let provider = VyronAutoLocalTestProvider(response: wire("local"))
        let scoped = request()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VyronAutoLocalRouter.route(using: provider, request: scoped)
        }
        do {
            _ = try await task.value
            XCTFail("Already canceled requests must stop before inference")
        } catch is CancellationError { }
        let recorded = await provider.recordedRequests()
        XCTAssertTrue(recorded.isEmpty)
    }

    func testEncodedPromptBudgetIncludesNestedJSONEscapesAndLeavesTransportHeadroom() async throws {
        let candidates = (0..<20).map { index in
            VyronAutoLocalCandidate(
                id: "candidate-\(index)",
                model: LocalModel(
                    name: "model-\(index):latest", size: 1,
                    parameterSize: String(repeating: "\\", count: 60), capabilities: ["completion"]
                ),
                location: .local, thinkingSupport: .unsupported
            )
        }
        let escaped = String(repeating: "\\\n", count: 12_000)
        let scoped = VyronAutoLocalRequest(
            assessor: LocalModel(name: "assessor:latest", size: 1), candidates: candidates,
            context: VyronAutoLocalContext(
                messages: [ChatMessage(role: "user", content: "LATEST_BEGIN" + escaped + "LATEST_END")],
                reference: "REFERENCE_BEGIN" + escaped + "REFERENCE_END", requiresTools: false, requiresImages: false
            ),
            effort: .automatic
        )
        let provider = VyronAutoLocalTestProvider(response: wire("candidate-0"))
        _ = try await VyronAutoLocalRouter.route(using: provider, request: scoped)
        let recorded = await provider.recordedRequests()
        let sent = try XCTUnwrap(recorded.first)
        let prompt = sent.messages[0].content
        let envelope = [
            ["role": "system", "content": sent.configuration.systemPrompt ?? ""],
            ["role": "user", "content": prompt]
        ]
        let encodedBytes = try JSONEncoder().encode(envelope).count
        XCTAssertLessThanOrEqual(encodedBytes, VyronAutoLocalLimits.maximumPromptBytes)
        XCTAssertLessThan(encodedBytes + 2_048 + AgentEffort.quick.developmentBudget.outputTokens, 32_768)
        for marker in ["LATEST_BEGIN", "LATEST_END", "REFERENCE_BEGIN", "REFERENCE_END"] {
            XCTAssertTrue(prompt.contains(marker))
        }
    }

    private nonisolated func wire(
        _ id: String,
        complexity: String = "simple",
        thinking: String? = nil
    ) -> String {
        let value = thinking.map { "\"\($0)\"" } ?? "null"
        return "{\"candidateID\":\"\(id)\",\"complexity\":\"\(complexity)\",\"thinkingLevel\":\(value)}"
    }

    private func candidate(
        _ id: String,
        tools: Bool = false,
        location: VyronAutoLocalLocation = .local,
        thinking: VyronModelThinkingSupport = .unsupported
    ) -> VyronAutoLocalCandidate {
        VyronAutoLocalCandidate(
            id: id,
            model: LocalModel(name: "\(id):latest", size: 1, capabilities: tools ? ["tools"] : ["completion"]),
            location: location, thinkingSupport: thinking
        )
    }

    private func request(
        candidates: [VyronAutoLocalCandidate]? = nil,
        effort: AgentEffort = .automatic
    ) -> VyronAutoLocalRequest {
        VyronAutoLocalRequest(
            assessor: LocalModel(name: "assessor:latest", size: 1), candidates: candidates ?? [candidate("local")],
            context: VyronAutoLocalContext(
                messages: [ChatMessage(role: "user", content: "Explain this request.")],
                reference: "", requiresTools: false, requiresImages: false
            ),
            effort: effort
        )
    }
}
