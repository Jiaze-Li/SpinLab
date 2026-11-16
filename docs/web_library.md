# Web Library UI

This note records the source-of-truth rule for the static Web Library UI.

## Source Of Truth

- Web Library UI source currently lives in `Resources/WebLibraryTemplate/`
- Generated output lives in `../SpinLab-Web-Library/public/`
- Never treat `../SpinLab-Web-Library/public/` as the source of truth

## Where the web library repo lives

- Scripts look for `SpinLab-Web-Library` in this order: the `SPINLAB_WEB_LIBRARY_DIR` environment variable, a sibling of this repo, then a sibling of this repo's parent folder (it may sit outside the SpinLab folder).
- The `../SpinLab-Web-Library/public/` paths below mean "that repo's `public/`", wherever it is.

## Editing Rule

- To change Web Library UI, edit `Resources/WebLibraryTemplate/`
- Do not manually edit `../SpinLab-Web-Library/public/app.js` or `styles.css` as the primary fix
- After changing the exporter, run `./scripts/publish_web_library.sh` to regenerate and publish

## Publishing

- Publishing is started and shown in the app's **Publish** area (sidebar, next to Inbox / Library / Workbench). Library has no publish button or status.
- One orchestration entry (`SpinLabAppState.publishWebLibrary`) runs `scripts/publish_web_library.sh`; the manual button and the automatic publish after a Library / Rules Book change both use it. Status lives in `PublishFeatureStore` (memory only).
- "Pushed to GitHub" is the most the app can know. Whether Cloudflare finished deploying is never checked and is shown as not verified.
- The script runs: export → validate → real page check in headless Chrome → change check → git commit/push. The Library to publish is the one selected in SpinLab: the app passes it as `SPINLAB_LIBRARY_ROOT`. The script has no default Library; run alone it exits with an error unless that variable is set. With no Library selected the app does not start the script and Publish shows why. Publish shows which Library each run used.
- The page check (`scripts/check_web_library_page.py`) opens the exported page and asserts the grouped sample list, the Synced time, the New sample entry and Compare mode. Without Chrome it prints `NOT RUN` (exit 3), never PASS, and publishing continues. If it fails the script stops before git.

## Script Extension Rule

- Template scripts must not replace a function that another file (or an earlier part of the file) declared. `app.js` exposes `registerFeature()` and calls registered features through hooks (`renderSampleList`, `renderChartsNav`, `stepSelectedSample`, `renderMetadataPanel`, `renderMetadata`, `attachEvents`, `reRender`); `compare.js` registers its versions. Add a new hook in `app.js` when a feature needs to extend another function.
- `validate_web_library.py` fails when it finds such a reassignment.
- Script and stylesheet addresses carry `?v=<content hash>` (from `__ASSET_VERSION__`) and `_headers` sets `Cache-Control: no-cache`; the validator checks both. Keep them when changing the publish flow.
- A web change is only accepted with a real headless-Chrome run of the page check, not just the static validator.

## Generated Output

- `../SpinLab-Web-Library/public/` is disposable generated output
- It may be replaced on every publish
- Manual edits there will be lost

## Future Refactor Note

- If the HTML/CSS/JS templates later move again, that directory becomes the Web Library UI source of truth
- Until that refactor happens, `Resources/WebLibraryTemplate/` remains authoritative

## Sample Notes

- Notes are sample-scoped plain text, edited from the detail panel, and rendered with escaping.
- The note API must live under the same Pages app at `GET /api/note?sample_id=...` and `PUT /api/note`.
- Notes must be stored in Cloudflare D1, not in `public/`, not in `library.json`, and not in the local SpinLab Library snapshot.
- Required table shape:

  ```sql
  CREATE TABLE IF NOT EXISTS sample_notes (
    sample_id TEXT PRIMARY KEY,
    note_text TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL
  );
  ```

- Required v1 deployment setup:
  - Bind the D1 database into the Pages Function runtime.
  - Keep the API same-origin with the web app.
  - Rely on the existing Cloudflare Access protection on the site for v1.
  - Add explicit Access JWT validation later only if deployment setup requires it.
