# SpinLab Agent Instructions

SpinLab is a macOS research app for magnetic experiment workflow management.

Core structure:
Inbox
Workbench
Library

Core workflow:
Import → Confirm → Visualize → Analyze → Save → Archive

Core objects:
Project
Batch
Sample
Device
Measurement
Dataset
Result
Comparison

Rules:
Sample can belong to multiple projects.
Batch is different from physical sample.
Device is optional.
Dataset maps to one measurement by default.
Results can be rated.

Architecture principle:
Add features through extension modules:
workflow
analysis module
metadata
view

V1 focus:
Inbox import
Library browsing
Workbench plotting
one workflow only

Change boundary policy (strict):
UI-only tasks may modify only:
- Sources/SpinLabApp/Features/Library/**
- Sources/SpinLabApp/UI/**

UI-only tasks must NOT modify parser/state/registry logic files, including:
- Sources/SpinLabApp/App/SpinLabAppState.swift
- Sources/SpinLabApp/Library/LibraryRegistryParser.swift
- any parser/registry logic under Sources/SpinLabApp/Library/**

If a request requires both UI and logic changes:
- stop and explicitly split into two tasks first
- complete UI and logic in separate rounds
- do not mix both in one round

Parser/state/registry logic changes must be:
- explicitly called out before implementation
- handled in a dedicated round

Layered architecture policy (global, not Library-only):
- Enforce pipeline: Input (Excel/files) -> Parser -> Model -> UseCase/Service -> Repository/Store -> UI.
- Parser responsibility: parse source structure and preserve source order semantics (for example XLSX column order).
- Model responsibility: carry both raw data and ordered/view-ready projections when order matters.
- UseCase/Service responsibility: execute workflows (refresh/diff/confirm/import) without UI code and without storage details.
- Repository/Store responsibility: persistence and filesystem operations only; no business policy decisions.
- UI responsibility: render model/view-model data only; do not sort, infer, or rewrite business semantics.

Separation rules:
- UI must not decide metadata ordering rules.
- Ordering/tokenization/normalization logic belongs to parser/model/service layers.
- When a change touches both UI and logic/storage, split into separate tasks and commits.

Global shell layout policy:
- Use a stable three-column app shell as default:
  - left: navigation (Inbox / Workbench / Library, with room for future secondary menu)
  - center: workspace/actions (load/create/save/refresh/review and other primary operations)
  - right: inspector/output (details, plots, metadata, previews)
- Keep critical workflow actions in the center workspace column; avoid making the right column the primary action surface.
- Keep right column reusable across modules (sample detail now, plot/result/detail panels later).
