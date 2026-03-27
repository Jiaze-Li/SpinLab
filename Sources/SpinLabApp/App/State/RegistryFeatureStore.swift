import Foundation

struct RegistryFeatureStore {
    var registryFileName: String?
    var registrySourceFilePath: String?
    var registryPrefixEntries: [RegistryPrefixEntry] = []

    mutating func applyPresentation(_ presentation: RegistryPresentationState) {
        registrySourceFilePath = presentation.registrySourceFilePath
        registryFileName = presentation.registryFileName
        registryPrefixEntries = presentation.registryPrefixEntries
    }
}
