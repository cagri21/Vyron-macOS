import Foundation

struct VyronPausedModelDownloadsStore {
    let defaults: UserDefaults

    func load() -> Set<String> {
        Set(defaults.stringArray(forKey: VyronUserDefaultsKey.pausedModelDownloads.rawValue) ?? [])
    }

    func save(_ tags: Set<String>) {
        defaults.set(tags.sorted(), forKey: VyronUserDefaultsKey.pausedModelDownloads.rawValue)
    }
}
