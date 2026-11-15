from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import export_static_library as export  # noqa: E402


def _rules_book(tmp_path: Path, treatments: list[dict]) -> Path:
    (tmp_path / "library_import_rules.json").write_text(
        json.dumps({"registry": {"labOptions": ["E3-L4"], "growthMaterialOptions": ["SRO"]}}), encoding="utf-8"
    )
    (tmp_path / "sample_identification.json").write_text(
        json.dumps(
            {
                "sampleId": {
                    "matches": [
                        {"type": "starts-with", "value": "pn"},
                        {"type": "regex", "value": "^X$"},
                        {"type": "starts-with", "value": "PT"},
                        {"type": "starts-with", "value": "PN"},
                    ]
                },
                "substrate": {
                    "treatments": treatments,
                    "materials": [{"displayName": "STO"}],
                    "orientations": [{"displayName": "001"}],
                }
            }
        ),
        encoding="utf-8",
    )
    return tmp_path


def test_default_treatment_is_the_original_entry(tmp_path: Path) -> None:
    book = _rules_book(
        tmp_path,
        [
            {"displayName": "HF", "matches": [{"type": "contains", "value": "hf"}]},
            {"displayName": "b", "matches": [{"type": "equals", "value": "b"}]},
            {"displayName": "o", "matches": [{"type": "equals", "value": "o"}, {"type": "contains", "value": "origin"}]},
        ],
    )
    form = export.build_new_sample_form(book)
    assert form["substrate"]["treatments"] == ["HF", "b", "o"]
    assert form["substrate"]["defaultTreatment"] == "o"


def test_default_treatment_found_through_a_match_value(tmp_path: Path) -> None:
    book = _rules_book(
        tmp_path,
        [
            {"displayName": "HF", "matches": []},
            {"displayName": "Original", "matches": [{"type": "equals", "value": "O"}]},
        ],
    )
    assert export.build_new_sample_form(book)["substrate"]["defaultTreatment"] == "Original"


def test_default_treatment_falls_back_to_o(tmp_path: Path) -> None:
    book = _rules_book(tmp_path, [{"displayName": "HF", "matches": []}])
    assert export.build_new_sample_form(book)["substrate"]["defaultTreatment"] == "o"


@pytest.mark.parametrize("token", ["o", " O ", "(o)", "o_"])
def test_token_normalisation_matches_the_app(token: str) -> None:
    assert export._normalize_substrate_token(token) == "O"


def test_form_carries_the_shared_field_definition(tmp_path: Path) -> None:
    book = _rules_book(tmp_path, [{"displayName": "o", "matches": []}])
    form = export.build_new_sample_form(book)
    schema = json.loads(export.NEW_SAMPLE_SCHEMA_PATH.read_text(encoding="utf-8"))
    assert form["numberFields"] == schema["numberFields"]
    assert form["rheedFields"] == schema["rheedFields"]
    assert form["required"] == schema["required"]
    assert "frequency" in {f["key"] for f in form["numberFields"]}


def test_export_records_when_it_ran_for_the_sync_time_shown_on_the_pages(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    root = tmp_path / "library"
    (root / "index").mkdir(parents=True)
    (root / "index" / "library_index.json").write_text(
        json.dumps({"version": 1, "batches": [], "samples": []}), encoding="utf-8"
    )
    book_dir = tmp_path / "book"
    book_dir.mkdir()
    book = _rules_book(book_dir, [{"displayName": "o", "matches": [{"type": "equals", "value": "o"}]}])
    out = tmp_path / "out"
    monkeypatch.setattr(
        sys, "argv",
        ["export", "--library-root", str(root), "--output-dir", str(out), "--rules-book-dir", str(book)],
    )
    assert export.main() == 0
    form = json.loads((out / "data" / "new_sample_form.json").read_text(encoding="utf-8"))
    report = json.loads((out / "data" / "export_report.json").read_text(encoding="utf-8"))
    assert "syncedAt" not in form
    assert report["exportedAt"]
    assert 'id="sync-info"' in (out / "new-sample.html").read_text(encoding="utf-8")


def test_form_carries_the_batch_prefixes_from_the_rules_book(tmp_path: Path) -> None:
    book = _rules_book(tmp_path, [{"displayName": "o", "matches": [{"type": "equals", "value": "o"}]}])
    assert export.build_new_sample_form(book)["batchPrefixes"] == ["PN", "PT"]
