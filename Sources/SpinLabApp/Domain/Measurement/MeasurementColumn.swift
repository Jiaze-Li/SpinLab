import Foundation

/// The minimum per-array primitive a format loader may produce, per the 2026-08-08
/// MeasurementData/Signal architecture audit §2/§3. Named "Column" rather than "Signal" or
/// "Channel" deliberately: "Channel" already means something else in this codebase (IV's
/// ch1/ch2 — one lock-in input producing four correlated columns), and "Signal" implies physical/
/// electrical meaningfulness a loader cannot always know (e.g. RSM's raw detector counts). A
/// `MeasurementColumn` is simply "the Nth array of values found in this file," whether or not
/// the file itself gave it a name.
///
/// Ownership, per the audit:
///   - `stableSourceKey`, `sourceColumnIndex`, `values`, `sourceUnit` — loader facts, required.
///   - `rawLabel` — loader fact, optional (nil when the file has no header row to preserve, e.g.
///     LVM's positional-only grammar).
///   - `instrumentChannelLabel` — loader fact, optional, and only ever set when the label is
///     fixed by the specific loader's own file grammar (not deduced physics).
///   - `physicalQuantityID` — mixed. A loader may assign this only under the audit's §4 rule
///     (the raw file declares identity, unambiguously, without external context). Everything
///     else is workflow interpretation, assigned after the column leaves the loader — which is
///     why this field, alone, is declared `var`.
///
/// Deliberately excluded per the audit: x/y role, harmonic, component, Rxx/Rxy, fit results,
/// normalized/canonical values. None of those are things a loader can know from the raw file
/// alone; they belong to workflow interpretation, never to this type.
struct MeasurementColumn: Sendable {
    let stableSourceKey: String
    let rawLabel: String?
    let sourceColumnIndex: Int
    let values: [Double]
    var sourceUnit: PhysicalQuantityUnitTag
    var physicalQuantityID: PhysicalQuantityID?
    let instrumentChannelLabel: String?

    init(stableSourceKey: String,
         rawLabel: String?,
         sourceColumnIndex: Int,
         values: [Double],
         sourceUnit: PhysicalQuantityUnitTag,
         physicalQuantityID: PhysicalQuantityID? = nil,
         instrumentChannelLabel: String? = nil) {
        self.stableSourceKey = stableSourceKey
        self.rawLabel = rawLabel
        self.sourceColumnIndex = sourceColumnIndex
        self.values = values
        self.sourceUnit = sourceUnit
        self.physicalQuantityID = physicalQuantityID
        self.instrumentChannelLabel = instrumentChannelLabel
    }
}
