import Foundation
import XCTest
@testable import VyronAutomation

final class VyronChromeBridgeTests: XCTestCase, @unchecked Sendable {
    func testNativeFramingHandlesSplitHeadersAndConcatenatedFrames() throws {
        let first = Data("{\"version\":1,\"type\":\"hello\"}".utf8)
        let second = Data("{\"version\":1,\"type\":\"heartbeat\"}".utf8)
        let frames = try VyronChromeNativeFraming.frame(first) + VyronChromeNativeFraming.frame(second)
        var parser = VyronChromeNativeFraming()
        XCTAssertEqual(try parser.append(Data(frames.prefix(2))), [])
        XCTAssertEqual(try parser.append(Data(frames.dropFirst(2))), [first, second])
        XCTAssertNoThrow(try parser.finish())
    }

    func testNativeFramingRejectsOversizeAndTruncatedFrames() throws {
        var parser = VyronChromeNativeFraming()
        XCTAssertThrowsError(try parser.append(Data([255, 255, 255, 127])))
        parser = VyronChromeNativeFraming()
        XCTAssertEqual(try parser.append(Data([10, 0, 0, 0, 123])), [])
        XCTAssertThrowsError(try parser.finish())
        XCTAssertThrowsError(try VyronChromeNativeFraming.frame(Data()))
    }

    func testSessionsRequireFreshHeartbeatAndMatchingIdentity() async throws {
        let rootURL = try makeRoot()
        defer { removeRoot(rootURL) }
        let root = try VyronChromeBridgeDirectory.open(rootURL, create: false)
        let liveID = UUID()
        let staleID = UUID()
        // A host may be between creating its private session folder and publishing its first heartbeat.
        _ = try root.child(UUID().uuidString, create: true)
        let live = try VyronChromeBridgeMailbox(root: root, id: liveID, create: true)
        let stale = try VyronChromeBridgeMailbox(root: root, id: staleID, create: true)
        try live.update(VyronChromeBridgeSession(id: liveID, extensionID: extensionID, updatedAt: Date()))
        try stale.update(VyronChromeBridgeSession(
            id: staleID, extensionID: extensionID, updatedAt: Date().addingTimeInterval(-30)
        ))
        let client = VyronChromeBridgeClient(root: rootURL)
        let sessions = try await client.sessions()
        XCTAssertEqual(sessions.map(\.id), [liveID])
        try live.update(VyronChromeBridgeSession(id: UUID(), extensionID: extensionID, updatedAt: Date()))
        let mismatched = try await client.sessions()
        XCTAssertTrue(mismatched.isEmpty)
    }

    func testExpiredRequestIsRejectedAndNeverDispatched() throws {
        let rootURL = try makeRoot()
        defer { removeRoot(rootURL) }
        let root = try VyronChromeBridgeDirectory.open(rootURL, create: false)
        let id = UUID()
        let host = try VyronChromeNativeHostConnection(root: root, id: id, extensionID: extensionID)
        try host.accept(hello)
        let mailbox = try VyronChromeBridgeMailbox(root: root, id: id, create: false)
        let requestID = UUID()
        let data = Data("""
        {"version":1,"id":"\(requestID)","method":"tabs","arguments":{},"expiresAt":1}
        """.utf8)
        let request = try VyronChromeBridgePolicy.decode(VyronChromeBridgeRequest.self, from: data)
        XCTAssertThrowsError(try request.validate())
        try mailbox.requests.write(requestID.uuidString + ".json", data: data)
        XCTAssertTrue(try host.outgoing().isEmpty)
        XCTAssertTrue(try mailbox.requests.names().isEmpty)
    }

    func testCancellationBeforeDispatchRemovesRequestAndAfterDispatchSendsCancel() throws {
        let rootURL = try makeRoot()
        defer { removeRoot(rootURL) }
        let root = try VyronChromeBridgeDirectory.open(rootURL, create: false)
        let id = UUID()
        let host = try VyronChromeNativeHostConnection(root: root, id: id, extensionID: extensionID)
        try host.accept(hello)
        let mailbox = try VyronChromeBridgeMailbox(root: root, id: id, create: false)
        let first = VyronChromeBridgeRequest(method: "tabs")
        try mailbox.requests.write(first.id.uuidString + ".json", data: VyronChromeBridgePolicy.encode(first))
        try mailbox.cancel(first.id)
        XCTAssertTrue(try host.outgoing().isEmpty)
        let second = VyronChromeBridgeRequest(method: "tabs")
        try mailbox.requests.write(second.id.uuidString + ".json", data: VyronChromeBridgePolicy.encode(second))
        XCTAssertEqual(try host.outgoing().count, 1)
        XCTAssertTrue(try host.outgoing().isEmpty, "Dispatched requests must not replay")
        try mailbox.cancel(second.id)
        let cancelled = try host.outgoing()
        XCTAssertEqual(cancelled.count, 1)
        let signal = try VyronChromeBridgePolicy.decode(VyronChromeBridgeSignal.self, from: XCTUnwrap(cancelled.first))
        XCTAssertEqual(signal.type, "cancel")
        XCTAssertEqual(signal.id, second.id)
    }

