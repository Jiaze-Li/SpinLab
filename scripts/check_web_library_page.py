#!/usr/bin/env python3
"""Open the exported web library page in headless Chrome and check what it really shows.

The static validator only reads files; it cannot see a feature script overwriting another one at runtime.
This check serves the export locally, loads it in Chrome (``--headless --dump-dom``) and asserts:

  * the sample list is grouped by prefix (group headers, no flat list)
  * the "Synced" time is shown
  * the "New sample" entry is present
  * switching to Compare mode shows the compare list, and switching back restores the grouped list

Exit codes: 0 = PASS, 1 = FAIL, 3 = NOT RUN (no headless browser found; never printed as PASS).
"""
from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_NOT_RUN = 3

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "scripts" / "tests" / "web_library_compare_harness.js"
CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
]
CHECK_PAGE = "__check_page__.html"


def find_chrome() -> str | None:
    override = os.environ.get("SPINLAB_CHROME")
    if override:
        return override if Path(override).exists() else None
    for candidate in CHROME_CANDIDATES:
        if Path(candidate).exists():
            return candidate
    for name in ("google-chrome", "chromium", "chrome"):
        found = shutil.which(name)
        if found:
            return found
    return None


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        pass


class _PageCheckServer(http.server.ThreadingHTTPServer):
    # Chrome opens 6+ concurrent connections for CSS/JS/data; Python's default backlog (5) can drop them.
    request_queue_size = 64
    daemon_threads = True


def dump_dom(chrome: str, url: str, profile_dir: Path) -> str:
    completed = subprocess.run(
        [
            chrome,
            "--headless=new",
            "--disable-gpu",
            "--no-first-run",
            "--no-default-browser-check",
            f"--user-data-dir={profile_dir}",
            "--virtual-time-budget=15000",
            "--dump-dom",
            url,
        ],
        capture_output=True,
        text=True,
        timeout=90,
        check=False,
    )
    return completed.stdout


def extract_result(dom: str) -> dict | None:
    match = re.search(r'<pre id="check-result">(.*?)</pre>', dom, re.S)
    if not match:
        return None
    import html

    return json.loads(html.unescape(match.group(1)))


def evaluate(result: dict) -> list[str]:
    """Return failed assertions (empty = pass)."""
    failures: list[str] = []
    if result.get("stage") != "done":
        failures.append(f"page script stopped at stage {result.get('stage')!r}")
    if result.get("errors"):
        failures.append(f"page errors: {result['errors']}")
    samples = result.get("samples") or {}
    if not samples.get("groupHeads"):
        failures.append("sample list shows no prefix group headers")
    if samples.get("flatRows"):
        failures.append(f"sample list also shows {samples['flatRows']} flat rows outside any group")
    if samples.get("syncHidden") is not False or not str(samples.get("syncText") or "").startswith("Synced"):
        failures.append(f"sync time not shown (text={samples.get('syncText')!r}, hidden={samples.get('syncHidden')!r})")
    if not str(samples.get("newSampleHref") or "").endswith("new-sample.html"):
        failures.append(f"New sample entry missing (href={samples.get('newSampleHref')!r})")
    compare = result.get("compare") or {}
    if compare.get("modeTabs") != 2 or compare.get("activeMode") != "compare":
        failures.append(f"Compare mode did not open (tabs={compare.get('modeTabs')}, active={compare.get('activeMode')!r})")
    if compare.get("groupHeads"):
        failures.append("Compare mode still shows the prefix-grouped sample list")
    if not (compare.get("compareGroupCards") or compare.get("compareEmpty") or compare.get("compareGroupRows")):
        failures.append("Compare mode shows neither compare groups nor the compare empty state")
    restored = result.get("restored") or {}
    if restored.get("activeMode") != "samples" or not restored.get("groupHeads") or restored.get("flatRows"):
        failures.append(f"switching back did not restore the grouped list ({restored})")
    if restored.get("compareGroupCards") or restored.get("compareEmpty"):
        failures.append("compare list still visible after switching back")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output-dir", required=True, type=Path, help="exported public/ directory")
    parser.add_argument("--harness-path", type=Path, default=HARNESS, help="path to web_library_compare_harness.js")
    parser.add_argument("--dump-json", type=Path, help="write the full page result (incl. markup) to this file")
    args = parser.parse_args()
    output_dir: Path = args.output_dir.resolve()
    harness_path: Path = args.harness_path.resolve()

    chrome = find_chrome()
    if chrome is None:
        print("NOT RUN: no headless browser (Google Chrome / Chromium not found)")
        return EXIT_NOT_RUN
    index = output_dir / "index.html"
    if not index.is_file():
        print(f"FAIL: {index} not found")
        return EXIT_FAIL
    if not harness_path.is_file():
        print(f"FAIL: {harness_path} not found")
        return EXIT_FAIL

    with tempfile.TemporaryDirectory(prefix="spinlab-page-check-") as tmp:
        serve_dir = Path(tmp) / "site"
        shutil.copytree(output_dir, serve_dir)
        page = index.read_text(encoding="utf-8")
        harness = harness_path.read_text(encoding="utf-8")
        page = page.replace("</body>", f"<script>\n{harness}\n</script>\n</body>")
        (serve_dir / CHECK_PAGE).write_text(page, encoding="utf-8")

        handler = functools.partial(_QuietHandler, directory=str(serve_dir))
        server = _PageCheckServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_address[1]}/{CHECK_PAGE}"
            dom = dump_dom(chrome, url, Path(tmp) / "profile")
        finally:
            server.shutdown()

    result = extract_result(dom)
    if result is None:
        print("FAIL: the page produced no check result (script did not run)")
        return EXIT_FAIL
    if args.dump_json:
        args.dump_json.write_text(json.dumps(result, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
    failures = evaluate(result)
    summary = json.dumps({k: result.get(k) for k in ("samples", "compare", "restored")}, ensure_ascii=False, sort_keys=True)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        print(f"DOM assertions input: {summary}")
        return EXIT_FAIL
    print(f"PASS: web library page behaves as expected in headless Chrome\nDOM assertions input: {summary}")
    return EXIT_PASS


if __name__ == "__main__":
    sys.exit(main())
