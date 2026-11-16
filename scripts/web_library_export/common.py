from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def ensure_inside(base_dir: Path, candidate: Path) -> None:
    base = base_dir.resolve()
    target = candidate.resolve()
    if base == target:
        return
    try:
        target.relative_to(base)
    except ValueError as exc:
        raise RuntimeError(f"Refusing to write outside output dir: {target}") from exc


def safe_slug(value: str) -> str:
    slug = [ch if ch.isalnum() or ch in {"-", "_"} else "_" for ch in value]
    cleaned = "".join(slug).strip("_")
    return cleaned or "item"


def short_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


def natural_key(value: str) -> list[Any]:
    # Each element is tagged (0, str) or (1, int) so keys with a different
    # digit/letter shape at the same position (e.g. "1st_..." vs "AHE_...")
    # compare via the tag instead of raising TypeError on int-vs-str.
    parts = re.split(r"(\d+)", value)
    key: list[Any] = []
    for part in parts:
        if not part:
            continue
        if part.isdigit():
            key.append((1, int(part)))
        else:
            key.append((0, part.casefold()))
    return key


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def unique_names(values: Iterable[Any]) -> list[str]:
    seen: set[str] = set()
    names: list[str] = []
    for value in values:
        if isinstance(value, str) and value and value not in seen:
            seen.add(value)
            names.append(value)
    return names


def gather_string_list(values: Iterable[Any]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for value in values:
        text = str(value)
        if text in seen:
            continue
        seen.add(text)
        output.append(text)
    return sorted(output)
