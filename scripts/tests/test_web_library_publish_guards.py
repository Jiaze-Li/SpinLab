"""Publish script, template guard, asset-version and real-page checks (all on temporary fixtures; nothing is pushed anywhere real)."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
TEMPLATE_DIR = ROOT / "Resources" / "WebLibraryTemplate"
sys.path.insert(0, str(SCRIPTS))

import check_web_library_page as page_check  # noqa: E402
import export_static_library as exporter  # noqa: E402
import validate_web_library as validator  # noqa: E402


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _make_library(root: Path) -> None:
    ids = [f"PN{n}-a" for n in range(1, 5)] + [f"LNO{n}-a" for n in range(1, 3)]
    _write_json(
        root / "index" / "library_index.json",
        {
            "version": 1,
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
            "batches": [{"id": i.split("-")[0], "displayName": i.split("-")[0], "sampleKeys": [i]} for i in ids],
            "samples": [{"id": i, "batchId": i.split("-")[0]} for i in ids],
            "metadataColumnOrder": [],
        },
    )


def _export(library: Path, out: Path) -> None:
    subprocess.run(
        [sys.executable, str(SCRIPTS / "export_static_library.py"), "--library-root", str(library), "--output-dir", str(out)],
        check=True, capture_output=True, text=True,
    )


def _git(*args: str, cwd: Path) -> str:
    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"}
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True, env=env).stdout


# --- no runtime function overrides (AC-09) ---------------------------------------------------------

def test_shipped_templates_have_no_runtime_overrides() -> None:
    sources = {p.name: p.read_text(encoding="utf-8") for p in TEMPLATE_DIR.glob("*.js")}
    assert validator.find_runtime_overrides(sources) == []


def test_guard_flags_a_function_replaced_by_another_file() -> None:
    sources = {
        "app.js": "function renderSampleList() {}\nfunction other() {}\n",
        "feature.js": "const base = renderSampleList;\nrenderSampleList = function wrapped() { base(); };\n",
    }
    problems = validator.find_runtime_overrides(sources)
    assert len(problems) == 1 and "feature.js:2" in problems[0] and "renderSampleList" in problems[0]


def test_guard_flags_a_reassignment_inside_the_declaring_file() -> None:
    problems = validator.find_runtime_overrides({"app.js": "function a() {}\na = function () {};\n"})
    assert len(problems) == 1


def test_guard_ignores_comparisons_and_unrelated_assignments() -> None:
    sources = {"app.js": "function a() {}\nlet b = 1;\nif (a == b) {}\nconst c = a;\n"}
    assert validator.find_runtime_overrides(sources) == []


def test_validator_reports_override_in_exported_output(tmp_path: Path) -> None:
    out = tmp_path / "out"
    out.mkdir()
    (out / "app.js").write_text("function render() {}\n", encoding="utf-8")
    (out / "x.js").write_text("render = function () {};\n", encoding="utf-8")
    errors: list[str] = []
    validator.validate_no_runtime_function_overrides(out, errors)
    assert len(errors) == 1


def test_removed_compare_scripts_are_not_shipped_and_are_cleaned_up(tmp_path: Path) -> None:
    assert "compare-overview.js" not in exporter.WEB_TEMPLATE_FILES
    assert "compare-scope.js" not in exporter.WEB_TEMPLATE_FILES
    out = tmp_path / "public"
    out.mkdir()
    (out / "compare-scope.js").write_text("old", encoding="utf-8")
    exporter.clean_generated_output(out)
    assert not (out / "compare-scope.js").exists()


# --- asset versions and cache (AC-11) --------------------------------------------------------------

def test_export_versions_assets_and_sets_no_cache(tmp_path: Path) -> None:
    library = tmp_path / "lib"
    _make_library(library)
    out = tmp_path / "out"
    _export(library, out)
    errors: list[str] = []
    validator.validate_asset_versioning(out, errors)
    assert errors == []
    for page in ("index.html", "new-sample.html"):
        text = (out / page).read_text(encoding="utf-8")
        assert "__ASSET_VERSION__" not in text
        assert "?v=" in text
    assert "Cache-Control: no-cache" in (out / "_headers").read_text(encoding="utf-8")


def test_asset_version_is_stable_and_changes_with_content(tmp_path: Path) -> None:
    copy = tmp_path / "template"
    shutil.copytree(TEMPLATE_DIR, copy)
    first = exporter.web_asset_version(copy)
    assert exporter.web_asset_version(copy) == first
    (copy / "app.js").write_text((copy / "app.js").read_text(encoding="utf-8") + "\n// changed\n", encoding="utf-8")
    assert exporter.web_asset_version(copy) != first


def test_asset_check_flags_unversioned_scripts_placeholder_and_missing_headers(tmp_path: Path) -> None:
    out = tmp_path / "out"
    out.mkdir()
    (out / "index.html").write_text(
        '<script src="./app.js"></script><script src="./b.js?v=__ASSET_VERSION__"></script>', encoding="utf-8")
    errors: list[str] = []
    validator.validate_asset_versioning(out, errors)
    joined = "\n".join(errors)
    assert "placeholder" in joined and "./app.js without" in joined and "_headers" in joined


# --- real page check (AC-10, AC-12) ----------------------------------------------------------------

def test_page_check_evaluation_rules() -> None:
    good = {
        "stage": "done", "errors": [],
        "samples": {"groupHeads": 2, "flatRows": 0, "syncHidden": False, "syncText": "Synced 11-16 08:00", "newSampleHref": "./new-sample.html"},
        "compare": {"modeTabs": 2, "activeMode": "compare", "groupHeads": 0, "compareEmpty": 1},
        "restored": {"activeMode": "samples", "groupHeads": 2, "flatRows": 0},
    }
    assert page_check.evaluate(good) == []
    flat = json.loads(json.dumps(good))
    flat["samples"]["groupHeads"] = 0
    flat["samples"]["flatRows"] = 5
    assert any("group headers" in f for f in page_check.evaluate(flat))
    no_sync = json.loads(json.dumps(good))
    no_sync["samples"]["syncHidden"] = True
    assert any("sync time" in f for f in page_check.evaluate(no_sync))
    no_new = json.loads(json.dumps(good))
    no_new["samples"]["newSampleHref"] = None
    assert any("New sample" in f for f in page_check.evaluate(no_new))
    stuck = json.loads(json.dumps(good))
    stuck["restored"]["groupHeads"] = 0
    assert any("restore" in f for f in page_check.evaluate(stuck))


def test_page_check_reports_not_run_without_a_browser(tmp_path: Path) -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPTS / "check_web_library_page.py"), "--output-dir", str(tmp_path)],
        env={**os.environ, "SPINLAB_CHROME": str(tmp_path / "no-such-chrome")}, capture_output=True, text=True,
    )
    assert result.returncode == 3
    assert result.stdout.startswith("NOT RUN")
    assert "PASS" not in result.stdout


@pytest.mark.skipif(page_check.find_chrome() is None, reason="NOT RUN: no headless browser")
def test_real_chrome_sees_grouped_list_sync_time_new_sample_and_compare(tmp_path: Path) -> None:
    library = tmp_path / "lib"
    _make_library(library)
    out = tmp_path / "out"
    _export(library, out)
    dump = tmp_path / "result.json"
    result = subprocess.run(
        [sys.executable, str(SCRIPTS / "check_web_library_page.py"), "--output-dir", str(out), "--dump-json", str(dump)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.startswith("PASS")
    page = json.loads(dump.read_text(encoding="utf-8"))
    assert page["samples"]["groupNames"] == ["PN", "LNO"] or sorted(page["samples"]["groupNames"]) == ["LNO", "PN"]


@pytest.mark.skipif(page_check.find_chrome() is None, reason="NOT RUN: no headless browser")
def test_real_chrome_fails_when_a_script_breaks_the_grouped_list(tmp_path: Path) -> None:
    library = tmp_path / "lib"
    _make_library(library)
    out = tmp_path / "out"
    _export(library, out)
    # The exact failure PR 210 hit: a later script overwrites the list renderer with the old flat one.
    (out / "compare.js").write_text(
        (out / "compare.js").read_text(encoding="utf-8")
        + '\nrenderSampleList = function () { els.sampleList.innerHTML = filteredSamples().map((s) => `<div class="sample-row">${s.id}</div>`).join(""); };\n',
        encoding="utf-8",
    )
    result = subprocess.run(
        [sys.executable, str(SCRIPTS / "check_web_library_page.py"), "--output-dir", str(out)], capture_output=True, text=True)
    assert result.returncode == 1
    assert "FAIL" in result.stdout and "PASS" not in result.stdout


# --- publish script (AC-03, AC-10) -----------------------------------------------------------------

def _publish_fixture(tmp_path: Path) -> tuple[dict[str, str], Path, Path]:
    library = tmp_path / "lib"
    _make_library(library)
    bare = tmp_path / "remote.git"
    subprocess.run(["git", "init", "--bare", "-b", "main", str(bare)], check=True, capture_output=True)
    web = tmp_path / "web"
    web.mkdir()
    _git("init", "-b", "main", cwd=web)
    (web / "README.md").write_text("web", encoding="utf-8")
    _git("add", "README.md", cwd=web)
    _git("commit", "-m", "init", cwd=web)
    _git("remote", "add", "origin", str(bare), cwd=web)
    _git("push", "-u", "origin", "main", cwd=web)
    env = {**os.environ, "SPINLAB_LIBRARY_ROOT": str(library), "SPINLAB_WEB_LIBRARY_DIR": str(web),
           "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"}
    return env, web, bare


def _run_publish(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["/bin/bash", str(SCRIPTS / "publish_web_library.sh")], env=env, capture_output=True, text=True)


def test_publish_script_pushes_to_local_remote_then_reports_no_changes(tmp_path: Path) -> None:
    env, web, bare = _publish_fixture(tmp_path)
    env["SPINLAB_CHROME"] = str(tmp_path / "no-such-chrome")  # NOT RUN path; real-page path covered above
    first = _run_publish(env)
    assert first.returncode == 0, first.stdout + first.stderr
    assert "Page check NOT RUN" in first.stdout
    assert "Cloudflare Pages will redeploy automatically." in first.stdout
    assert "Update SpinLab web snapshot" in _git("log", "--oneline", "-1", cwd=bare)
    second = _run_publish(env)
    assert second.returncode == 0, second.stdout + second.stderr
    assert "No web snapshot changes to publish." in second.stdout
    assert "Cloudflare Pages will redeploy" not in second.stdout


@pytest.mark.skipif(page_check.find_chrome() is None, reason="NOT RUN: no headless browser")
def test_publish_script_runs_real_page_check_and_stops_before_git_when_it_fails(tmp_path: Path) -> None:
    env, web, bare = _publish_fixture(tmp_path)
    ok = _run_publish(env)
    assert ok.returncode == 0, ok.stdout + ok.stderr
    assert "PASS: web library page" in ok.stdout
    # Break a template copy used by the script: point it at a broken template dir via a patched export.
    head_before = _git("rev-parse", "HEAD", cwd=bare)
    broken = tmp_path / "broken-root"
    for rel in ("scripts", "Resources/WebLibraryTemplate", "Sources/SpinLabApp/config"):
        shutil.copytree(ROOT / rel, broken / rel, ignore=shutil.ignore_patterns("__pycache__"))
    app = broken / "Resources" / "WebLibraryTemplate" / "compare.js"
    app.write_text(app.read_text(encoding="utf-8") + "\nfeatures.unshift({ renderSampleList: () => { els.sampleList.innerHTML = '<div class=\"sample-row\">x</div>'; } });\n", encoding="utf-8")
    new_library = tmp_path / "lib2"
    _make_library(new_library)
    _write_json(new_library / "extra.json", {"changed": True})
    env2 = {**env, "SPINLAB_LIBRARY_ROOT": str(new_library)}
    failed = subprocess.run(["/bin/bash", str(broken / "scripts" / "publish_web_library.sh")], env=env2, capture_output=True, text=True)
    assert failed.returncode == 1, failed.stdout + failed.stderr
    assert "Page check failed" in failed.stdout
    # The failure must come from the page assertions, not from a missing file or a crash.
    assert "FAIL:" in failed.stdout
    assert "Traceback" not in failed.stdout + failed.stderr and "FileNotFoundError" not in failed.stdout + failed.stderr
    assert _git("rev-parse", "HEAD", cwd=bare) == head_before


def test_publish_script_has_no_library_of_its_own(tmp_path: Path) -> None:
    env, web, bare = _publish_fixture(tmp_path)
    head = _git("rev-parse", "HEAD", cwd=bare)
    no_root = {k: v for k, v in env.items() if k != "SPINLAB_LIBRARY_ROOT"}
    missing = _run_publish(no_root)
    assert missing.returncode == 1
    assert "No Library given" in missing.stdout and "Exporting" not in missing.stdout
    gone = _run_publish({**env, "SPINLAB_LIBRARY_ROOT": str(tmp_path / "nope")})
    assert gone.returncode == 1
    assert "Library folder does not exist" in gone.stdout and "Exporting" not in gone.stdout
    assert _git("rev-parse", "HEAD", cwd=bare) == head
    script_text = (SCRIPTS / "publish_web_library.sh").read_text(encoding="utf-8")
    assert "/Users/jack" not in script_text
    assert "../SpinLab-Web-Library" not in script_text


def test_publish_script_requires_explicit_web_repo_and_supports_switching_repos(tmp_path: Path) -> None:
    env, web1, bare1 = _publish_fixture(tmp_path / "one")
    _, web2, bare2 = _publish_fixture(tmp_path / "two")
    env["SPINLAB_CHROME"] = str(tmp_path / "no-such-chrome")

    # 1. Missing web repo fails fast without probing sibling folders
    no_web = {k: v for k, v in env.items() if k != "SPINLAB_WEB_LIBRARY_DIR"}
    missing_web = _run_publish(no_web)
    assert missing_web.returncode == 1
    assert "No web library repository given" in missing_web.stdout and "Exporting" not in missing_web.stdout

    # 2. Non-existent web repo folder fails fast
    gone_web = _run_publish({**env, "SPINLAB_WEB_LIBRARY_DIR": str(tmp_path / "missing-web")})
    assert gone_web.returncode == 1
    assert "Missing web library repo" in gone_web.stdout and "Exporting" not in gone_web.stdout

    # 3. Folder without .git fails fast
    not_git = tmp_path / "plain-dir"
    not_git.mkdir()
    bad_git = _run_publish({**env, "SPINLAB_WEB_LIBRARY_DIR": str(not_git)})
    assert bad_git.returncode == 1
    assert "not a git repository" in bad_git.stdout and "Exporting" not in bad_git.stdout

    # 4. Switching web repo publishes to the newly selected repo without touching the first
    head1_before = _git("rev-parse", "HEAD", cwd=bare1)
    head2_before = _git("rev-parse", "HEAD", cwd=bare2)
    run2 = subprocess.run(
        [
            "/bin/bash",
            str(SCRIPTS / "publish_web_library.sh"),
            "--library-root",
            env["SPINLAB_LIBRARY_ROOT"],
            "--web-repo",
            str(web2),
        ],
        env={k: v for k, v in env.items() if k not in {"SPINLAB_LIBRARY_ROOT", "SPINLAB_WEB_LIBRARY_DIR"}},
        capture_output=True,
        text=True,
    )
    assert run2.returncode == 0, run2.stdout + run2.stderr
    assert _git("rev-parse", "HEAD", cwd=bare1) == head1_before
    assert _git("rev-parse", "HEAD", cwd=bare2) != head2_before


def test_standalone_scripts_require_explicit_paths_and_bundled_layout_runs_isolated(tmp_path: Path) -> None:
    # 1. validate_web_library.py without --output-dir fails immediately
    val_missing = subprocess.run(
        [sys.executable, str(SCRIPTS / "validate_web_library.py")],
        capture_output=True,
        text=True,
    )
    assert val_missing.returncode != 0
    assert "--output-dir" in val_missing.stderr

    # 2. export_static_library.py without required args fails immediately
    exp_missing = subprocess.run(
        [sys.executable, str(SCRIPTS / "export_static_library.py")],
        capture_output=True,
        text=True,
    )
    assert exp_missing.returncode != 0
    assert "--library-root" in exp_missing.stderr

    # 3. Simulated packaged Contents/Resources/Publish/ layout (no Sources/ or Resources/ parent tree)
    publish_bundle = tmp_path / "PublishBundle"
    (publish_bundle / "scripts" / "tests").mkdir(parents=True)
    (publish_bundle / "config").mkdir(parents=True)
    for name in (
        "publish_web_library.sh",
        "export_static_library.py",
        "validate_web_library.py",
        "check_web_library_page.py",
        "check_web_library_changes.py",
    ):
        shutil.copy2(SCRIPTS / name, publish_bundle / "scripts" / name)
    if (SCRIPTS / "web_library_export").is_dir():
        shutil.copytree(SCRIPTS / "web_library_export", publish_bundle / "scripts" / "web_library_export")
    shutil.copy2(SCRIPTS / "tests" / "web_library_compare_harness.js", publish_bundle / "scripts" / "tests" / "web_library_compare_harness.js")
    shutil.copytree(TEMPLATE_DIR, publish_bundle / "WebLibraryTemplate")
    shutil.copy2(ROOT / "Sources" / "SpinLabApp" / "config" / "new_sample_form_schema.json", publish_bundle / "config" / "new_sample_form_schema.json")

    env, web, bare = _publish_fixture(tmp_path / "bundled-run")
    env["SPINLAB_CHROME"] = str(tmp_path / "no-such-chrome")
    bundled_res = subprocess.run(
        [
            "/bin/bash",
            str(publish_bundle / "scripts" / "publish_web_library.sh"),
            "--library-root",
            env["SPINLAB_LIBRARY_ROOT"],
            "--web-repo",
            str(web),
        ],
        env={k: v for k, v in env.items() if k not in {"SPINLAB_LIBRARY_ROOT", "SPINLAB_WEB_LIBRARY_DIR"}},
        cwd=publish_bundle,
        capture_output=True,
        text=True,
    )
    assert bundled_res.returncode == 0, bundled_res.stdout + bundled_res.stderr
    assert (web / "public" / "data" / "library.json").is_file()
    assert (web / "public" / "data" / "new_sample_form.json").is_file()


@pytest.mark.skipif(not Path("/Applications/SpinLab.app/Contents/Resources/Publish").is_dir(), reason="Packaged /Applications/SpinLab.app not built")
def test_packaged_spinlab_app_bundle_publishes_without_source_tree(tmp_path: Path) -> None:
    app_publish_root = Path("/Applications/SpinLab.app/Contents/Resources/Publish")
    env, web, bare = _publish_fixture(tmp_path / "app-bundle-run")
    res = subprocess.run(
        [
            "/bin/bash",
            str(app_publish_root / "scripts" / "publish_web_library.sh"),
            "--library-root",
            env["SPINLAB_LIBRARY_ROOT"],
            "--web-repo",
            str(web),
        ],
        env={k: v for k, v in env.items() if k not in {"SPINLAB_LIBRARY_ROOT", "SPINLAB_WEB_LIBRARY_DIR"}},
        cwd=tmp_path,  # outside the source tree
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, res.stdout + res.stderr
    assert "Update SpinLab web snapshot" in _git("log", "--oneline", "-1", cwd=bare)
    assert (web / "public" / "data" / "library.json").is_file()
    assert (web / "public" / "data" / "new_sample_form.json").is_file()
