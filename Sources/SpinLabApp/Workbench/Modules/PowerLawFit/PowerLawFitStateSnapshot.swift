import Foundation

struct PowerLawFitStateSnapshot: Codable, Hashable, Sendable {
    var configuration: PowerLawFitConfiguration
    var input: PowerLawFitInput?
    var result: PowerLawFitResult?

    init(
        configuration: PowerLawFitConfiguration = PowerLawFitConfiguration(),
        input: PowerLawFitInput? = nil,
        result: PowerLawFitResult? = nil
    ) {
        self.configuration = configuration
        self.input = input
        self.result = result
    }
}

