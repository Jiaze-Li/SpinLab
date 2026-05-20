# Web Library UI

This note records the source-of-truth rule for the static Web Library UI.

## Source Of Truth

- Web Library UI source currently lives in `Resources/WebLibraryTemplate/`
- Generated output lives in `../SpinLab-Web-Library/public/`
- Never treat `../SpinLab-Web-Library/public/` as the source of truth

## Editing Rule

- To change Web Library UI, edit `Resources/WebLibraryTemplate/`
- Do not manually edit `../SpinLab-Web-Library/public/app.js` or `styles.css` as the primary fix
- After changing the exporter, run `./scripts/publish_web_library.sh` to regenerate and publish

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
