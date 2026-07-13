import Foundation
import Observation

@MainActor
@Observable
final class PowerLawFitRuntime {
    var configuration = PowerLawFitConfiguration()
    var input = PowerLawFitInput(points: [])
    private(set) var result: PowerLawFitResult?

    func recompute() {
        result = PowerLawFitUseCase().execute(input: input, configuration: configuration)
    }

    func snapshot() -> PowerLawFitStateSnapshot {
        PowerLawFitStateSnapshot(configuration: configuration, input: input, result: result)
    }

    func restore(from snapshot: PowerLawFitStateSnapshot) {
        configuration = snapshot.configuration
        input = snapshot.input ?? PowerLawFitInput(points: [])
        result = snapshot.result
    }
}

