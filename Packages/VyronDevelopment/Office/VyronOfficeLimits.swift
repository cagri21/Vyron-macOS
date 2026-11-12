import Foundation

public enum VyronOfficeLimits {
    public static let maximumInputBytes = 64 * 1_024 * 1_024
    public static let maximumOutputBytes = 128 * 1_024 * 1_024
    public static let maximumPages = 20
    public static let defaultPreviewPages = 6
    public static let previewWidth = 1_600
    public static let maximumPageDimension = 3_200
    public static let timeout: TimeInterval = 120
}
