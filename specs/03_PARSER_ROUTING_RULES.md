# SpinLab Parser and Routing Rules

Status: active

## Parse sources
- file name
- parent folder
- grandparent folder

## File type policy
- Included in import/classification: `.dat`, `.lvm`
- Ignored in classification/routing: `.gph`

## Sample key rules
- Primary sample patterns:
  - `PN\\d+`
  - `PT\\d+`
  - `S\\d+`
- Folder-derived sample is allowed as fallback only when unique.

## Channel mapping rules
- Channel aliases:
  - `ch1/c1`
  - `ch2/c2`
  - `ch3/c3`
- Channel-level mapping has priority over default file-level sample mapping.

## Unified routing formula
For each channel, route sample key is:
`channelSampleKey ?? defaultSampleKey ?? folderDerivedSampleKey`

Then group channels by sample key into route targets.

This single rule must handle both:
- one file -> one sample
- one file -> multiple samples

## Conflict behavior
- If sample mapping is unresolved or conflicting, never auto-route silently.
- Mark as review-required and require manual confirmation.

## Queue status rules
- Root definition:
  - Queue status is based on whether parsed sample routing can be mapped to the required existing Library drawer target(s).
- File-level delivery:
  - If the file-level route maps to an existing drawer, mark as `library-matched`.
  - If not, mark as `review-required`.
- Channel-level delivery:
  - Every reported channel must map to its own existing drawer target.
  - If any channel cannot be uniquely mapped to a drawer target, mark as `review-required`.
  - Route unresolved metadata alone does not force review when final drawer mapping is still unique and valid.
- Complement policy:
  - File-level sample info may complete missing channel sample info.
  - Channel-to-channel cross-completion is not allowed.

## Inbox drawer matching runtime rule (V2.2.0 current)
- Matching is token-coverage-based:
  - normalize sample input and drawer keys into uppercase token sets.
  - split alpha-numeric components during tokenization.
  - input token set must be subset of candidate drawer token set.
- Success contract:
  - exactly one candidate -> mapped drawer.
  - zero or multiple candidates -> unresolved (`?`).

## Inbox registry lookup runtime rule (V2.2.0 current)
- Rule/logic separation:
  - lookup policy is implemented in dedicated registry rulebook interfaces.
- Sheet indexing:
  - sheets prefixed with `__` are not indexed for sample lookup.
  - sheets without recognized sample-id column are not indexed.
- Query path:
  - lookup executes as `sampleID -> indexed row(s)` direct query.
  - prefix-to-sheet mapping is informational and is not a routing dependency for lookup.

## Duplicate import guard
- Duplicate import match rule: `fileName + contentHash`.
- If matched, reject duplicate import and do not create a new pending route item.

## Conditions and tags
- Parse and preserve:
  - workflow
  - measurement tags
  - substrate/device-level hints
  - conditions (`temperature`, `current`, `field`)
- Persist both raw and normalized values in archive metadata.
