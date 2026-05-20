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