    func testClientCancellationCleansRequestAndPreservesCancellation() async throws {
        let rootURL = try makeRoot()
        defer { removeRoot(rootURL) }
        let root = try VyronChromeBridgeDirectory.open(rootURL, create: false)
        let id = UUID()
        let mailbox = try VyronChromeBridgeMailbox(root: root, id: id, create: true)
        try mailbox.update(VyronChromeBridgeSession(id: id, extensionID: extensionID, updatedAt: Date()))
        let request = VyronChromeBridgeRequest(method: "tabs")
        let client = VyronChromeBridgeClient(root: rootURL)
        let task = Task { try await client.send(request, to: id) }
        let deadline = Date().addingTimeInterval(2)
        while try mailbox.requests.names().isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(try mailbox.requests.names().isEmpty)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request unexpectedly succeeded") }
        catch is CancellationError { }
        catch { XCTFail("Cancellation must stay distinct: \(error)") }
        XCTAssertTrue(try mailbox.requests.names().isEmpty)
        XCTAssertTrue(try mailbox.responses.names().isEmpty)
        XCTAssertEqual(try mailbox.cancellations.names(), [request.id.uuidString + ".json"])
        do { _ = try await client.send(request, to: id); XCTFail("A cancelled request was replayed") }
        catch let error as VyronChromeBridgeError { XCTAssertEqual(error, .unavailable) }
    }

    func testResponseIdentityCannotCreateUnsolicitedMailboxEntry() throws {
        let rootURL = try makeRoot()
        defer { removeRoot(rootURL) }
        let root = try VyronChromeBridgeDirectory.open(rootURL, create: false)
        let id = UUID()
        let host = try VyronChromeNativeHostConnection(root: root, id: id, extensionID: extensionID)
        try host.accept(hello)
        let mailbox = try VyronChromeBridgeMailbox(root: root, id: id, create: false)
        let unsolicited = Data("""
        {"version":1,"id":"\(UUID())","ok":true,"result":{"tabs":[]}}
        """.utf8)
        try host.accept(unsolicited)
        XCTAssertTrue(try mailbox.responses.names().isEmpty)
    }

    func testCompletedRequestCannotBeReinsertedAndReplayed() throws {
        let rootURL = try makeRoot()
        defer { removeRoot(rootURL) }
        let root = try VyronChromeBridgeDirectory.open(rootURL, create: false)
        let id = UUID()
        let host = try VyronChromeNativeHostConnection(root: root, id: id, extensionID: extensionID)
        try host.accept(hello)
        let mailbox = try VyronChromeBridgeMailbox(root: root, id: id, create: false)
        let request = VyronChromeBridgeRequest(method: "tabs")
        let name = request.id.uuidString + ".json"
        let data = try VyronChromeBridgePolicy.encode(request)
        try mailbox.requests.write(name, data: data)
        XCTAssertEqual(try host.outgoing().count, 1)
        let response = Data("""
        {"version":1,"id":"\(request.id)","ok":true,"result":{"tabs":[]}}
        """.utf8)
        try host.accept(response)
        XCTAssertNotNil(try mailbox.responses.read(name))
        try mailbox.requests.write(name, data: data)
        XCTAssertThrowsError(try host.outgoing(), "Even a completed request identity must never be replayed")
    }

    func testPrivateStorageRejectsSymlinksAndTraversal() throws {
        let rootURL = try makeRoot()
        defer { removeRoot(rootURL) }
        let root = try VyronChromeBridgeDirectory.open(rootURL, create: false)
        let target = try root.child("target", create: true)
        try target.write("value.json", data: Data("{}".utf8))
        let alias = rootURL.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: rootURL.appendingPathComponent("target"))
        XCTAssertThrowsError(try root.child("alias", create: false))
        XCTAssertThrowsError(try VyronChromeBridgeDirectory.open(alias, create: false))
        XCTAssertThrowsError(try root.read("../value.json"))
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("linked.json"),
            withDestinationURL: rootURL.appendingPathComponent("target/value.json")
        )
        XCTAssertThrowsError(try root.read("linked.json"))
        XCTAssertThrowsError(try root.write("linked.json", data: Data("{}".utf8), replacing: true))
    }

    func testNativeOriginRequiresExactRegisteredExtensionAndExecutable() throws {
        let rootURL = try makeRoot()
        defer { removeRoot(rootURL) }
        let location = rootURL.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        let manifests = try VyronChromeBridgeDirectory.open(location, create: true)
        let hostDirectory = rootURL.appendingPathComponent("Vyron.app/Contents/MacOS")
        _ = try VyronChromeBridgeDirectory.open(hostDirectory, create: true)
        let executable = hostDirectory.appendingPathComponent("VyronChromeHost").path
        try Data("synthetic executable".utf8).write(to: URL(fileURLWithPath: executable))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable)
        let origin = "chrome-extension://\(extensionID)/"
        let manifest = Data("""
        {"name":"ai.vyron.chrome","path":"\(executable)","type":"stdio","allowed_origins":["\(origin)"]}
        """.utf8)
        try manifests.write("ai.vyron.chrome.json", data: manifest)
        XCTAssertEqual(
            try VyronChromeNativeOrigin.validate(origin: origin, executable: executable, home: rootURL), extensionID
        )
        XCTAssertThrowsError(try VyronChromeNativeOrigin.validate(
            origin: "chrome-extension://\(String(repeating: "b", count: 32))/", executable: executable, home: rootURL
        ))
        XCTAssertThrowsError(try VyronChromeNativeOrigin.validate(
            origin: origin, executable: executable + "-other", home: rootURL
        ))
        XCTAssertThrowsError(try VyronChromeNativeOrigin.validate(
            origin: origin + "?arbitrary=1", executable: executable, home: rootURL
        ))
    }

    private let extensionID = String(repeating: "a", count: 32)
    private let hello = Data("{\"version\":1,\"type\":\"hello\"}".utf8)

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/chrome-bridge-tests/" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private func removeRoot(_ root: URL) {
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Test storage cleanup failed: \(error)") }
    }
}
