# SpinLab Architecture Overview

This document explains the current architecture for human readers.

## High-level shape

SpinLab is organized around three feature domains:
- Inbox
- Library
- Workbench

Runtime flow is:
- Import -> Confirm -> Visualize -> Analyze -> Save -> Archive

`SpinLabAppState` acts as the app shell and coordinator.
Feature state and single-domain behavior live in FeatureStores.

## Layer boundaries

Core layering:
- Input/Files
- Parser/Import pipeline
- Domain model
- UseCase/Service/Orchestrator
- Repository/Store (I/O and persistence)
- AppState / FeatureStore state surface
- View / ViewModel

Design intent:
- Keep business logic out of Views.
- Keep storage and file I/O out of UI state objects.
- Keep parser/routing boundaries explicit and testable.

## App shell responsibilities

`SpinLabAppState` should mainly do:
- Cross-feature coordination (Inbox <-> Library <-> Workbench)
- Global concerns (navigation, alerting, audit context)

`SpinLabAppState` should avoid accumulating single-domain details that belong inside a FeatureStore.

## FeatureStore responsibilities

FeatureStores hold:
- Domain-scoped observable state
- Domain methods (single-feature operations)
- Projection subscriptions for their own repositories/streams

FeatureStores should expose explicit outcome-based methods for complex operations where useful.

## UseCase and Service split

UseCase:
- Stateless input/output business operation
- Easy to unit test in isolation

Service/Orchestrator:
- Stateful or multi-step domain orchestration
- Coordinates multiple lower-level operations in one domain

## Presentation-only container exception

Not every state holder must be an observable class.
A tiny presentation-only container with no autonomous behavior may stay as a value type (`struct`) if this reduces complexity.

## Current migration direction

Current direction is to keep slimming `SpinLabAppState` toward an app-shell role by:
- Moving single-domain methods into the corresponding FeatureStore
- Removing compatibility passthrough properties once views/tests migrate to namespaced access
- Preserving strict boundaries across Import pipeline stages

## Temporary exceptions (migration seam)

Some transitional seams still exist while refactor is in progress.
These are temporary and should shrink over time, not expand.

Operational rules for contributors/agents:
- Do not add new compatibility passthrough properties on `SpinLabAppState`.
- If you touch a migration seam, prefer reducing it in the same change.
- New single-domain behavior must still be implemented in FeatureStore.

## Related docs

- Routing stage boundaries:
  - `docs/architecture/ROUTING_LAYER_BOUNDARIES.md`
- Agent execution rules:
  - `AGENTS.md`
