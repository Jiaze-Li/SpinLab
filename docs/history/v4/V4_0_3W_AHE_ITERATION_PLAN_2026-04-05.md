# SpinLab V4.0 — 3ω AHE Workflow Iteration Plan (2026-04-05)

Status: planning
Type: new workflow (does not modify existing AHE/.dat workflow)

---

## Context

Adding a **3ω AHE (三阶谐波反常霍尔效应)** workflow to SpinLab 4.0 as a completely independent extension. This workflow ingests Zurich Instruments LVM files, performs field-sweep analysis at multiple temperatures, and produces six output plots — the most important being the Berry curvature quadrupole scaling analysis (paper Fig 5b).

Reference: *Physical Review X 2024 — Experimental evidence for a Berry curvature quadrupole in an antiferromagnet*

---

## Data Source

### Directory structure
```
{SampleFolder}/
├── 0deg/    ← 17 × "3w_" files (T: 5K→160K) + 2 × "RT_" files
├── 30deg/
└── 60deg/
```
Each angle folder is processed independently. No cross-angle comparison in a single view.

### LVM file format (Zurich Instruments, tab-separated)
```
[double header line — duplicated column names]
[blank line]
Tableau:
[tab-separated data rows — NO column header row in data section]
```

### Column layout (0-indexed, positional — no header row in data)

| Col | Name | Notes |
|-----|------|-------|
| 0 | H (Oe) | Field sweep ±20kOe, ~161 pts per file |
| 1 | V¹ω\_X (V) | 1st harmonic, in-phase ← used for R¹ω |
| 2 | V¹ω\_Y | |
| 3 | V¹ω\_R | magnitude |
| 4 | V¹ω\_θ | phase (°) |
| 5 | V³ω\_X (V) | **3rd harmonic, in-phase ← key signal** |
| 6 | V³ω\_Y | |
| 7 | V³ω\_R | |
| 8 | V³ω\_θ | |
| 9 | R\_H (Ω) | Pre-calc by LabVIEW: V¹ω\_X / I\_rms — verified to ~1e-11 precision |
| 10 | f\_ref (Hz) | ~317.3 Hz = 3ω reference (drive freq ≈ 105.8 Hz) |

**RT files:** Col 0 = Temperature (K), Col 9 = Rxx (Ω). Detected by `_RT_` in filename.

### I_rms extraction — from data, not filename
```
I_rms = mean( Col[1][i] / Col[9][i] )   for i in first N rows
```
Verified: consistent across all rows to ~1e-11 precision. Matches `I_amp / √2` exactly.
Filename `Iac_X A` is parsed as backup cross-check only — not the primary source.

### Filename metadata (regex)
- `T_([0-9.]+) K` → temperatureK (field-sweep files only)
- `_3w_` / `_RT_` → file kind
- Folder name (0deg, 30deg, 60deg) → angle label
- `Iac_([0-9.]+) A` → I\_amp (backup only)

---

## Calculation Pipeline

> **Design requirement: every calculation step must have the physical formula written as
> a `// Formula:` comment in the Swift source, so future readers can verify each line.**

### Step 1 — I_rms (derived from data)
```
// Formula: I_rms = Col[1] / Col[9]  =  V¹ω_X / R_H
// Verified: all rows agree to ~1e-11; equals I_amp/√2 from filename
I_rms = mean( Col[1][i] / Col[9][i] )   for first N rows
```

### Step 2 — Raw voltage → Resistance
```
// Formula: R¹ω(H) = V¹ω_X(H) / I_rms   [Col 1 / I_rms]
// Formula: R³ω(H) = V³ω_X(H) / I_rms   [Col 5 / I_rms]
```

### Step 3 — Centering (remove DC offset)
```
// Formula: R_centered(H) = R(H) - (max(R) + min(R)) / 2
// Purpose: center the hysteresis loop around zero for display
// Applied to both R¹ω and R³ω
```

### Step 4 — V^(3ω)_AHE extraction ⚠️ TBD after first plot

Two candidate methods — choose after visualising all temperature curves:

```
// [Method A — Intercept-distance / RAHE-style]
// Formula: b⁺ = H=0 intercept of linear fit at H > 0.7×Hmax
// Formula: b⁻ = H=0 intercept of linear fit at H < -0.7×Hmax
// Formula: RAHE³ω = (b⁺ - b⁻) / 2
// Formula: V^(3ω)_AHE = RAHE³ω × I_rms
// Formula: E^(3ω)_AHE = V^(3ω)_AHE / L_xy
// Prerequisite: V³ω_AHE must flip sign with magnetization reversal (antisymmetric)

// [Method B — H=0 direct read with high-T background reference]
// Formula: V^(3ω)_AHE(T) = V³ω_X(H≈0, T) − V³ω_X(H≈0, T_ref)
//   T_ref = highest measured T (above Tc, where AHE → 0)
// Formula: E^(3ω)_AHE = V^(3ω)_AHE / L_xy
// Prerequisite: field-dependent background is odd in H (→ 0 at H=0)
//               constant offset cancelled by T_ref subtraction
```

