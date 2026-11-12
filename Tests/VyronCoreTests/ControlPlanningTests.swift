import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

private final class PlanningStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (Int, String))?

    func set(_ handler: (@Sendable (URLRequest) throws -> (Int, String))?) {
        lock.withLock { self.handler = handler }
    }

    func handle(_ request: URLRequest) throws -> (Int, String) {
        guard let handler = lock.withLock({ handler }) else { throw URLError(.unsupportedURL) }
        return try handler(request)
    }
}

private final class PlanningURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = PlanningStubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.state.handle(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private final class IntentModelTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    func append(_ name: String) { lock.withLock { names.append(name) } }
    var values: [String] { lock.withLock { names } }
}

private func planningRequestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}

final class ControlPlanningTests: XCTestCase, @unchecked Sendable {
    private let browser = "com.apple.Safari"
    private let editor = "com.apple.TextEdit"
    private let catalog = #"{"models":[{"name":"qwen3-coder:30b","size":19000000000}]}"#

    override func tearDown() {
        PlanningURLProtocol.state.set(nil)
        super.tearDown()
    }

    private func client(endpoint: String = "http://127.0.0.1:11434") -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlanningURLProtocol.self]
        return OllamaClient(baseURL: URL(string: endpoint)!, configuration: configuration)
    }

    private func response(_ proposal: ControlProposal, done: Bool = true) throws -> String {
        let proposalJSON = String(decoding: try JSONEncoder().encode(proposal), as: UTF8.self)
        let object: [String: Any] = [
            "message": ["content": proposalJSON, "thinking": "NATIVE_REASONING_MARKER"], "done": done
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func response(_ route: AssistantRoute, done: Bool = true) throws -> String {
        let routeJSON = String(decoding: try JSONEncoder().encode(route), as: UTF8.self)
        let object: [String: Any] = [
            "message": ["content": routeJSON, "thinking": "NATIVE_REASONING_MARKER"], "done": done
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func testIntentRoutesDefaultToConversationAndCannotExpandTheLatestGoal() throws {
        let conversation = try AssistantRoute(mode: .conversation).validated(for: "What is 2+2?")
        XCTAssertEqual(conversation.mode, .conversation)
        XCTAssertNil(conversation.goal)
        XCTAssertThrowsError(try AssistantRoute(mode: .conversation, goal: "Open Calculator").validated(for: "What is 2+2?"))
        XCTAssertThrowsError(try AssistantRoute(mode: .clarify).validated(for: "Do it"))
        let task = try AssistantRoute(mode: .computerTask, goal: "Open Calculator and send an email.", effort: .quick).validated(for: " Open Calculator ")
        XCTAssertEqual(task.goal, "Open Calculator")
        XCTAssertNil(task.clarification)
        let howTo = try AssistantRoute(mode: .computerTask).validated(for: "How can I open Calculator?")
        XCTAssertEqual(howTo.mode, .conversation)
        XCTAssertNil(howTo.goal)
    }

    func testInformationalOrAmbiguousMessagesCannotBecomeActionAuthority() throws {
        for text in ["What happens if I open Calculator?", "Explain how Safari opens links", "Can I open Calculator offline?", "How would one open Calculator?", "What if I open Safari?"] {
            XCTAssertEqual(try AssistantRoute(mode: .computerTask).validated(for: text).mode, .conversation, text)
        }
        XCTAssertEqual(try AssistantRoute(mode: .computerTask).validated(for: "Can you open Calculator?").mode, .computerTask)
        let ambiguous = try AssistantRoute(mode: .computerTask).validated(for: "Do it.")
        XCTAssertEqual(ambiguous.mode, .clarify)
        XCTAssertNil(ambiguous.goal)
    }

    func testCodingConversationRequestsUseTheStrongerResponseEffort() throws {
        XCTAssertEqual(try AssistantRoute(mode: .conversation, effort: .quick).validated(for: "Write a SwiftUI view with a button.").effort, .balanced)
        XCTAssertEqual(try AssistantRoute(mode: .conversation, effort: .quick).validated(for: "Debug this Swift compiler error.").effort, .deep)
        XCTAssertEqual(try AssistantRoute(mode: .conversation, effort: .quick).validated(for: "Refactor this function.").effort, .deep)
        XCTAssertEqual(try AssistantRoute(mode: .computerTask, effort: .quick).validated(for: "Write a SwiftUI view.").mode, .conversation)
    }

    func testIntentRouterRetriesMalformedSmallModelJSONOnceWithInstalledCoder() async throws {
        let trace = IntentModelTrace()
        let valid = try response(AssistantRoute(mode: .conversation, effort: .balanced))
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" {
                return (200, #"{"models":[{"name":"tiny-chat:latest","size":2000000000,"capabilities":["completion"]},{"name":"qwen3-coder:30b","size":19000000000,"capabilities":["completion","tools"]}]}"#)
            }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            let model = try XCTUnwrap(body["model"] as? String)
            trace.append(model)
            if model == "tiny-chat:latest" { return (200, #"{"message":{"content":"This is prose instead of routing JSON."},"done":true}"#) }
            XCTAssertEqual(model, "qwen3-coder:30b")
            return (200, valid)
        }
        let route = try await client().routeRequest(text: "Write a SwiftUI view.")
        XCTAssertEqual(route.mode, .conversation)
        XCTAssertEqual(route.effort, .balanced)
        XCTAssertEqual(trace.values, ["tiny-chat:latest", "qwen3-coder:30b"])
    }

    func testIntentRoutesRejectUnknownModesAndActionFields() throws {
        for json in [
            #"{"mode":"execute","goal":"Open Calculator","effort":"quick"}"#,
            #"{"mode":"computerTask","goal":null,"effort":"quick","shell":"echo hello"}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(AssistantRoute.self, from: Data(json.utf8)))
        }
    }

    func testIntentRouterUsesQuickLocalModelAndBoundedReferenceConversation() async throws {
        let wireResponse = try response(AssistantRoute(mode: .conversation))
        PlanningURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags":
                return (200, #"{"models":[{"name":"qwen3-coder:30b","size":19000000000},{"name":"qwen3:4b","size":2500000000,"capabilities":["completion","thinking","tools"]}]}"#)
            case "/api/show":
                return (200, #"{"capabilities":["completion","thinking","tools"],"thinking":{"values":[false,true]}}"#)
            default:
                XCTAssertEqual(request.url?.path, "/api/chat")
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
                XCTAssertEqual(body["model"] as? String, "qwen3:4b")
                XCTAssertNil(body["think"])
                XCTAssertEqual((body["options"] as? [String: Int])?["num_predict"], 4_096)
                XCTAssertNil(body["applications"])
                XCTAssertNil(body["snapshot"])
                let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
                XCTAssertTrue(messages[0]["content"]!.contains("ONLY authority"))
                let user = messages[1]["content"]!
                let recent = user.components(separatedBy: "<recent>\n")[1].components(separatedBy: "\n</recent>")[0]
                XCTAssertLessThanOrEqual(recent.utf8.count, 3_072)
                XCTAssertFalse(recent.contains("OLD_REFERENCE_TO_OMIT"))
                XCTAssertFalse(recent.contains("�"))
                XCTAssertTrue(user.contains("How can I open Calculator?"))
                return (200, wireResponse)
            }
        }
        let route = try await client().routeRequest(
            text: "How can I open Calculator?",
            recentConversation: [ChatMessage(role: "assistant", content: "OLD_REFERENCE_TO_OMIT" + String(repeating: "界", count: 4_000))],
            preferredModel: "qwen3-coder:30b"
        )
        XCTAssertEqual(route.mode, .conversation)
        XCTAssertNil(route.goal)
    }

    func testIntentRouterReturnsLatestTextVerbatimForComputerTask() async throws {
        let catalog = catalog
        let taskResponse = try response(AssistantRoute(mode: .computerTask, goal: "Open Calculator and publish the result.", effort: .quick))
        PlanningURLProtocol.state.set { request in
            request.url?.path == "/api/tags" ? (200, catalog) : (200, taskResponse)
        }
        let route = try await client().routeRequest(text: "Open Calculator", preferredModel: "qwen3-coder:30b")
        XCTAssertEqual(route.mode, .computerTask)
        XCTAssertEqual(route.goal, "Open Calculator")
        XCTAssertEqual(route.effort, .quick)
    }

    func testIntentRouterCanClarifyWithoutStartingAnAction() async throws {
        let catalog = catalog
        let clarify = try response(AssistantRoute(mode: .clarify, clarification: "Which app and action do you mean?"))
        PlanningURLProtocol.state.set { request in
            request.url?.path == "/api/tags" ? (200, catalog) : (200, clarify)
        }
        let route = try await client().routeRequest(text: "Do it")
        XCTAssertEqual(route.mode, .clarify)
        XCTAssertNil(route.goal)
        XCTAssertEqual(route.clarification, "Which app and action do you mean?")
    }

    func testIntentRouterRejectsInvalidInputAndCloudOnlyModelsBeforeSendingText() async throws {
        PlanningURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            return (200, #"{"models":[{"name":"alias:latest","remote_host":"https://ollama.com","remote_model":"remote"}]}"#)
        }
        do {
            _ = try await client().routeRequest(text: " ")
            XCTFail("Expected empty input rejection")
        } catch {
            XCTAssertEqual(error as? IntentRoutingError, .invalidText)
        }
        do {
            _ = try await client().routeRequest(text: "Open Calculator")
            XCTFail("A cloud alias must not classify the request")
        } catch {
            XCTAssertEqual(error as? AgentPlanningError, .noEligibleModel)
        }
    }

    func testProposalValidatesTargetAndVisibleElement() throws {
        let proposal = ControlProposal(kind: .click, applicationID: browser, elementID: 8, explanation: "Click the address field.")
        XCTAssertEqual(try proposal.validated(expectedApplicationID: browser, availableElementIDs: [2, 8]), proposal)
        XCTAssertThrowsError(try proposal.validated(expectedApplicationID: editor))
        XCTAssertThrowsError(try proposal.validated(availableElementIDs: [2, 3]))
        XCTAssertThrowsError(try ControlProposal(kind: .click, applicationID: browser, elementID: -1, explanation: "Click.").validated())
    }

    func testActionKindsRejectUnexpectedPayloadFields() throws {
        for kind in [ControlProposal.Kind.inspect, .activate] {
            XCTAssertNoThrow(try ControlProposal(kind: kind, applicationID: editor, explanation: "Inspect the current window.").validated())
            XCTAssertThrowsError(try ControlProposal(kind: kind, applicationID: editor, text: "unexpected", explanation: "Inspect.").validated())
        }
        XCTAssertThrowsError(try ControlProposal(kind: .click, applicationID: browser, explanation: "Click.").validated())
        XCTAssertThrowsError(try ControlProposal(kind: .click, applicationID: browser, elementID: 1, url: "https://example.com", explanation: "Click.").validated())
        XCTAssertThrowsError(try ControlProposal(kind: .typeText, applicationID: editor, text: "", explanation: "Type.").validated())
    }

    func testCompleteIsAReportWithoutAnActionPayload() throws {
        let complete = ControlProposal(kind: .complete, applicationID: browser, explanation: "The current snapshot shows Example Domain at https://example.com.")
        XCTAssertEqual(try complete.validated(expectedApplicationID: browser), complete)
        let data = try JSONEncoder().encode(complete)
        XCTAssertEqual(try JSONDecoder().decode(ControlProposal.self, from: data), complete)
        for proposal in [
            ControlProposal(kind: .complete, applicationID: browser, elementID: 1, explanation: "Complete."),
            ControlProposal(kind: .complete, applicationID: browser, text: "unexpected", explanation: "Complete."),
            ControlProposal(kind: .complete, applicationID: browser, url: "https://example.com", explanation: "Complete."),
            ControlProposal(kind: .complete, applicationID: browser, key: "return", explanation: "Complete.")
        ] {
            XCTAssertThrowsError(try proposal.validated())
        }
    }

    func testWaitUsesOnlyBoundedSecondsAndAnApplication() throws {
        for seconds in [5, 30, 60] {
            let wait = ControlProposal(kind: .wait, applicationID: browser, seconds: seconds, explanation: "Wait for the visible loading indicator.")
            XCTAssertEqual(try wait.validated(), wait)
        }
        for seconds in [nil, 4, 61, -1] as [Int?] {
            XCTAssertThrowsError(try ControlProposal(kind: .wait, applicationID: browser, seconds: seconds, explanation: "Wait.").validated())
        }
        XCTAssertThrowsError(try ControlProposal(kind: .wait, applicationID: browser, text: "unexpected", seconds: 10, explanation: "Wait.").validated())
        XCTAssertThrowsError(try ControlProposal(kind: .inspect, applicationID: browser, seconds: 10, explanation: "Inspect.").validated())
    }

    func testAdaptiveEffortUsesGoalComplexityAndRepeatedFailures() {
        XCTAssertEqual(AgentEffort.automatic.resolved(for: "Open Safari"), .quick)
        XCTAssertEqual(AgentEffort.automatic.resolved(for: "Find the documentation and read the setup section"), .balanced)
        XCTAssertEqual(AgentEffort.automatic.resolved(for: "Compare these two setup guides"), .deep)
        XCTAssertEqual(AgentEffort.automatic.resolved(for: "Open Safari", failureCount: 1), .balanced)
        XCTAssertEqual(AgentEffort.automatic.resolved(for: "Open Safari", failureCount: 2), .deep)
        XCTAssertEqual(AgentEffort.quick.resolved(for: "Compare these guides", failureCount: 3), .quick)
    }

    func testAgentBudgetsIncreaseWithEffortAndFitTheContextLimit() throws {
        let quick = AgentBudget.forEffort(.quick)
        let balanced = AgentBudget.forEffort(.balanced)
        let deep = AgentBudget.forEffort(.deep)
        XCTAssertLessThan(quick.outputTokens, balanced.outputTokens)
        XCTAssertLessThan(balanced.outputTokens, deep.outputTokens)
        XCTAssertLessThan(quick.maxSteps, balanced.maxSteps)
        XCTAssertLessThan(balanced.maxSteps, deep.maxSteps)
        let fitted = try quick.fitting(baseInputBytes: 20_000)
        XCTAssertLessThanOrEqual(fitted.contextTokens, 32_768)
        XCTAssertLessThanOrEqual(20_000 + fitted.snapshotBytes + fitted.historyBytes + fitted.outputTokens + 2_048, fitted.contextTokens)
        XCTAssertThrowsError(try deep.fitting(baseInputBytes: 40_000))
    }

    func testModelRoutingUsesInstalledModelsAndExcludesCloudOrEmbeddingModels() {
        let small = LocalModel(name: "small-chat:3b", size: 2_000_000_000, capabilities: ["completion"])
        let coder = LocalModel(name: "qwen3-coder:30b", size: 19_000_000_000, capabilities: ["completion", "tools"])
        let embedding = LocalModel(name: "ordinary-name:latest", size: 1_000_000_000, capabilities: ["embedding"])
        let cloud = LocalModel(name: "large:cloud", size: 1)
        let installed = [coder, small, embedding, cloud]
        XCTAssertEqual(AgentModelRouter.selectModel(from: installed, preferredModel: coder.name, effort: .quick), small)
        XCTAssertEqual(AgentModelRouter.selectModel(from: installed, preferredModel: small.name, effort: .deep), coder)
        for effort in [AgentEffort.quick, .balanced, .deep] {
            XCTAssertEqual(AgentModelRouter.selectModel(from: [coder], effort: effort), coder)
        }
        XCTAssertNil(AgentModelRouter.selectModel(from: [embedding, cloud], effort: .balanced))
    }

    func testAgentRoutesOnlyToCatalogApplicationsAndLaunchesOnlyInstalledStoppedApps() throws {
        let applications = [AgentApplication(id: browser, name: "Safari"), AgentApplication(id: editor, name: "TextEdit", isRunning: false)]
        XCTAssertNoThrow(try validatedAgentProposal(ControlProposal(kind: .launch, applicationID: editor, explanation: "Open TextEdit for the note."), applications: applications, snapshot: nil))
        XCTAssertNoThrow(try validatedAgentProposal(ControlProposal(kind: .inspect, applicationID: browser, explanation: "Read the browser controls."), applications: applications, snapshot: nil))
        XCTAssertThrowsError(try validatedAgentProposal(ControlProposal(kind: .activate, applicationID: "com.unknown.App", explanation: "Activate."), applications: applications, snapshot: nil))
        XCTAssertThrowsError(try validatedAgentProposal(ControlProposal(kind: .launch, applicationID: browser, explanation: "Launch."), applications: applications, snapshot: nil))
        XCTAssertThrowsError(try validatedAgentProposal(ControlProposal(kind: .inspect, applicationID: editor, explanation: "Inspect."), applications: applications, snapshot: nil))
    }

    func testAgentMutationsAndCompletionRequireFreshMatchingSnapshotAndKnownElements() throws {
        let applications = [AgentApplication(id: browser, name: "Safari"), AgentApplication(id: editor, name: "TextEdit")]
        let fresh = AgentSnapshot(applicationID: browser, text: "[1] Button · Back {click}\n[2] TextField · Search {set text}")
        let click = ControlProposal(kind: .click, applicationID: browser, elementID: 1, explanation: "Click Back.")
        XCTAssertNoThrow(try validatedAgentProposal(click, applications: applications, snapshot: fresh))
        XCTAssertThrowsError(try validatedAgentProposal(click, applications: applications, snapshot: nil))
        XCTAssertThrowsError(try validatedAgentProposal(click, applications: applications, snapshot: AgentSnapshot(applicationID: editor, text: "[1] Button · Back")))
        XCTAssertThrowsError(try validatedAgentProposal(click, applications: applications, snapshot: AgentSnapshot(applicationID: browser, text: fresh.text, capturedAt: Date().addingTimeInterval(-31))))
        XCTAssertThrowsError(try validatedAgentProposal(click, applications: applications, snapshot: AgentSnapshot(applicationID: browser, text: fresh.text, capturedAt: Date().addingTimeInterval(10))))
        XCTAssertThrowsError(try validatedAgentProposal(ControlProposal(kind: .click, applicationID: browser, elementID: 99, explanation: "Click."), applications: applications, snapshot: fresh))
        XCTAssertThrowsError(try validatedAgentProposal(ControlProposal(kind: .complete, applicationID: browser, explanation: "Done."), applications: applications, snapshot: nil))
    }

    func testAgentSelectsAnAvailableApplicationWithoutAChosenSnapshot() async throws {
        let catalog = catalog
        let launch = try response(ControlProposal(kind: .launch, applicationID: editor, explanation: "TextEdit is installed and can hold the requested note."))
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, catalog) }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertTrue(messages[0]["content"]!.contains("Never delegate reasoning"))
            XCTAssertTrue(messages[0]["content"]!.contains("separate deterministic policy"))
            XCTAssertTrue(messages[1]["content"]!.contains("com.apple.TextEdit"))
            XCTAssertTrue(messages[1]["content"]!.contains("installed-not-running"))
            return (200, launch)
        }
        let decision = try await client().planAgent(
            model: "qwen3-coder:30b", goal: "Write a short note in TextEdit.",
            applications: [AgentApplication(id: browser, name: "Safari"), AgentApplication(id: editor, name: "TextEdit", isRunning: false)],
            snapshot: nil, history: ""
        )
        XCTAssertEqual(decision.proposal.kind, .launch)
        XCTAssertEqual(decision.proposal.applicationID, editor)
        XCTAssertEqual(decision.model, "qwen3-coder:30b")
        XCTAssertEqual(decision.effort, .balanced)
    }

    func testAgentBoundsUnicodeInputAndUsesTheReportedBudget() async throws {
        let catalog = catalog
        let inspect = try response(ControlProposal(kind: .inspect, applicationID: browser, explanation: "Read the relevant page."))
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, catalog) }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            let options = try XCTUnwrap(body["options"] as? [String: Int])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let bytes = messages.reduce(0) { $0 + ($1["content"]?.utf8.count ?? 0) }
            XCTAssertLessThanOrEqual(bytes + options["num_predict"]! + 1_500, options["num_ctx"]!)
            XCTAssertFalse(messages[1]["content"]!.contains("OLD_HISTORY_TO_OMIT"))
            XCTAssertFalse(messages[1]["content"]!.contains("�"))
            return (200, inspect)
        }
        let decision = try await client().planAgent(
            model: "qwen3-coder:30b", goal: String(repeating: "界", count: 3_000),
            applications: [AgentApplication(id: browser, name: "Safari")],
            snapshot: AgentSnapshot(applicationID: browser, text: String(repeating: "界", count: 20_000)),
            history: "OLD_HISTORY_TO_OMIT" + String(repeating: "界", count: 8_000), failureCount: 2
        )
        XCTAssertEqual(decision.effort, .deep)
        XCTAssertEqual(decision.budget.outputTokens, 1_536)
        XCTAssertLessThanOrEqual(decision.budget.contextTokens, 32_768)
    }

    func testAgentRejectsCloudOnlyCatalogBeforeSendingGoalOrSnapshot() async throws {
        PlanningURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            return (200, #"{"models":[{"name":"alias:latest","remote_model":"remote","remote_host":"https://ollama.com"}]}"#)
        }
        do {
            _ = try await client().planAgent(model: "alias", goal: "Inspect Safari", applications: [AgentApplication(id: browser, name: "Safari")], snapshot: nil, history: "PRIVATE")
            XCTFail("Cloud aliases must not receive the task")
        } catch {
            XCTAssertEqual(error as? AgentPlanningError, .noEligibleModel)
        }
    }

    func testAgentCannotUseAnElementOmittedFromTheBoundedModelSnapshot() async throws {
        let catalog = catalog
        let unseenClick = try response(ControlProposal(kind: .click, applicationID: browser, elementID: 99, explanation: "Click the requested item."))
        PlanningURLProtocol.state.set { request in
            request.url?.path == "/api/tags" ? (200, catalog) : (200, unseenClick)
        }
        do {
            _ = try await client().planAgent(
                model: "qwen3-coder:30b", goal: "Click the requested item.",
                applications: [AgentApplication(id: browser, name: "Safari")],
                snapshot: AgentSnapshot(applicationID: browser, text: "[1] Button · Back\n" + String(repeating: "x", count: 20_000) + "\n[99] Button · Requested item"),
                history: ""
            )
            XCTFail("An element not actually sent to the model must not be actionable")
        } catch {
            XCTAssertTrue(error is ControlPlanningError)
        }
    }

    func testQuickThinkingModelKeepsNativeDefaultAndStructuredOutputHeadroom() async throws {
        let catalog = #"{"models":[{"name":"qwen3-coder:30b","size":19000000000,"capabilities":["completion","tools"]},{"name":"qwen3:4b","size":2500000000,"capabilities":["completion","tools","thinking"]}]}"#
        let inspect = try response(ControlProposal(kind: .inspect, applicationID: browser, explanation: "Read Safari's current state."))
        PlanningURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags": return (200, catalog)
            case "/api/show":
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
                XCTAssertEqual(body["model"] as? String, "qwen3:4b")
                return (200, #"{"capabilities":["completion","tools","thinking"],"thinking":{"values":[false,true],"default":true}}"#)
            default:
                XCTAssertEqual(request.url?.path, "/api/chat")
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
                XCTAssertEqual(body["model"] as? String, "qwen3:4b")
                XCTAssertNil(body["think"])
                XCTAssertEqual((body["options"] as? [String: Int])?["num_predict"], 4_096)
                return (200, inspect)
            }
        }
        let decision = try await client().planAgent(model: "qwen3-coder:30b", goal: "Open Safari", applications: [AgentApplication(id: browser, name: "Safari")], snapshot: nil, history: "")
        XCTAssertEqual(decision.effort, .quick)
        XCTAssertEqual(decision.model, "qwen3:4b")
    }

    func testStructuredQwenPlannerKeepsNativeDefaultWhenTagsOmitCapabilities() async throws {
        let inspect = try response(ControlProposal(kind: .inspect, applicationID: browser, explanation: "Read the current page."))
        PlanningURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags": return (200, #"{"models":[{"name":"qwen3:4b","size":2500000000}]}"#)
            case "/api/show": return (200, #"{"capabilities":["completion","tools","thinking"],"thinking":{"values":[false,true],"default":true}}"#)
            default:
                XCTAssertEqual(request.url?.path, "/api/chat")
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
                XCTAssertNil(body["think"])
                return (200, inspect)
            }
        }
        _ = try await client().proposeControl(model: "qwen3:4b", instruction: "Inspect Safari", snapshot: "[1] Button · Back", applicationID: browser)
    }

    func testExplicitOffRetainsSmallRoutingAndControlBudgets() async throws {
        let wireRoute = try response(AssistantRoute(mode: .conversation))
        let wireControl = try response(ControlProposal(kind: .inspect, applicationID: browser, explanation: "Read Safari."))
        PlanningURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags":
                return (200, #"{"models":[{"name":"qwen3:4b","size":2500000000,"capabilities":["completion","thinking","tools"]}]}"#)
            case "/api/show":
                return (200, #"{"capabilities":["completion","thinking","tools"],"thinking":{"values":[false,true]}}"#)
            default:
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
                XCTAssertEqual(body["think"] as? Bool, false)
                let schema = body["format"] as? [String: Any]
                let properties = schema?["properties"] as? [String: Any]
                let routing = properties?["mode"] != nil
                XCTAssertEqual((body["options"] as? [String: Int])?["num_predict"], routing ? 384 : 512)
                return (200, routing ? wireRoute : wireControl)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlanningURLProtocol.self]
        let profile = ModelConnectionProfile(
            name: "Off fixture", kind: .ollama, endpoint: "http://localhost:11434",
            selectedModel: "qwen3:4b", settings: ModelSettings(thinking: false)
        )
        let selected = try OllamaClient(connection: profile, configuration: configuration)
        let route = try await selected.routeRequest(text: "Hello", preferredModel: "qwen3:4b")
        XCTAssertEqual(route.mode, .conversation)
        let proposal = try await selected.proposeControl(
            model: "qwen3:4b", instruction: "Inspect Safari", snapshot: "[1] Button", applicationID: browser
        )
        XCTAssertEqual(proposal.kind, .inspect)
    }

    func testStructuredNonThinkingModelOmitsThinkOption() async throws {
        let inspect = try response(ControlProposal(kind: .inspect, applicationID: browser, explanation: "Read the page."))
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" {
                return (200, #"{"models":[{"name":"qwen3-coder:30b","size":19000000000,"capabilities":["completion","tools"]}]}"#)
            }
            XCTAssertEqual(request.url?.path, "/api/chat", "Non-thinking metadata must not trigger an unnecessary show request")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            XCTAssertNil(body["think"])
            return (200, inspect)
        }
        _ = try await client().planAgent(model: "qwen3-coder:30b", goal: "Read the page", applications: [AgentApplication(id: browser, name: "Safari")], snapshot: nil, history: "")
    }

    func testStructuredNamedThinkingLevelsDoNotReceiveUnsupportedBoolean() async throws {
        let inspect = try response(ControlProposal(kind: .inspect, applicationID: browser, explanation: "Read the page."))
        PlanningURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags": return (200, #"{"models":[{"name":"named-thinker:latest","size":10000000000,"capabilities":["completion","thinking"]}]}"#)
            case "/api/show": return (200, #"{"capabilities":["completion","thinking"],"thinking":{"values":["low","medium","high"],"default":"medium"}}"#)
            default:
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
                XCTAssertNil(body["think"])
                return (200, inspect)
            }
        }
        _ = try await client().proposeControl(model: "named-thinker", instruction: "Inspect Safari", snapshot: "[1] Button · Back", applicationID: browser)
    }

    func testWebNavigationAllowsOnlyCredentialFreeHTTPURLsInBrowsers() throws {
        for url in ["https://example.com/path?q=hello#section", "http://localhost:8080/"] {
            XCTAssertNoThrow(try ControlProposal(kind: .openURL, applicationID: browser, url: url, explanation: "Open the requested page.").validated())
        }
        for url in ["file:///etc/passwd", "javascript:alert(1)", "mailto:test@example.com", "https://user:pass@example.com", "https://example.com\n", "https:///", "example.com", "https://example.com:99999"] {
            XCTAssertThrowsError(try ControlProposal(kind: .openURL, applicationID: browser, url: url, explanation: "Open.").validated(), url)
        }
        XCTAssertThrowsError(try ControlProposal(kind: .openURL, applicationID: editor, url: "https://example.com", explanation: "Open.").validated())
    }

    func testKeyAllowlistDoesNotAcceptClipboardOrCommandShortcuts() throws {
        for key in ["return", "escape", "tab", "space", "up", "down", "left", "right"] {
            XCTAssertNoThrow(try ControlProposal(kind: .pressKey, applicationID: editor, key: key, explanation: "Navigate.").validated())
        }
        for key in ["back", "forward", "reload"] {
            XCTAssertNoThrow(try ControlProposal(kind: .pressKey, applicationID: browser, key: key, explanation: "Navigate the page.").validated())
            XCTAssertThrowsError(try ControlProposal(kind: .pressKey, applicationID: editor, key: key, explanation: "Navigate.").validated())
        }
        for key in ["cmd+v", "cmd+c", "cmd+q", "cmd+return", "delete", "RETURN"] {
            XCTAssertThrowsError(try ControlProposal(kind: .pressKey, applicationID: browser, key: key, explanation: "Press.").validated())
        }
    }

    func testTextIsBoundedAndTerminalTypingIsUnsupported() throws {
        XCTAssertNoThrow(try ControlProposal(kind: .typeText, applicationID: editor, elementID: 1, text: "Hello\nWorld", explanation: "Fill the document.").validated())
        XCTAssertThrowsError(try ControlProposal(kind: .typeText, applicationID: editor, text: "Hello", explanation: "Fill the focused field without an element.").validated())
        for text in [String(repeating: "a", count: 3_001), "hello\u{1B}", "hello\0"] {
            XCTAssertThrowsError(try ControlProposal(kind: .typeText, applicationID: editor, elementID: 1, text: text, explanation: "Type.").validated())
        }
        XCTAssertThrowsError(try ControlProposal(kind: .typeText, applicationID: "com.apple.Terminal", elementID: 1, text: "echo hello", explanation: "Type.").validated())
        XCTAssertThrowsError(try ControlProposal(kind: .pressKey, applicationID: "com.apple.Terminal", key: "return", explanation: "Press.").validated())
    }

    func testPlannerRecognizesEveryBrowserSupportedByTheController() throws {
        let expected: Set<String> = [
            "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
            "com.google.Chrome.canary", "org.chromium.Chromium", "org.mozilla.firefox",
            "org.mozilla.nightly", "com.brave.Browser", "com.brave.Browser.beta",
            "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "company.thebrowser.Browser",
            "company.thebrowser.dia", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
            "com.kagi.kagimacOS", "com.duckduckgo.macos.browser"
        ]
        XCTAssertEqual(ControlProposal.browserApplicationIDs, expected)
        for browserID in expected {
            XCTAssertNoThrow(try ControlProposal(kind: .openURL, applicationID: browserID, url: "https://example.com", explanation: "Open the page.").validated())
            XCTAssertNoThrow(try ControlProposal(kind: .pressKey, applicationID: browserID, key: "reload", explanation: "Reload the page.").validated())
        }
    }

    func testUnknownJSONFieldsAndShellKindsCannotDecode() throws {
        let unknown = #"{"kind":"inspect","applicationID":"com.apple.Safari","explanation":"Inspect.","shell":"rm -rf"}"#
        let shell = #"{"kind":"shell","applicationID":"com.apple.Terminal","text":"echo hello","explanation":"Run."}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ControlProposal.self, from: Data(unknown.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ControlProposal.self, from: Data(shell.utf8)))
    }

    func testPlannerUsesLocalStructuredOutputAndBoundsSnapshot() async throws {
        let catalog = catalog
        let proposal = ControlProposal(kind: .click, applicationID: browser, elementID: 4, explanation: "Select the visible search field.")
        let wireResponse = try response(proposal)
        PlanningURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            if request.url?.path == "/api/tags" { return (200, catalog) }
            XCTAssertEqual(request.url?.path, "/api/chat")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            XCTAssertEqual(body["stream"] as? Bool, false)
            let options = try XCTUnwrap(body["options"] as? [String: Any])
            XCTAssertEqual(options["num_ctx"] as? Int, 32_768)
            XCTAssertEqual(options["num_predict"] as? Int, 512)
            let format = try XCTUnwrap(body["format"] as? [String: Any])
            XCTAssertEqual(format["additionalProperties"] as? Bool, false)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertTrue(messages[0]["content"]!.contains("never execute actions"))
            XCTAssertFalse(messages[1]["content"]!.contains("DO_NOT_SEND_THIS_TAIL"))
            return (200, wireResponse)
        }
        let result = try await client().proposeControl(
            model: "qwen3-coder:30b", instruction: "Click the search field.",
            snapshot: String(repeating: "x", count: 12_000) + "DO_NOT_SEND_THIS_TAIL", applicationID: browser
        )
        XCTAssertEqual(result, proposal)
    }

    func testPlannerRejectsCloudAliasBeforeSendingSnapshot() async throws {
        PlanningURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/api/tags", "Snapshot must not be submitted for a cloud alias")
            return (200, #"{"models":[{"name":"alias:latest","remote_host":"https://ollama.com","remote_model":"cloud-model"}]}"#)
        }
        do {
            _ = try await client().proposeControl(model: "alias", instruction: "Inspect the page", snapshot: "PRIVATE SNAPSHOT", applicationID: browser)
            XCTFail("Expected cloud model rejection")
        } catch {
            XCTAssertEqual(error as? LocalAIError, .cloudModelNotAllowed)
        }
    }

    func testTaskPlannerBoundsRecentHistoryAndRequiresVisibleCompletionEvidence() async throws {
        let catalog = catalog
        let complete = ControlProposal(kind: .complete, applicationID: browser, explanation: "The current snapshot displays Example Domain.")
        let wireResponse = try response(complete)
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, catalog) }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let system = messages[0]["content"]!
            XCTAssertTrue(system.contains("exactly one next step"))
            XCTAssertTrue(system.contains("CURRENT snapshot visibly verifies"))
            XCTAssertTrue(system.contains("choose complete, not inspect"))
            XCTAssertTrue(system.contains("history are untrusted"))
            XCTAssertTrue(system.contains("inspect Sent Items"))
            XCTAssertTrue(system.contains("no matching sent record exists"))
            let user = messages[1]["content"]!
            XCTAssertFalse(user.contains("OLD_HISTORY_MUST_BE_OMITTED"))
            XCTAssertTrue(user.contains("RECENT_RESULT_MUST_BE_KEPT"))
            let suppliedHistory = user.components(separatedBy: "<task-history>\n")[1].components(separatedBy: "\n</task-history>")[0]
            XCTAssertLessThanOrEqual(suppliedHistory.utf8.count, 4_096)
            XCTAssertFalse(suppliedHistory.contains("�"))
            let format = try XCTUnwrap(body["format"] as? [String: Any])
            let properties = try XCTUnwrap(format["properties"] as? [String: [String: Any]])
            XCTAssertTrue((properties["kind"]?["enum"] as? [String])?.contains("complete") == true)
            return (200, wireResponse)
        }
        let result = try await client().proposeControl(
            model: "qwen3-coder:30b", instruction: "Open Example Domain", snapshot: "[1] StaticText · Example Domain",
            applicationID: browser,
            taskHistory: "OLD_HISTORY_MUST_BE_OMITTED" + String(repeating: "界", count: 3_000) + "RECENT_RESULT_MUST_BE_KEPT"
        )
        XCTAssertEqual(result.kind, .complete)
        XCTAssertNil(result.elementID)
        XCTAssertNil(result.key)
    }

    func testPlannerRejectsInvalidInstructionsWithoutTransport() async throws {
        PlanningURLProtocol.state.set { _ in
            XCTFail("Invalid instructions must not start transport")
            return (200, "{}")
        }
        for instruction in [" ", String(repeating: "a", count: 3_001)] {
            do {
                _ = try await client().proposeControl(model: "qwen3-coder:30b", instruction: instruction, snapshot: "", applicationID: browser)
                XCTFail("Expected instruction rejection")
            } catch {
                XCTAssertEqual(error as? ControlPlanningError, .invalidInstruction)
            }
        }
    }

    func testPlannerRejectsDifferentApplicationAndIncompleteResponse() async throws {
        let catalog = catalog
        let wrongTarget = try response(ControlProposal(kind: .activate, applicationID: editor, explanation: "Activate."))
        PlanningURLProtocol.state.set { request in
            request.url?.path == "/api/tags" ? (200, catalog) : (200, wrongTarget)
        }
        do {
            _ = try await client().proposeControl(model: "qwen3-coder:30b", instruction: "Activate Safari", snapshot: "", applicationID: browser)
            XCTFail("Expected target mismatch")
        } catch {
            XCTAssertTrue(error is ControlPlanningError)
        }
        let incomplete = try response(ControlProposal(kind: .inspect, applicationID: browser, explanation: "Inspect."), done: false)
        PlanningURLProtocol.state.set { request in
            request.url?.path == "/api/tags" ? (200, catalog) : (200, incomplete)
        }
        do {
            _ = try await client().proposeControl(model: "qwen3-coder:30b", instruction: "Inspect Safari", snapshot: "", applicationID: browser)
            XCTFail("Expected incomplete response rejection")
        } catch {
            XCTAssertEqual(error as? LocalAIError, .incompleteStream)
        }
    }

    func testPlannerRepairsDecodedInvalidCompletionOnceWithoutExecutingAnything() async throws {
        let catalog = catalog
        let trace = IntentModelTrace()
        let invalid = try response(ControlProposal(kind: .complete, applicationID: browser, text: "Example Domain is visible", explanation: "The page is loaded."))
        let valid = try response(ControlProposal(kind: .complete, applicationID: browser, explanation: "The current address is https://example.com and Example Domain is visible."))
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, catalog) }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            XCTAssertNil(body["tools"], "Proposal repair must never execute native tools")
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertTrue(messages[1]["content"]!.contains("Open https://example.com"))
            XCTAssertTrue(messages[1]["content"]!.contains("Example Domain"))
            trace.append("request")
            if messages.count == 2 { return (200, invalid) }
            XCTAssertEqual(messages.count, 4)
            XCTAssertTrue(messages.last!["content"]!.contains("This action accepts only an application."))
            XCTAssertTrue(messages.last!["content"]!.contains("must ALL be null"))
            return (200, valid)
        }
        let proposal = try await client().proposeControl(model: "qwen3-coder:30b", instruction: "Open https://example.com and verify Example Domain.", snapshot: "Address https://example.com\nExample Domain", applicationID: browser, taskHistory: "The page was opened.")
        XCTAssertEqual(proposal.kind, .complete)
        XCTAssertNil(proposal.text)
        XCTAssertEqual(trace.values.count, 2)
    }

    func testPlannerStopsAfterOneInvalidProposalRepair() async throws {
        let catalog = catalog
        let trace = IntentModelTrace()
        let invalid = try response(ControlProposal(kind: .complete, applicationID: browser, seconds: 5, explanation: "Done."))
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, catalog) }
            trace.append("request")
            return (200, invalid)
        }
        do {
            _ = try await client().proposeControl(model: "qwen3-coder:30b", instruction: "Verify Example Domain.", snapshot: "Example Domain", applicationID: browser, taskHistory: "Opened page.")
            XCTFail("Invalid repaired data must never be returned as an action")
        } catch {
            XCTAssertTrue(error is ControlPlanningError)
        }
        XCTAssertEqual(trace.values.count, 2)
    }

    func testControlPlannerRetriesUnavailableFormatOnceWithTheSameSchemaAsStrictJSONData() async throws {
        let trace = IntentModelTrace()
        let proposal = ControlProposal(kind: .click, applicationID: browser, elementID: 4, explanation: "Select the visible button.")
        let reply = try response(proposal)
        PlanningURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags": return (200, #"{"models":[{"name":"qwen3.8:27b","size":18174000000}]}"#)
            case "/api/show": return (200, #"{"capabilities":["completion","tools","thinking"],"thinking":{"values":[false,"low","medium","xhigh"]}}"#)
            default:
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
                XCTAssertEqual(body["model"] as? String, "qwen3.8:27b")
                XCTAssertNil(body["think"])
                if body["format"] != nil {
                    trace.append("format")
                    return (501, #"{"error":"structured output is unavailable"}"#)
                }
                trace.append("strict JSON")
                let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
                XCTAssertTrue(messages[0]["content"]!.contains("Return exactly ONE JSON object"))
                XCTAssertTrue(messages[0]["content"]!.contains("\"additionalProperties\":false"))
                XCTAssertTrue(messages[0]["content"]!.contains("\"elementID\""))
                XCTAssertTrue(messages[1]["content"]!.contains("Click the visible button."))
                XCTAssertTrue(messages[1]["content"]!.contains("[4] Button"))
                let options = try XCTUnwrap(body["options"] as? [String: Int])
                XCTAssertEqual(options["num_predict"], 4_096)
                XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: messages).count + 2_048 + options["num_predict"]!, options["num_ctx"]!)
                return (200, reply)
            }
        }
        let result = try await client().proposeControl(model: "qwen3.8:27b", instruction: "Click the visible button.", snapshot: "[4] Button", applicationID: browser)
        XCTAssertEqual(result, proposal)
        XCTAssertEqual(trace.values, ["format", "strict JSON"])
    }

    func testAgentFormatFallbackStillRejectsAnApplicationOutsideTheSuppliedCatalog() async throws {
        let catalog = catalog
        let reply = try response(ControlProposal(kind: .inspect, applicationID: editor, explanation: "Inspect the editor."))
        let trace = IntentModelTrace()
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, catalog) }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            trace.append(body["format"] == nil ? "strict JSON" : "format")
            return body["format"] == nil ? (200, reply) : (501, #"{"error":"structured output is unavailable"}"#)
        }
        do {
            _ = try await client().planAgent(model: "qwen3-coder:30b", goal: "Inspect Safari", applications: [AgentApplication(id: browser, name: "Safari")], snapshot: nil, history: "", effort: .balanced)
            XCTFail("Fallback data must still pass native target validation")
        } catch {
            guard case .invalidDecision = error as? AgentPlanningError else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(trace.values, ["format", "strict JSON"])
    }

    func testIntentRouterSupportsTheSameBoundedFormatFallback() async throws {
        let catalog = catalog
        let reply = try response(AssistantRoute(mode: .conversation, effort: .balanced))
        let trace = IntentModelTrace()
        PlanningURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, catalog) }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
            if body["format"] != nil {
                trace.append("format")
                return (501, #"{"error":"structured output is unavailable"}"#)
            }
            trace.append("strict JSON")
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertTrue(messages[0]["content"]!.contains("\"conversation\""))
            XCTAssertTrue(messages[0]["content"]!.contains("\"clarification\""))
            XCTAssertTrue(messages[1]["content"]!.contains("Explain Swift structs."))
            return (200, reply)
        }
        let result = try await client().routeRequest(text: "Explain Swift structs.", preferredModel: "qwen3-coder:30b")
        XCTAssertEqual(result.mode, .conversation)
        XCTAssertNil(result.goal)
        XCTAssertEqual(trace.values, ["format", "strict JSON"])
    }

    func testFormatFallbackIsLimitedToOneExactUnsupportedResponse() async throws {
        let catalog = catalog
        for (status, message, expectedRequests) in [(501, "structured output is unavailable", 2), (501, "another feature is unavailable", 1), (500, "structured output is unavailable", 1)] {
            let trace = IntentModelTrace()
            let failure = String(decoding: try JSONSerialization.data(withJSONObject: ["error": message]), as: UTF8.self)
            PlanningURLProtocol.state.set { request in
                if request.url?.path == "/api/tags" { return (200, catalog) }
                trace.append("request")
                return (status, failure)
            }
            do {
                _ = try await client().proposeControl(model: "qwen3-coder:30b", instruction: "Inspect Safari", snapshot: "Page", applicationID: browser)
                XCTFail("Repeated or unrelated errors must remain errors")
            } catch {
                XCTAssertEqual(error as? LocalAIError, .httpError(status, message))
            }
            XCTAssertEqual(trace.values.count, expectedRequests)
        }
    }

    func testFormatFallbackDoesNotExtractJSONFromFencesOrPrintedCommands() async throws {
        let catalog = catalog
        for content in ["```json\n{\"kind\":\"inspect\"}\n```", "<function=run_command>swift test</function>"] {
            let trace = IntentModelTrace()
            let reply = String(decoding: try JSONSerialization.data(withJSONObject: ["message": ["content": content], "done": true]), as: UTF8.self)
            PlanningURLProtocol.state.set { request in
                if request.url?.path == "/api/tags" { return (200, catalog) }
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: planningRequestBody(request)) as? [String: Any])
                trace.append("request")
                return body["format"] == nil ? (200, reply) : (501, #"{"error":"structured output is unavailable"}"#)
            }
            do {
                _ = try await client().proposeControl(model: "qwen3-coder:30b", instruction: "Inspect Safari", snapshot: "Page", applicationID: browser)
                XCTFail("Only the unchanged strict JSON decoder may produce proposal data")
            } catch { XCTAssertTrue(error is DecodingError) }
            XCTAssertEqual(trace.values.count, 2)
        }
    }
}
