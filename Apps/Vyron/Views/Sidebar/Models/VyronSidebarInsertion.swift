import VyronCore

enum VyronSidebarInsertion: Equatable {
    case before(VyronSidebarRow)
    case after(VyronSidebarRow)
    case end

    func index(in rows: [VyronSidebarRow]) -> Int? {
        switch self {
        case .before(let row): rows.firstIndex(of: row)
        case .after(let row): rows.firstIndex(of: row).map { $0 + 1 }
        case .end: rows.endIndex
        }
    }
}
