import Foundation

struct VyronAppStoragePaths {
    let directory: URL

    static var applicationSupport: Self {
        let files = FileManager.default
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? files.homeDirectoryForCurrentUser.appendingPathComponent(
                VyronAppStoragePath.applicationSupportHomePath,
                isDirectory: true
            )
        // Keep the data directory created by earlier versions of Vyron.
        return Self(directory: support.appendingPathComponent(VyronAppStoragePath.appDataDirectoryName, isDirectory: true))
    }

    func url(for path: VyronAppStoragePath) -> URL {
        directory.appendingPathComponent(path.rawValue, isDirectory: path.isDirectory)
    }
}