**Empirical observation at 5K:** V³ω shows a flat plateau at |H| < 5000 Oe; no detectable
jump at the 1ω switching field (~11000 Oe). The 3ω signal does NOT clearly flip with
magnetization — consistent with Berry curvature quadrupole in antiferromagnet (Q_xxz
is invariant under T×τ AF symmetry). At 160K (above Tc): purely monotonic, no plateau.

**Decision rule after plotting:**
- If V³ω shows detectable antisymmetric switching → Method A
- If V³ω is symmetric or switch is below noise → Method B

### Step 5 — RAHE and Hc fitting (for Tab 3 & 4)
```
// RAHE extraction from R(H) curve (applied to R¹ω and R³ω separately):
// Formula: fit R = k×H + b  in  H > 0.7×Hmax  → b⁺
// Formula: fit R = k×H + b  in  H < −0.7×Hmax → b⁻
// Formula: RAHE = (b⁺ − b⁻) / 2

// Hc extraction:
// Formula: R_mid = (max(R) + min(R)) / 2
// Find H where R(H) = R_mid in positive field  → Hc⁺  (linear interpolation)
// Find H where R(H) = R_mid in negative field  → Hc⁻
// Formula: Hc = (|Hc⁺| + |Hc⁻|) / 2
```

### Step 6 — RT curve (for Tab 5 and Scaling input)
```
// Formula: Rxx(T) = Col[9](T)   [LabVIEW pre-calc = V¹ω_X / I_rms = longitudinal R]
// Alternative: Rxx(T) = Col[1](T) / I_rms  (equivalent, verified)
// I_rms: same derivation as Step 1, applied to RT file
```

### Step 7 — Fig 5b Scaling Analysis (main result)

User inputs geometry parameters: **L_xx (μm), L_xy (μm), d (nm)**

```
// Unit conversions:
// d_m    = d_nm × 1e-9        (nm → m)
// L_xx_m = L_xx_um × 1e-6    (μm → m)
// L_xy_m = L_xy_um × 1e-6    (μm → m)

// Resistivity (from paper transport equations):
// Formula: ρ_xx = Rxx(T) × (d_m × L_xy_m / L_xx_m)

// Conductivity:
// Formula: σ_xx = 1 / ρ_xx

// Electric fields:
// Formula: E_xx       = I_amp × Rxx(T) / L_xx_m         [longitudinal field, V/m]
// Formula: E^(3ω)_AHE = V^(3ω)_AHE(T) / L_xy_m         [3ω Hall field, V/m]
//   NOTE: denominator uses E_xx³ = E_xx to the POWER of 3 (not "3ω")

// Scaling axes for Fig 5b:
// X-axis: σ²_xx(T)
// Y-axis: E^(3ω)_AHE(T) / ( E_xx(T)³ × σ_xx(T) )

// Linear fit:
// Formula: Y = α × σ²_xx + β
//   β → intrinsic Berry curvature quadrupole Q_xxz  ← main physical result
//   α → extrinsic skew scattering contribution
```

Temperature matching: interpolate Rxx(T) from RT curve to discrete 3w file temperatures (nearest or linear).

---

## Output Plots (6 tabs)

| Tab | Plot | Data source |
|-----|------|-------------|
| 1 | R¹ω vs H — stacked by temperature | 3w field sweeps |
| 2 | R³ω vs H — stacked by temperature | 3w field sweeps |
| 3 | RAHE¹ω and RAHE³ω vs T | Fitted from field sweeps |
| 4 | Hc¹ω and Hc³ω vs T | Fitted from field sweeps |
| 5 | Rxx vs T | RT files |
| **6** | **E^(3ω)\_AHE / (E\_xx³ × σ\_xx) vs σ²\_xx + linear fit** | **Fig 5b — main result** |

---

## Architecture

### New domain additions (`Domain/Models.swift`)
```swift
// WorkflowKind
case threeOmegaAHE = "3ω AHE"

// MeasurementType
case threeOmegaAHE = "3ω AHE"
```

### Implementation order

