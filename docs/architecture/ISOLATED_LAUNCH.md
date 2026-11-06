# Isolated launch mode (GUI test isolation)

Status: active. Owner: `IsolatedLaunch` (`Sources/SpinLabApp/Storage/IsolatedLaunch.swift`).

Changing `HOME`, the bundle identifier or copying the `.app` does **not** isolate SpinLab:
Application Support resolves through the user record. Use this explicit contract instead.

## Launching

```
SpinLabApp --spinlab-isolated-config <dir> --spinlab-isolated-library <dir> [--spinlab-isolated-selftest]
```

or `SPINLAB_ISOLATED_CONFIG_DIR` / `SPINLAB_ISOLATED_LIBRARY_ROOT` (an argument and an
environment value that disagree are refused). Giving any of these flags makes the launch an
isolated test launch, and then **both** paths are mandatory.

`--spinlab-isolated-selftest` runs the real startup path headlessly (no window), prints a JSON
report and exits 0.

## Contract (fail-closed, checked before any live service is built)

- Both directories must be absolute, normalized, existing, not symbolic links, and contain the
  marker file `.spinlab-isolated-test-root` whose body is `spinlab-isolated-test-root-v1`.
  The harness creates the marker deliberately; a real Library never has it.
- No symbolic link inside either root may point outside it; roots with more than 50 000 entries
  are refused as "not a synthetic fixture".
- Neither root may equal, contain or sit inside `~/Library/Application Support/SpinLab` or
  `.../com.spinlab.app` (user-record and `FileManager` homes); config and Library must not overlap.
- Stored `library_settings.json` / `rules_book.json` in the config directory must not point outside
  the isolated roots (the Library Root is forced to the isolated one; bookmarks are dropped).
- A refusal prints the reason and exits with status 78 without touching production data.

Settings, interaction snapshot, logs, pending imports, projects, archive scan and registry state
live in the config directory; the Library lives in the isolated Library Root. The environment/cwd
registry fallback is disabled. Changing the Library Root, backup path or Rules Book at runtime is
limited to the isolated folders.

Ordinary launches (no flags) are unchanged.

## Verifying a run

Hash the production files and the isolated fixtures before and after. For belt-and-braces on a
developer machine, run the process under `sandbox-exec` with a profile that kills it on any
read/write of the production folders.
