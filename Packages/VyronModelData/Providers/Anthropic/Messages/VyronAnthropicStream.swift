import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronAnthropicStream {
    private let model: String?
    private let prefixDigest: Data?
    private var line = Data()
    private var event = Data()
    private var started = false
    private var activeBlock: VyronAnthropicStreamBlock?
    private var content: [DevelopmentJSONValue] = []
    private var contentBytes = 0
    private var stopReason: String?
    private var completedMessage: DevelopmentMessage?
    private(set) var output = ""

    var completed: Bool { completedMessage != nil }

    init(model: String? = nil, prefixDigest: Data? = nil) {
        self.model = model
        self.prefixDigest = prefixDigest
    }

    mutating func append(_ byte: UInt8) throws -> String {
        guard !completed else { return "" }
        if byte == 10 {
            let delta = try consumeLine()
            line.removeAll(keepingCapacity: true)
            return delta
        }
        guard line.count < VyronAnthropicWire.maximumResponseBytes else { throw oversized }
        line.append(byte)
        return ""
    }

    mutating func finish() throws -> String {
        var delta = ""
        if !line.isEmpty {
            delta += try consumeLine()
            line.removeAll()
        }
        if !event.isEmpty { delta += try consumeEvent() }
        guard completed else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.claudeStreamIncomplete)
        }
        return delta
    }

    func developmentMessage() throws -> DevelopmentMessage {
        guard let completedMessage else { throw invalidEvent }
        return completedMessage
    }

    private var invalidEvent: ModelProviderError {
        .invalidResponse(VyronModelDataText.claudeInvalidStreamEvent)
    }

    private var oversized: ModelProviderError {
        .invalidResponse(VyronModelDataText.claudeStreamTooLarge)
    }

    private mutating func consumeLine() throws -> String {
        guard let raw = String(data: line, encoding: .utf8) else { throw invalidEvent }
        let value = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if value.isEmpty { return try consumeEvent() }
        guard value.hasPrefix("data:") else { return "" }
        let payload = value.dropFirst(5).drop(while: { $0 == " " })
        let separatorBytes = event.isEmpty ? 0 : 1
        guard event.count + separatorBytes + payload.utf8.count <= VyronAnthropicWire.maximumResponseBytes else {
            throw oversized
        }
        if !event.isEmpty { event.append(10) }
        event.append(contentsOf: payload.utf8)
        return ""
    }

    private mutating func consumeEvent() throws -> String {
        guard !event.isEmpty else { return "" }
        let fields = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: event)
        event.removeAll(keepingCapacity: true)
        guard case .string(let type) = fields["type"] else { throw invalidEvent }
        switch type {
        case "message_start":
            guard !started, case .object(let message) = fields["message"],
                message["role"] == .string("assistant")
            else {
                throw invalidEvent
            }
            started = true
        case "content_block_start":
            guard started, stopReason == nil, activeBlock == nil, fields["index"] == .number(Double(content.count)),
                case .object(let block) = fields["content_block"], case .string = block["type"]
            else {
                throw invalidEvent
            }
            let active = VyronAnthropicStreamBlock(fields: block)
            activeBlock = active
            return try appendOutput(active.visibleText)
        case "content_block_delta":
            guard fields["index"] == .number(Double(content.count)), case .object(let delta) = fields["delta"],
                var block = activeBlock
            else { throw invalidEvent }
            let text = try block.append(delta)
            activeBlock = block
            return try appendOutput(text)
        case "content_block_stop":
            guard fields["index"] == .number(Double(content.count)), let activeBlock else { throw invalidEvent }
            let block = try activeBlock.completedContent()
            contentBytes += try JSONEncoder().encode(block).count
            guard contentBytes <= VyronAnthropicWire.maximumResponseBytes else { throw oversized }
            content.append(block)
            self.activeBlock = nil
        case "message_delta":
            guard started, activeBlock == nil, case .object(let delta) = fields["delta"] else { throw invalidEvent }
            if case .string(let reason) = delta["stop_reason"] { stopReason = reason }
        case "message_stop":
            guard started, activeBlock == nil, let stopReason else { throw invalidEvent }
            completedMessage = try VyronAnthropicWire.developmentMessage(
                content: content,
                stopReason: stopReason,
                model: model,
                prefixDigest: prefixDigest
            )
        case "error":
            throw ModelProviderError.invalidResponse(VyronModelDataText.claudeStreamError)
        default:
            break
        }
        return ""
    }

    private mutating func appendOutput(_ delta: String) throws -> String {
        guard output.utf8.count + delta.utf8.count <= VyronAnthropicWire.maximumResponseBytes else { throw oversized }
        output += delta
        return delta
    }
}
