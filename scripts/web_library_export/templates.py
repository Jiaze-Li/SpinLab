from __future__ import annotations

import hashlib
import shutil
from pathlib import Path

# Every file in Resources/WebLibraryTemplate that ends up in the published public/ folder.
WEB_TEMPLATE_FILES = [
    "index.html",
    "styles.css",
    "app-search.js",
    "app-notes-report.js",
    "app.js",
    "new-sample.html",
    "new-sample.css",
    "new-sample.js",
    "compare.js",
    "compare.css",
    "compare-overview.css",
    "_headers",
]

# Template files that no longer exist. Removed from the output so an old published copy cannot linger.
RETIRED_WEB_TEMPLATE_FILES = ["compare-overview.js", "compare-scope.js"]


def clean_generated_output(output_dir: Path) -> None:
    for name in [*WEB_TEMPLATE_FILES, *RETIRED_WEB_TEMPLATE_FILES]:
        path = output_dir / name
        if path.exists():
            path.unlink()
    for name in ["data", "assets"]:
        path = output_dir / name
        if path.exists():
            shutil.rmtree(path)


def web_library_template_dir(override: Path | str | None = None) -> Path:
    if override is not None:
        return Path(override).expanduser().resolve()
    root = Path(__file__).resolve().parents[2]
    bundled = root / "WebLibraryTemplate"
    if bundled.exists():
        return bundled
    return root / "Resources" / "WebLibraryTemplate"


def read_web_library_template(name: str, template_dir: Path | None = None) -> str:
    template_path = (template_dir or web_library_template_dir()) / name
    if not template_path.exists():
        raise RuntimeError(f"Missing Web Library template: {template_path}")
    return template_path.read_text(encoding="utf-8")


def web_asset_version(template_dir: Path) -> str:
    """Short hash of every script and stylesheet, so a changed file gets a new address and phones never reuse a stale copy."""
    digest = hashlib.sha1()
    for name in sorted(WEB_TEMPLATE_FILES):
        if name.endswith((".js", ".css")):
            digest.update((template_dir / name).read_bytes())
    return digest.hexdigest()[:10]


def render_web_template(name: str, template_dir: Path | None = None) -> str:
    template_dir = template_dir or web_library_template_dir()
    text = (template_dir / name).read_text(encoding="utf-8")
    return text.replace("__ASSET_VERSION__", web_asset_version(template_dir))


def write_web_library_templates(output_dir: Path, template_dir: Path | None = None) -> None:
    # Web Library UI source of truth is Resources/WebLibraryTemplate/ (or bundled WebLibraryTemplate/).
    # <web_repo>/public/ is generated output and may be replaced on every publish.
    # Do not edit generated public files directly.
    resolved_dir = template_dir or web_library_template_dir()
    for name in WEB_TEMPLATE_FILES:
        (output_dir / name).write_text(render_web_template(name, resolved_dir), encoding="utf-8")
