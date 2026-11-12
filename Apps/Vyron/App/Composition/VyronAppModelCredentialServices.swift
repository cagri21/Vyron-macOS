import VyronModelData

struct VyronAppModelCredentialServices {
    let store: ModelCredentialStore
    let reader: VyronModelCredentialReader
    let localAuthentication: VyronLocalAuthenticationModel
}