| # | File | Action | Purpose |
|---|------|--------|---------|
| 1 | `Domain/Models.swift` | MODIFY | Add two enum cases |
| 2 | `Workbench/V3/ThreeOmegaIngestionContracts.swift` | NEW | Data contracts (all value types) |
| 3 | `UseCases/ThreeOmegaLVMParser.swift` | NEW | LVM file parser |
| 4 | `UseCases/ThreeOmegaFitUseCase.swift` | NEW | I_rms, RAHE, Hc, centering |
| 5 | `UseCases/ThreeOmegaScalingUseCase.swift` | NEW | Fig 5b formula |
| 6 | `UseCases/IngestThreeOmegaSelectionsUseCase.swift` | NEW | Multi-file orchestration |
| 7 | `Extensions/ExtensionPoints.swift` | MODIFY | Add 4 ThreeOmegaAHE* extension structs |
| 8 | `Workflow/WorkflowRegistry.swift` | MODIFY | Register new bundle |
| 9 | `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | NEW | @MainActor @Observable state |
| 10 | `Features/Workbench/ThreeOmegaWorkspaceView.swift` | NEW | SwiftUI view (6 tabs) |
| 11 | `Workflow/WorkflowWorkspaceRegistry.swift` | MODIFY | Enable "3W" case |
| 12 | `Tests/SpinLabAppTests/V400ThreeOmegaTests.swift` | NEW | Unit tests (≥20) |

### Key data contracts

```swift
enum ThreeOmegaFileKind: String, Codable, Hashable, Sendable {
    case fieldSweep   // "3w_" files — one temperature per file
    case rtSweep      // "RT_" files — Rxx vs T
}

struct LVMParsedFile: Sendable {
    var columnNames: [String]       // 11 canonical names, positional
    var rows: [[String]]
    var iRms: Double                // derived from data: mean(Col1/Col9)
    var iAmpFallback: Double        // from filename (backup)
    var temperatureK: Double        // from filename (NaN for RT files)
    var angleLabel: String
    var fileKind: ThreeOmegaFileKind
}

struct ThreeOmegaFieldSweepResult: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var temperatureK: Double
    var hField: [Double]            // Oe
    var r1omega: [Double]           // Ω, centered
    var r3omega: [Double]           // Ω, centered
    var v3omegaAtZeroField: Double  // V³ω_X at H≈0 (for Method B)
    var rahe1omega: Double?         // Ω, from high-field fit
    var rahe3omega: Double?         // Ω, from high-field fit
    var hc1omega: Double?           // Oe
    var hc3omega: Double?           // Oe
    var warnings: [String]
}

struct ThreeOmegaRTResult: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var temperatureK: [Double]
    var rxx: [Double]               // Ω, longitudinal resistance
}

struct ThreeOmegaGeometry: Codable, Hashable, Sendable {
    var lxx: Double                 // μm — Hall bar longitudinal length
    var lxy: Double                 // μm — Hall bar transverse width
    var dNm: Double                 // nm — film thickness
    var isComplete: Bool { lxx > 0 && lxy > 0 && dNm > 0 }
}

struct ThreeOmegaScalingPoint: Codable, Hashable, Sendable {
    var sigma2xx: Double            // X-axis: σ²_xx
    var scalingY: Double            // Y-axis: E^(3ω)_AHE / (E_xx³ × σ_xx)
    var temperatureK: Double
}

struct ThreeOmegaScalingResult: Codable, Hashable, Sendable {
    var points: [ThreeOmegaScalingPoint]
    var beta: Double?               // Berry curvature quadrupole Q_xxz
    var alpha: Double?              // skew scattering
    var rSquared: Double?
    var warnings: [String]
}
```

### Workspace store

```swift
@MainActor @Observable final class ThreeOmegaWorkspaceStore {
    // Selection
    var selectedSearchResultIDs: Set<String> = []
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []

    // User-supplied geometry (session-only, not persisted)
    var geometry = ThreeOmegaGeometry(lxx: 0, lxy: 0, dNm: 0)

    // Analysis outputs
    private(set) var ingestionResult: ThreeOmegaIngestionResult?
    private(set) var scalingResult: ThreeOmegaScalingResult?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?
    var activeTab: ThreeOmegaWorkbenchTab = .fieldSweep1omega

    // 6 rendered plot images (PNG)
    private(set) var plotR1omega, plotR3omega, plotRAHEvsT,
                     plotHcvsT, plotRT, plotScaling: Data?

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var scalingTask: Task<Void, Never>?

    func runAnalysis()   // parse + fit all files; spawns Task.detached
    func runScaling()    // recompute Fig 5b only (cheap; re-run on geometry change)
    func clearAll()
}

