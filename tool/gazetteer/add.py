#!/usr/bin/env python3
"""Add a curated location to the Benue gazetteer (the practical update tool).

Interactive (prompts for everything):
  python tool/gazetteer/add.py

Non-interactive:
  python tool/gazetteer/add.py --name "Naval Base Kanshio" --town Makurdi \
      --lat 7.6850 --lng 8.5361 --aliases "Navy Base|Naval HQ" \
      --category landmark --notes "draft; verify coords"

Options:
  --dry-run    print the CSV row that would be written, change nothing
  --force      add even if a same-named entry already exists
  --verified   mark the row verified=true (only after a human checked coords)
  --no-build   write the CSV but skip the build.py rebuild

After a normal run the pipeline (build.py) merges the row with provider
records, regenerates out/ + the app asset, and you can inspect the result
with `view.py <name>` or `view.py --map`.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CURATED = ROOT / "curated"
DATA = ROOT / "out" / "benue_gazetteer.json"
TOWNS = ROOT / "towns.json"
FIELDS = ["id", "name", "aliases", "locality", "lga", "state", "category",
          "lat", "lng", "precision", "verified", "notes"]

# Same envelope build.py validates against (Benue State).
LAT_MIN, LAT_MAX = 6.2, 8.2
LNG_MIN, LNG_MAX = 7.7, 9.9


def norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def ask(prompt: str, default: str = "", required: bool = True) -> str:
    if not sys.stdin.isatty():
        # Piped/non-interactive: optional fields fall back to their default,
        # required ones must be passed as flags.
        if default or not required:
            return default
        sys.exit(f"Missing required value: {prompt!r} - pass it as a flag (see --help).")
    try:
        suffix = f" [{default}]" if default else ""
        value = input(f"{prompt}{suffix}: ").strip()
    except EOFError:
        sys.exit("\nNon-interactive shell - pass the values as flags (see --help).")
    return value or default


def existing_keys() -> dict[tuple[str, str], dict]:
    """(town, normalised name/alias key) -> entry, from curated CSVs + output.

    Scoped by town on purpose: settlements share names across LGAs
    (e.g. Hange exists in Katsina-Ala - a Makurdi Hange must not collide).
    """
    keys: dict[tuple[str, str], dict] = {}

    def put(locality: str, key: str, entry: dict) -> None:
        keys.setdefault((locality.lower(), key), entry)

    for path in sorted(CURATED.glob("*.csv")):
        with path.open(encoding="utf-8", newline="") as fh:
            for row in csv.DictReader(fh):
                if row.get("name"):
                    entry = {"name": row["name"], "src": path.name}
                    put(row.get("locality", ""), norm(row["name"]), entry)
                    for a in (row.get("aliases") or "").split("|"):
                        if a.strip():
                            put(row.get("locality", ""), norm(a), entry)
    if DATA.exists():
        for e in json.loads(DATA.read_text(encoding="utf-8"))["entries"]:
            for cand in [e["name"], *e.get("aliases", [])]:
                put(e.get("locality", ""), norm(cand), e)
    return keys


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name")
    ap.add_argument("--town", help="Makurdi, Gboko, Otukpo, Katsina-Ala or Vandeikya")
    ap.add_argument("--lat", type=float)
    ap.add_argument("--lng", type=float)
    ap.add_argument("--aliases", help="pipe-separated, e.g. 'NAF Base|TAC Makurdi'")
    ap.add_argument("--category", default="")
    ap.add_argument("--precision", default="approximate",
                    choices=["approximate", "exact"])
    ap.add_argument("--notes", default="")
    ap.add_argument("--verified", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-build", action="store_true")
    args = ap.parse_args()

    towns = json.loads(TOWNS.read_text(encoding="utf-8"))["towns"]

    name = args.name or ask("Location name")
    town_name = args.town or ask("Town", "Makurdi")
    town = next((t for t in towns if t["name"].lower() == town_name.lower()), None)
    if town is None:
        sys.exit(f"Unknown town '{town_name}'. Known: "
                 f"{', '.join(t['name'] for t in towns)}")

    lat = args.lat if args.lat is not None else float(ask("Latitude"))
    lng = args.lng if args.lng is not None else float(ask("Longitude"))
    if not (LAT_MIN <= lat <= LAT_MAX and LNG_MIN <= lng <= LNG_MAX):
        sys.exit(f"({lat}, {lng}) is outside the Benue envelope "
                 f"lat {LAT_MIN}-{LAT_MAX}, lng {LNG_MIN}-{LNG_MAX}.")
    dlat, dlng = abs(lat - town["lat"]), abs(lng - town["lng"])
    if max(dlat, dlng) > town["radius_deg"] * 2:
        print(f"  note: ({lat}, {lng}) is far from {town['name']} centre - double-check.")

    aliases = args.aliases if args.aliases is not None else ask(
        "Aliases (pipe-separated, optional)", required=False)
    aliases = "|".join(a.strip() for a in re.split(r"[|;]", aliases) if a.strip())
    category = args.category or ask("Category (e.g. district, market, landmark)", "place")
    notes = args.notes or ask("Notes (optional)",
                              f"Added {date.today().isoformat()}; coords approximate")

    row = {
        "id": f"ng-benue-{slug(town['name'])}-{slug(name)}",
        "name": name,
        "aliases": aliases,
        "locality": town["name"],
        "lga": town["lga"],
        "state": "Benue",
        "category": category,
        "lat": f"{lat:.6f}".rstrip("0").rstrip("."),
        "lng": f"{lng:.6f}".rstrip("0").rstrip("."),
        "precision": args.precision,
        "verified": "true" if args.verified else "false",
        "notes": notes,
    }

    keys = existing_keys()
    town_l = town["name"].lower()
    lookups = [norm(name)] + [norm(a) for a in aliases.split("|") if a]
    hits = {k: keys[(town_l, k)] for k in lookups if (town_l, k) in keys}
    if hits and not args.force:
        for _, e in hits.items():
            print(f"Already exists: {e.get('name')} ({e.get('src') or e.get('id')})")
        sys.exit("Duplicate suppressed - rerun with --force to add anyway.")

    if args.dry_run:
        import io
        buf = io.StringIO()
        csv.DictWriter(buf, fieldnames=FIELDS).writerow(row)
        print("would append to", CURATED / f"{slug(town['name'])}.csv")
        print(buf.getvalue().strip())
        return 0

    csv_path = CURATED / f"{slug(town['name'])}.csv"
    new_file = not csv_path.exists()
    with csv_path.open("a", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=FIELDS)
        if new_file:
            writer.writeheader()
        writer.writerow(row)
    print(f"appended {row['id']} -> {csv_path}")

    if args.no_build:
        print("skipped rebuild (--no-build); run `python tool/gazetteer/build.py` later.")
        return 0

    result = subprocess.run([sys.executable, str(ROOT / "build.py")])
    if result.returncode != 0:
        sys.exit(result.returncode)
    if DATA.exists():
        total = json.loads(DATA.read_text(encoding="utf-8"))["entry_count"]
        print(f"done - gazetteer now has {total} entries.")
    print("Next: check the pin with `view.py --map` or `view.py <name>`, "
          "then set verified=true in the CSV and rebuild once coords are confirmed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
