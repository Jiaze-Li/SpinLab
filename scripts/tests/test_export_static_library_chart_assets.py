from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EXPORT_SCRIPT = ROOT / "scripts" / "export_static_library.py"


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Tiny valid PNG signature + minimal bytes is enough for copy-based export.
    path.write_bytes(b"\x89PNG\r\n\x1a\nTEST")


def _setup_library_index(library_root: Path, sample_id: str = "S1") -> None:
    _write_json(
        library_root / "index" / "library_index.json",
        {
            "version": 1,
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
            "batches": [{"id": "B1", "displayName": "B1", "sampleKeys": [sample_id]}],
            "samples": [{"id": sample_id, "batchId": "B1"}],
            "metadataColumnOrder": [],
        },
    )


def _run_export(library_root: Path, output_dir: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "python3",
            str(EXPORT_SCRIPT),
            "--library-root",
            str(library_root),
            "--output-dir",
            str(output_dir),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def _read_report(output_dir: Path) -> dict:
    return json.loads((output_dir / "data" / "export_report.json").read_text(encoding="utf-8"))


def test_active_indexed_png_is_exported(tmp_path: Path) -> None:
    library_root = tmp_path / "library"
    output_dir = tmp_path / "out"
    _setup_library_index(library_root)

    active_rel = "samples/S1/charts/active.png"
    chart_ref = {
        "chartIdentityKey": "chart-active",
        "chartImagePath": active_rel,
        "manifestPath": "samples/S1/charts/active.manifest.json",
        "workflowID": "threeOmega",
        "generatedAt": "2026-01-01T00:00:00Z",
    }
    _write_json(library_root / "samples" / "S1" / "_spinlab" / "results_index.json", {"references": [chart_ref]})
    _write_json(
        library_root / "samples" / "S1" / "_spinlab" / "measurement_plot_index.json",
        {"entries": {"run1.dat": ["chart-active"]}},
    )
    _write_png(library_root / active_rel)

    result = _run_export(library_root, output_dir)
    assert result.returncode == 0, result.stderr + "\n" + result.stdout

    report = _read_report(output_dir)
    assets = report["assetStats"]["assets"]
    assert len(assets) == 1
    asset_url = assets[0]["url"]

    exported_asset_path = output_dir / asset_url
    assert exported_asset_path.exists()

    library_json = json.loads((output_dir / "data" / "library.json").read_text(encoding="utf-8"))
    assert library_json["sourceSummary"]["chartCount"] == 1


def test_orphan_png_is_not_exported(tmp_path: Path) -> None:
    library_root = tmp_path / "library"
    output_dir = tmp_path / "out"
    _setup_library_index(library_root)

    active_rel = "samples/S1/charts/active.png"
    orphan_rel = "samples/S1/charts/orphan.png"
    chart_ref = {
        "chartIdentityKey": "chart-active",
        "chartImagePath": active_rel,
        "manifestPath": "samples/S1/charts/active.manifest.json",
        "workflowID": "threeOmega",
        "generatedAt": "2026-01-01T00:00:00Z",
    }
    _write_json(library_root / "samples" / "S1" / "_spinlab" / "results_index.json", {"references": [chart_ref]})
    _write_json(
        library_root / "samples" / "S1" / "_spinlab" / "measurement_plot_index.json",
        {"entries": {"run1.dat": ["chart-active"]}},
    )
    _write_png(library_root / active_rel)
    _write_png(library_root / orphan_rel)

    result = _run_export(library_root, output_dir)
    assert result.returncode == 0, result.stderr + "\n" + result.stdout

    report = _read_report(output_dir)
    assets = report["assetStats"]["assets"]
    assert len(assets) == 1
    exported_source_files = {asset["source_file"] for asset in assets}
    assert "orphan.png" not in exported_source_files

    exported_assets_dir = output_dir / "assets"
    assert exported_assets_dir.exists()
    exported_names = {path.name for path in exported_assets_dir.iterdir() if path.is_file()}
    assert all("orphan" not in name for name in exported_names)


def test_missing_indexed_png_emits_warning_and_is_not_copied(tmp_path: Path) -> None:
    library_root = tmp_path / "library"
    output_dir = tmp_path / "out"
    _setup_library_index(library_root)

    missing_rel = "samples/S1/charts/missing.png"
    chart_ref = {
        "chartIdentityKey": "chart-missing",
        "chartImagePath": missing_rel,
        "manifestPath": "samples/S1/charts/missing.manifest.json",
        "workflowID": "threeOmega",
        "generatedAt": "2026-01-01T00:00:00Z",
    }
    _write_json(library_root / "samples" / "S1" / "_spinlab" / "results_index.json", {"references": [chart_ref]})
    _write_json(
        library_root / "samples" / "S1" / "_spinlab" / "measurement_plot_index.json",
        {"entries": {"run1.dat": ["chart-missing"]}},
    )

    result = _run_export(library_root, output_dir)
    assert result.returncode == 0, result.stderr + "\n" + result.stdout

    report = _read_report(output_dir)
    warning_codes = [w.get("code") for w in report.get("warnings", [])]
    assert "missing_active_chart_png" in warning_codes

    assets = report["assetStats"]["assets"]
    assert assets == []
    assert report["assetStats"]["chartCount"] == 0

    exported_assets_dir = output_dir / "assets"
    if exported_assets_dir.exists():
        assert list(exported_assets_dir.iterdir()) == []
