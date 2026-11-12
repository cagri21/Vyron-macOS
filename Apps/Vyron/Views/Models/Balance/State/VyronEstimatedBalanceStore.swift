import Foundation

/// Estimates contain amounts and receipt identities only, never API keys or message contents.
struct VyronEstimatedBalanceStore {
    let fileURL: URL
    private static let maximumFileBytes = 4_194_304
    private static let maximumConnections = 100

    func load() throws -> [UUID: VyronEstimatedBalanceLedger] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumFileBytes else {
            throw VyronEstimatedBalanceError.invalidStorage
        }
        let document = try JSONDecoder().decode(VyronEstimatedBalanceDocument.self, from: Data(contentsOf: fileURL))
        guard document.version == 1, document.records.count <= Self.maximumConnections,
            Set(document.records.map(\.connectionID)).count == document.records.count
        else {
            throw VyronEstimatedBalanceError.invalidStorage
        }
        var ledgers: [UUID: VyronEstimatedBalanceLedger] = [:]
        for record in document.records {
            guard Self.isValid(record.ledger) else { throw VyronEstimatedBalanceError.invalidStorage }
            ledgers[record.connectionID] = record.ledger
        }
        return ledgers
    }

    func save(_ ledgers: [UUID: VyronEstimatedBalanceLedger]) throws {
        guard ledgers.count <= Self.maximumConnections, ledgers.values.allSatisfy(Self.isValid) else {
            throw VyronEstimatedBalanceError.invalidStorage
        }
        let records = ledgers.sorted { $0.key.uuidString < $1.key.uuidString }.map {
            VyronEstimatedBalanceRecord(connectionID: $0.key, ledger: $0.value)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(VyronEstimatedBalanceDocument(version: 1, records: records))
        guard data.count <= Self.maximumFileBytes else { throw VyronEstimatedBalanceError.invalidStorage }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func isValid(_ ledger: VyronEstimatedBalanceLedger) -> Bool {
        let amount = ledger.state.remainingUSD
        return !amount.isNaN && amount >= -1_000_000_000_000 && amount <= 1_000_000_000
            && ledger.baseline.timeIntervalSince1970.isFinite
            && ledger.state.updatedAt.timeIntervalSince1970.isFinite
            && ledger.state.updatedAt >= ledger.baseline
            && ledger.receipts.count <= VyronEstimatedBalanceLedger.maximumReceipts
            && ledger.receipts.allSatisfy { !$0.isEmpty && $0.utf8.count <= 600 }
            && Set(ledger.receipts).count == ledger.receipts.count
    }
}
