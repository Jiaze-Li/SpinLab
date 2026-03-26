# Routing Layer Boundaries (V2.2.1)

Directory contract for `Sources/SpinLabApp/Import`:

- `Parse/`: filename tokenization and semantic extraction only.
- `Route/`: route planning only (candidate generation, no final verdict).
- `Match/`: Library drawer matching/indexing only.
- `Evaluate/`: final routing verdict and warning reasoning only.
- `Presentation/`: UI-facing route/warning projection only.
- `Rules/`: rule loading/compilation/runtime metadata only.

Minimum dependency constraints:

1. `Route/` can depend on `Parse/` and `Rules/`; it must not depend on `Presentation/`.
2. `Evaluate/` can depend on `Route/` and `Match/`; it must not call parser internals.
3. `Presentation/` can depend on `Evaluate/` outputs only; it must not invoke rule loading or matching.
4. App layer must access routing via `InboxRoutingState` + capability contracts, not concrete internals.

Enforcement in code:

- `InboxRoutingState` is the only App-level routing façade.
- `RoutingCapabilities` + `RuleRuntimeCapability` are the capability boundaries consumed by App state.