enum ThreeOmegaWorkbenchTab: String, CaseIterable, Identifiable {
    case fieldSweep1omega = "R¹ω vs H"
    case fieldSweep3omega = "R³ω vs H"
    case raheVsT          = "RAHE vs T"
    case hcVsT            = "Hc vs T"
    case rtCurve          = "Rxx vs T"
    case scaling          = "Fig 5b"
    var id: String { rawValue }
}
```

### UI layout

```
┌─────────────────────────┬──────────────────────────────────────────┐
│ LEFT (360–640 pt)       │ RIGHT                                    │
│                         │ [R¹ω vs H][R³ω vs H][RAHE vs T]         │
│ Title: "3ω AHE"         │ [Hc vs T][Rxx vs T][Fig 5b]             │
│                         │ ─────────────────────────────────────    │
│ Search Section          │ WorkbenchStatusArea                      │
│ [Search]  [Analyze]     │ WorkbenchPlotCanvas  (active tab)        │
│ [Clear]                 │                                          │
│                         │ (Fig 5b tab only:)                       │
│ GroupBox "Geometry"     │   β = xxx  (Berry curvature quadrupole)  │
│   L_xx (μm): [___]      │   α = xxx                               │
│   L_xy (μm): [___]      │   R² = xxx                              │
│   d    (nm):  [___]     │                                          │
│   [Run Scaling]         │                                          │
│                         │                                          │
│ Results List            │                                          │
│ (scrollable hit rows)   │                                          │
└─────────────────────────┴──────────────────────────────────────────┘
```

Geometry parameters are **session-only** (not persisted). `runScaling()` is separate from `runAnalysis()` — geometry changes trigger only a cheap re-run of the scaling formula, not a full re-parse.

### Extension bundle additions (`ExtensionPoints.swift`)

```swift
struct ThreeOmegaAHEWorkflowExtension: WorkflowExtension {
    let workflow: SpinLabDomain.WorkflowKind = .threeOmegaAHE
    let supportedMeasurementTypes = [SpinLabDomain.MeasurementType.threeOmegaAHE]
}
struct ThreeOmegaAHEMetadataExtension: MetadataExtension {
    // parseFilename: T, I_amp, angle via regex; .lvm in supported extensions
}
struct ThreeOmegaAHEAnalysisModuleExtension: AnalysisModuleExtension { }
struct ThreeOmegaAHEViewExtension: ViewExtension {
    let displayName = "3ω AHE Workspace"
}
```

Register in `WorkflowRegistry.registerBuiltins()` and enable `"3W"` case in `WorkflowWorkspaceRegistry`.

---

## Verification

### Build
```bash
./scripts/build_desktop_app.sh debug
```

### Manual functional test (with sample data `20260327_STO111_PN69`)
1. Import all `.lvm` files from `0deg/` → confirm each in Inbox
2. Open Workbench → 3ω AHE
3. Select all 17 field-sweep files + 2 RT files → Analyze
4. Verify Tabs 1–5 render with correct curves
5. Enter L_xx=26, L_xy=21, d=30 → Run Scaling → Tab 6 shows scatter + linear fit
6. Repeat for `30deg/`, `60deg/`

### Unit tests (`V400ThreeOmegaTests.swift`, ≥20 tests)
- **LVM parser**: header skip, 11 canonical columns, I_rms from data, T/kind from filename
- **FitUseCase**: centering, RAHE ideal step function, Hc ideal loop, I_rms derivation
- **Ingestion**: 3 files → 3 sorted results, parse-once guarantee, RT separation, failure tolerance
- **Scaling**: linear fit accuracy (synthetic data), missing RT → warning, geometry.isComplete
- **Domain/registry**: WorkflowKind Codable roundtrip, registry contains bundle after bootstrap

---

## Open Questions (resolve after first plot)

1. **V^(3ω)_AHE extraction method** — Method A (intercept-distance) vs Method B (H=0 + T_ref).
   Deciding factor: whether V³ω shows a detectable antisymmetric jump at the 1ω switching field.
   Empirical hint: at 5K, no obvious jump in V³ω at Hc ≈ 11000 Oe (but may be hidden by background).

2. **Multiple RT files per angle folder** — 0deg has two RT files (H=+0.089 Oe and H=−0.030 Oe).
   Decision: use one, average, or pick by closer-to-zero field.

3. **Temperature interpolation** — match Rxx(T) from continuous RT curve to discrete 3w temperatures:
   nearest-neighbour or linear interpolation.
