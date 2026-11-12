import Foundation
import VyronAutomation

struct VyronComputerPreviewTestRequest {
    let application: DesktopApplication
    let completion: CheckedContinuation<VyronMacControlPreview, any Error>
}
