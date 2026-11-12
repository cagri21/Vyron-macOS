import SwiftUI

enum VyronMCPStyle {
    static let editorTitle = Font.system(size: 20, weight: .semibold)
    static let reviewTitle = Font.system(size: 21, weight: .semibold)
    static let reviewIdentity = Font.system(size: 13, weight: .medium)
    static let reviewBody = Font.system(size: 12)
    static let field = Font.system(size: 11)
    static let helper = Font.system(size: 10)
    static let code = Font.system(size: 11, design: .monospaced)
    static let editorSize = CGSize(width: 650, height: 670)
    static let reviewSize = CGSize(width: 650, height: 480)
    static let editorContainerSpacing: CGFloat = 0
    static let editorPadding: CGFloat = 23
    static let editorFooterPadding: CGFloat = 20
    static let editorSectionSpacing: CGFloat = 16
    static let credentialsSpacing: CGFloat = 12
    static let jsonFieldSpacing: CGFloat = 6
    static let jsonFieldPadding: CGFloat = 6
    static let jsonFieldRadius: CGFloat = 6
    static let configurationEditorHeight: CGFloat = 180
    static let credentialEditorHeight: CGFloat = 65
    static let commandHintLineSpacing: CGFloat = 3
    static let permissionsHintLineSpacing: CGFloat = 4
    static let reviewSpacing: CGFloat = 18
    static let reviewPadding: CGFloat = 25
    static let reviewArgumentsPadding: CGFloat = 12
    static let reviewArgumentsRadius: CGFloat = 8
}
