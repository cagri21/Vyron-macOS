import Foundation

struct VyronSkillSetupCatalog: Decodable, Sendable {
    let skills: [VyronSkillSetupCatalogEntry]
    let version: Int

    static func read(from directory: URL) throws -> Self {
        let file = directory.appendingPathComponent("catalog.json")
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            let size = values.fileSize, size <= 65_536
        else { throw VyronSkillSetupError.failed }
        let data = try Data(contentsOf: file)
        guard data.count <= 65_536 else { throw VyronSkillSetupError.failed }
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        let aliases = catalog.skills.flatMap(\.aliases)
        guard catalog.version == 1, catalog.skills.count <= 32,
            Set(catalog.skills.map(\.identifier)).count == catalog.skills.count,
            Set(aliases).count == aliases.count,
            catalog.skills.allSatisfy(\.isValid)
        else { throw VyronSkillSetupError.failed }
        return catalog
    }
}
