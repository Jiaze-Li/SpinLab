# Web Library UI

This note records the source-of-truth rule for the static Web Library UI.

## Source Of Truth

- Web Library UI source lives in `Resources/WebLibraryTemplate/` (and is packaged into `SpinLab.app/Contents/Resources/Publish/WebLibraryTemplate/` when building the desktop app)
- Generated output lives in `<web_repo>/public/` (inside the local `SpinLab-Web-Library` repository configured in SpinLab)
- Never treat `<web_repo>/public/` as the source of truth

## Where the web library repo lives

- The web repository location is a user-configured setting in SpinLab (`LibrarySettings.webLibraryRepoPath`, stored in `library_settings.json`), visible and editable on the **Publish** page via `"Choose Web Repository..."`.
- Scripts never probe sibling folders (`../SpinLab-Web-Library`); when run from SpinLab, the app passes the configured repository path explicitly, and when run standalone from the command line, `--web-repo` (or `SPINLAB_WEB_LIBRARY_DIR`) and `--library-root` (or `SPINLAB_LIBRARY_ROOT`) must be provided explicitly.

## Editing Rule

- To change Web Library UI, edit `Resources/WebLibraryTemplate/`
- Do not manually edit `<web_repo>/public/app.js` or `styles.css` as the primary fix
- Rebuild the desktop app (`./scripts/build_desktop_app.sh debug`) so `SpinLab.app/Contents/Resources/Publish/` carries the updated templates and scripts, or pass explicit paths to `./scripts/publish_web_library.sh`

## Publishing

- Publishing is started, configured, and shown in the app's **Publish** area (sidebar, next to Inbox / Library / Workbench). Library has no publish button or status.
- `PublishFeatureStore` (Features/Publish) owns publishing: its one entry (`publishWebLibrary`) validates the selected Library and configured Web Repository, then runs `scripts/publish_web_library.sh` from the app's bundled `Contents/Resources/Publish/` directory through `WebLibraryPublishService`; the manual button and the automatic publish (`WebLibraryAutoPublisher`) after a Library / Rules Book change both use it. Status is memory only. `SpinLabAppState` only creates the store, supplies the selected Library and Web Repository closures, and forwards "Library changed" / "Rules section saved".
- Publish displays the selected Library path, the configured Web Repository path, the bundled script/template version (`AppVersion.current` + short SHA-1 fingerprint), and the last run's outcome, stage, and timestamp.
- "Pushed to GitHub" is the most the app can know. Whether Cloudflare finished deploying is never checked and is shown as not verified.
- The script runs: export → validate → real page check in headless Chrome → change check → git commit/push. Both the Library (`SPINLAB_LIBRARY_ROOT` / `--library-root`) and the Web Repository (`SPINLAB_WEB_LIBRARY_DIR` / `--web-repo`) come from SpinLab settings and have no default fallback; if either is unset, missing on disk, or (for the Web Repository) not a Git repository, publishing refuses to start at the launch stage and explains why.
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

## Sample Notes & Phone Write-Back

- See [`phone_writeback_contract.md`](phone_writeback_contract.md) for the complete field contract, ownership boundaries, and consistency check across the phone New Sample form (`/api/samples`), `NewSampleFields.swift`, `new_sample_form_schema.json`, and Sample Notes (`/api/note`).
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
