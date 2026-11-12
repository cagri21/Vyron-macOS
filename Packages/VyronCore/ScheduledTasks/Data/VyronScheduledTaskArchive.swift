import Foundation

struct VyronScheduledTaskArchive: Codable {
    let version: Int
    let tasks: [VyronScheduledTask]

    init(version: Int = 1, tasks: [VyronScheduledTask]) {
        self.version = version
        self.tasks = tasks
    }
}
