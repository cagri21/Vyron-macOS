import Foundation
import VyronModelDomain

/// Availability is deliberately limited to reviewed provider/model combinations.
public enum VyronResponseSpeedPolicy {
    public static func supportsFast(connection: ModelConnectionProfile?, model: String) -> Bool {
        guard let connection, VyronConnectionBalancePolicy.support(for: connection) == .dashboardOnly else {
            return false
        }
        return VyronOpenAIPriceCatalog.pricing(for: model)?.serviceMultiplier("fast") != nil
    }

    public static func effectiveSpeed(connection: ModelConnectionProfile?, model: String) -> VyronResponseSpeed {
        connection?.settings.responseSpeed == .fast && supportsFast(connection: connection, model: model)
            ? .fast : .standard
    }
}
