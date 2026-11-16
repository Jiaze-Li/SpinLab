"""Automated consistency checks for the Phone Write-Back Contract (`docs/phone_writeback_contract.md`).

Verifies field parity across:
1. `Sources/SpinLabApp/config/new_sample_form_schema.json`
2. `Sources/SpinLabApp/Library/NewSampleFields.swift`
3. `Resources/WebLibraryTemplate/new-sample.js`
4. `Resources/WebLibraryTemplate/` note API usage (`GET/PUT /api/note`)
5. `docs/phone_writeback_contract.md`

Includes negative fixtures that intentionally introduce field drift and assert that the checker fails.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "Sources" / "SpinLabApp" / "config" / "new_sample_form_schema.json"
SWIFT_FIELDS_PATH = ROOT / "Sources" / "SpinLabApp" / "Library" / "NewSampleFields.swift"
NEW_SAMPLE_JS_PATH = ROOT / "Resources" / "WebLibraryTemplate" / "new-sample.js"
TEMPLATE_DIR = ROOT / "Resources" / "WebLibraryTemplate"
CONTRACT_DOC_PATH = ROOT / "docs" / "phone_writeback_contract.md"

FIXED_BASE_FIELDS = {
    "date",
    "lab",
    "growthMaterial",
    "batch",
    "substrateTreatment",
    "substrateMaterial",
    "substrateOrientation",
    "extraSubstrates",
    "hasAttenuator",
    "purpose",
    "note",
    "rheed",
}


def parse_schema_fields(schema: dict[str, Any]) -> dict[str, set[str]]:
    required = {entry["key"] for entry in schema.get("required", []) if isinstance(entry, dict) and "key" in entry}
    numbers = {entry["key"] for entry in schema.get("numberFields", []) if isinstance(entry, dict) and "key" in entry}
    rheed = {entry["key"] for entry in schema.get("rheedFields", []) if isinstance(entry, dict) and "key" in entry}
    return {
        "required": required,
        "numberFields": numbers,
        "rheedFields": rheed,
    }


def parse_swift_new_sample_fields(swift_source: str) -> dict[str, set[str]]:
    rheed_match = re.search(r"struct\s+Rheed\s*:[^{]+\{(.*?)\}", swift_source, re.S)
    rheed_vars = set(re.findall(r"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*Double\?", rheed_match.group(1))) if rheed_match else set()

    # Extract top-level stored properties of NewSampleFields between `struct Substrate` end and `func number(forKey`
    body_start = swift_source.find("struct Substrate")
    body_end = swift_source.find("func number(forKey")
    body_slice = swift_source[body_start:body_end] if body_start != -1 and body_end != -1 else swift_source
    # Remove nested Substrate struct block
    body_slice = re.sub(r"struct\s+Substrate\s*:[^{]+\{.*?\n\s*\}", "", body_slice, flags=re.S)
    top_vars = set(re.findall(r"^\s*var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:", body_slice, re.M))

    number_switch_match = re.search(r"func\s+number\(forKey\s+key:\s*String\)\s*->\s*Double\?\s*\{(.*?)\n\s*\}", swift_source, re.S)
    number_cases = set(re.findall(r'case\s+"([^"]+)"\s*:', number_switch_match.group(1))) if number_switch_match else set()

    rheed_switch_match = re.search(r"func\s+rheedValue\(forKey\s+key:\s*String\)\s*->\s*Double\?\s*\{(.*?)\n\s*\}", swift_source, re.S)
    rheed_cases = set(re.findall(r'case\s+"([^"]+)"\s*:', rheed_switch_match.group(1))) if rheed_switch_match else set()

    decode_match = re.search(r"init\(from\s+decoder:\s*Decoder\)\s*throws\s*\{(.*?)\n\s*\}", swift_source, re.S)
    decoded_keys = (
        set(re.findall(r"(?:forKey:\s*|text\()\.([A-Za-z_][A-Za-z0-9_]*)\)", decode_match.group(1)))
        if decode_match
        else set()
    )

    return {
        "topVars": top_vars,
        "numberCases": number_cases,
        "rheedVars": rheed_vars,
        "rheedCases": rheed_cases,
        "decodedKeys": decoded_keys,
    }


def parse_js_new_sample_fields(js_source: str) -> dict[str, Any]:
    collect_match = re.search(r"function\s+collectFields\(\)\s*\{(.*?)\n\}", js_source, re.S)
    collect_body = collect_match.group(1) if collect_match else ""
    fields_obj_match = re.search(r"const\s+fields\s*=\s*\{(.*?)\};", collect_body, re.S)
    literal_keys = set(re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", fields_obj_match.group(1), re.M)) if fields_obj_match else set()
    if "fields.extraSubstrates" in collect_body:
        literal_keys.add("extraSubstrates")

    uses_schema_required = "state.form.required" in collect_body
    uses_schema_numbers = "state.form.numberFields" in collect_body and "fields[field.key]" in collect_body
    uses_schema_rheed = "state.form.rheedFields" in collect_body and "fields.rheed[field.key]" in collect_body
    posts_to_api_samples = "./api/samples" in js_source and "submission_id" in js_source

    return {
        "baseKeys": literal_keys,
        "usesSchemaRequired": uses_schema_required,
        "usesSchemaNumbers": uses_schema_numbers,
        "usesSchemaRheed": uses_schema_rheed,
        "postsToApiSamples": posts_to_api_samples,
    }


def check_phone_writeback_consistency(
    schema: dict[str, Any],
    swift_source: str,
    js_source: str,
    contract_doc: str,
) -> list[str]:
    problems: list[str] = []
    s = parse_schema_fields(schema)
    sw = parse_swift_new_sample_fields(swift_source)
    js = parse_js_new_sample_fields(js_source)

    expected_top_vars = FIXED_BASE_FIELDS | s["numberFields"]
    if sw["topVars"] != expected_top_vars:
        missing = sorted(expected_top_vars - sw["topVars"])
        extra = sorted(sw["topVars"] - expected_top_vars)
        problems.append(f"NewSampleFields.swift top-level properties mismatch (missing={missing}, extra={extra})")

    if sw["numberCases"] != s["numberFields"]:
        missing = sorted(s["numberFields"] - sw["numberCases"])
        extra = sorted(sw["numberCases"] - s["numberFields"])
        problems.append(f"NewSampleFields.number(forKey:) cases mismatch schema.numberFields (missing={missing}, extra={extra})")

    if sw["rheedVars"] != s["rheedFields"]:
        missing = sorted(s["rheedFields"] - sw["rheedVars"])
        extra = sorted(sw["rheedVars"] - s["rheedFields"])
        problems.append(f"NewSampleFields.Rheed properties mismatch schema.rheedFields (missing={missing}, extra={extra})")

    if sw["rheedCases"] != s["rheedFields"]:
        missing = sorted(s["rheedFields"] - sw["rheedCases"])
        extra = sorted(sw["rheedCases"] - s["rheedFields"])
        problems.append(f"NewSampleFields.rheedValue(forKey:) cases mismatch schema.rheedFields (missing={missing}, extra={extra})")

    if sw["decodedKeys"] != expected_top_vars:
        missing = sorted(expected_top_vars - sw["decodedKeys"])
        extra = sorted(sw["decodedKeys"] - expected_top_vars)
        problems.append(f"NewSampleFields.init(from:) decoded keys mismatch (missing={missing}, extra={extra})")

    if not s["required"].issubset(FIXED_BASE_FIELDS):
        problems.append(f"schema.required contains keys not in base fields: {sorted(s['required'] - FIXED_BASE_FIELDS)}")

    if js["baseKeys"] != FIXED_BASE_FIELDS:
        missing = sorted(FIXED_BASE_FIELDS - js["baseKeys"])
        extra = sorted(js["baseKeys"] - FIXED_BASE_FIELDS)
        problems.append(f"new-sample.js collectFields() base keys mismatch (missing={missing}, extra={extra})")

    if not js["usesSchemaRequired"]:
        problems.append("new-sample.js collectFields() does not validate state.form.required")
    if not js["usesSchemaNumbers"]:
        problems.append("new-sample.js collectFields() does not populate state.form.numberFields")
    if not js["usesSchemaRheed"]:
        problems.append("new-sample.js collectFields() does not populate state.form.rheedFields")
    if not js["postsToApiSamples"]:
        problems.append("new-sample.js does not POST { submission_id, fields } to ./api/samples")

    all_keys = FIXED_BASE_FIELDS | s["numberFields"] | s["rheedFields"]
    for key in sorted(all_keys):
        if f"`{key}`" not in contract_doc:
            problems.append(f"docs/phone_writeback_contract.md is missing documented field `{key}`")

    return problems


def test_phone_writeback_contract_is_consistent_across_all_layers() -> None:
    assert CONTRACT_DOC_PATH.is_file(), "docs/phone_writeback_contract.md must exist"
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    swift_source = SWIFT_FIELDS_PATH.read_text(encoding="utf-8")
    js_source = NEW_SAMPLE_JS_PATH.read_text(encoding="utf-8")
    contract_doc = CONTRACT_DOC_PATH.read_text(encoding="utf-8")

    problems = check_phone_writeback_consistency(schema, swift_source, js_source, contract_doc)
    assert problems == []


def test_note_writeback_contract_in_web_templates() -> None:
    js_texts = "\n".join(p.read_text(encoding="utf-8") for p in sorted(TEMPLATE_DIR.glob("*.js")))
    assert "./api/note?sample_id=" in js_texts
    assert 'fetch("./api/note"' in js_texts
    assert "sample_id" in js_texts and "note_text" in js_texts


def test_negative_fixture_fails_when_schema_swift_or_js_fields_drift() -> None:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    swift_source = SWIFT_FIELDS_PATH.read_text(encoding="utf-8")
    js_source = NEW_SAMPLE_JS_PATH.read_text(encoding="utf-8")
    contract_doc = CONTRACT_DOC_PATH.read_text(encoding="utf-8")

    # 1. Drift in schema.numberFields (new number field added in JSON but not in Swift)
    drifted_schema = json.loads(json.dumps(schema))
    drifted_schema["numberFields"].append({"key": "annealTime", "tag": "退火时间", "label": "Anneal time", "unit": "min"})
    problems_schema = check_phone_writeback_consistency(drifted_schema, swift_source, js_source, contract_doc)
    assert any("annealTime" in p for p in problems_schema)

    # 2. Drift in Swift (a field renamed in NewSampleFields.swift)
    drifted_swift = swift_source.replace("var hasAttenuator: Bool", "var attenuatorEnabled: Bool")
    problems_swift = check_phone_writeback_consistency(schema, drifted_swift, js_source, contract_doc)
    assert any("hasAttenuator" in p or "attenuatorEnabled" in p for p in problems_swift)

    # 3. Drift in new-sample.js (a base field omitted from collectFields)
    drifted_js = js_source.replace("substrateTreatment: first.treatment,", "treatmentName: first.treatment,")
    problems_js = check_phone_writeback_consistency(schema, swift_source, drifted_js, contract_doc)
    assert any("substrateTreatment" in p or "treatmentName" in p for p in problems_js)

    # 4. Drift in contract documentation (a field missing from docs/phone_writeback_contract.md)
    drifted_doc = contract_doc.replace("`laserOutputEnergy`", "`removedField`")
    problems_doc = check_phone_writeback_consistency(schema, swift_source, js_source, drifted_doc)
    assert any("laserOutputEnergy" in p for p in problems_doc)
