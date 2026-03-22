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
