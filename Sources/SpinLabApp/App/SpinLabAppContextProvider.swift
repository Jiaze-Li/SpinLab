import Foundation

final class ArchivedRecordDomainContextAdapter: SpinLabDomainContext {
    private let normalizedValueProvider: @MainActor (String?) -> String?
    private let metadataValueProvider: @MainActor (SampleRegistryLookupResult?, [String]) -> String?
    private let canonicalProjectProvider: @MainActor (String) -> SpinLabDomain.Project?
    private let canonicalBatchProvider: @MainActor (String) -> SpinLabDomain.Batch?
    private let canonicalSampleProvider: @MainActor (String) -> SpinLabDomain.Sample?
    private let canonicalDeviceProvider: @MainActor (String, UUID) -> SpinLabDomain.Device?
    private let canonicalMeasurementProvider: @MainActor (String) -> SpinLabDomain.Measurement?
    private let canonicalDatasetProvider: @MainActor (String) -> SpinLabDomain.Dataset?
    private let measurementNotesProvider: @MainActor (SpinLabDomain.PendingImport, PendingImportConfirmationDraft, SampleRegistryLookupResult?) -> String
    private let defaultResultSummaryProvider: @MainActor (SpinLabDomain.Measurement) -> String

    init(
        normalizedValueProvider: @escaping @MainActor (String?) -> String?,
        metadataValueProvider: @escaping @MainActor (SampleRegistryLookupResult?, [String]) -> String?,
        canonicalProjectProvider: @escaping @MainActor (String) -> SpinLabDomain.Project?,
        canonicalBatchProvider: @escaping @MainActor (String) -> SpinLabDomain.Batch?,
        canonicalSampleProvider: @escaping @MainActor (String) -> SpinLabDomain.Sample?,
        canonicalDeviceProvider: @escaping @MainActor (String, UUID) -> SpinLabDomain.Device?,
        canonicalMeasurementProvider: @escaping @MainActor (String) -> SpinLabDomain.Measurement?,
        canonicalDatasetProvider: @escaping @MainActor (String) -> SpinLabDomain.Dataset?,
        measurementNotesProvider: @escaping @MainActor (SpinLabDomain.PendingImport, PendingImportConfirmationDraft, SampleRegistryLookupResult?) -> String,
        defaultResultSummaryProvider: @escaping @MainActor (SpinLabDomain.Measurement) -> String
    ) {
        self.normalizedValueProvider = normalizedValueProvider
        self.metadataValueProvider = metadataValueProvider
        self.canonicalProjectProvider = canonicalProjectProvider
        self.canonicalBatchProvider = canonicalBatchProvider
        self.canonicalSampleProvider = canonicalSampleProvider
        self.canonicalDeviceProvider = canonicalDeviceProvider
        self.canonicalMeasurementProvider = canonicalMeasurementProvider
        self.canonicalDatasetProvider = canonicalDatasetProvider
        self.measurementNotesProvider = measurementNotesProvider
        self.defaultResultSummaryProvider = defaultResultSummaryProvider
    }

    func normalizedValue(_ value: String?) -> String? {
        MainActor.assumeIsolated {
            normalizedValueProvider(value)
        }
    }

    func metadataValue(in lookup: SampleRegistryLookupResult?, keys: [String]) -> String? {
        MainActor.assumeIsolated {
            metadataValueProvider(lookup, keys)
        }
    }

    func canonicalProject(named name: String) -> SpinLabDomain.Project? {
        MainActor.assumeIsolated {
            canonicalProjectProvider(name)
        }
    }

    func createProject(named name: String) -> String? {
        nil
    }

    func canonicalBatch(named name: String) -> SpinLabDomain.Batch? {
        MainActor.assumeIsolated {
            canonicalBatchProvider(name)
        }
    }

    func canonicalSample(named name: String) -> SpinLabDomain.Sample? {
        MainActor.assumeIsolated {
            canonicalSampleProvider(name)
        }
    }

    func canonicalDevice(named name: String, sampleID: UUID) -> SpinLabDomain.Device? {
        MainActor.assumeIsolated {
            canonicalDeviceProvider(name, sampleID)
        }
    }

    func canonicalMeasurement(forSourcePath path: String) -> SpinLabDomain.Measurement? {
        MainActor.assumeIsolated {
            canonicalMeasurementProvider(path)
        }
    }

    func canonicalDataset(forSourcePath path: String) -> SpinLabDomain.Dataset? {
        MainActor.assumeIsolated {
            canonicalDatasetProvider(path)
        }
    }

    func measurementNotes(
        for pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        registryLookup: SampleRegistryLookupResult?
    ) -> String {
        MainActor.assumeIsolated {
            measurementNotesProvider(pending, draft, registryLookup)
        }
    }

    func defaultResultSummary(for measurement: SpinLabDomain.Measurement) -> String {
        MainActor.assumeIsolated {
            defaultResultSummaryProvider(measurement)
        }
    }
}
