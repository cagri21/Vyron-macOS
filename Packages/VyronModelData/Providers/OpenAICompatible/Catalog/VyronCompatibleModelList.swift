import VyronModelDomain

struct VyronCompatibleModelList: Decodable {
    let data: [VyronCompatibleModelDescriptor]
}
