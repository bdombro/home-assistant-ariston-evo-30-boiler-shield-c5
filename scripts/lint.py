"""Sanity checks used by `just lint`: YAML parses, CSV rows look right, writes stay on the allow-list."""
import csv
import pathlib
import sys

import yaml

root = pathlib.Path(__file__).resolve().parent.parent
ALLOWED_WRITES = {"set_ch_setpoint", "set_heating_enabled", "set_dhw_enabled"}
errors = []


class Loader(yaml.SafeLoader):
    pass


Loader.add_constructor("!include_dir_named", lambda loader, node: None)

for path in sorted((root / "home-assistant").rglob("*.yaml")):
    try:
        yaml.load(path.read_text(encoding="utf-8"), Loader)
    except yaml.YAMLError as exc:
        errors.append(f"{path.relative_to(root)}: {exc}")

seen = set()
for n, line in enumerate((root / "ebusd" / "ariston.csv").read_text(encoding="utf-8").splitlines(), 1):
    if not line or line.startswith("#"):
        continue
    row = next(csv.reader([line]))
    if row[0] not in {"r", "w", "u", "b", "g"}:
        errors.append(f"ariston.csv:{n}: unknown message type {row[0]!r}")
        continue
    if len(row) < 8:
        errors.append(f"ariston.csv:{n}: too few columns ({len(row)})")
    key = (row[0], row[1], row[2])
    if key in seen:
        errors.append(f"ariston.csv:{n}: duplicate {key}")
    seen.add(key)
    if row[0] == "w" and row[2] not in ALLOWED_WRITES:
        errors.append(f"ariston.csv:{n}: write {row[2]!r} is not on the allow-list")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"ok: {len(seen)} CSV definitions, YAML parses, writes limited to {sorted(ALLOWED_WRITES)}")
