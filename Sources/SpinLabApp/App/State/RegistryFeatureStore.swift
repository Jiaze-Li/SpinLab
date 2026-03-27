import Foundation
import Observation

@MainActor
@Observable
final class RegistryFeatureStore {
    var registryFileName: String?
    var registrySourceFilePath: String?
    var registryPrefixEntries: [RegistryPrefixEntry] = []

    func applyPresentation(_ presentation: RegistryPresentationState) {
        registrySourceFilePath = presentation.registrySourceFilePath
        registryFileName = presentation.registryFileName
        registryPrefixEntries = presentation.registryPrefixEntries
    }
}
