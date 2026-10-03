#!/usr/bin/env python3
"""Benue gazetteer build pipeline.

Seeds the gazetteer from redistributable open sources, merges the hand-curated
CSVs, deduplicates, validates and emits the app asset plus the backend
handoff pack.

Sources (all redistributable, see SOURCES.md emitted next to the output):
  * curated/*.csv      - hand written, verified by humans
  * GeoNames NG dump   - CC BY 4.0   (villages / localities / admin / rivers)
  * Wikidata           - CC0 1.0     (items with coordinates in Benue)
  * Overture Places    - CDLA-P2.0 / Apache-2.0  (--overture, POIs)

Usage:
  python tool/gazetteer/build.py                 # curated + geonames + wikidata
  python tool/gazetteer/build.py --skip-network  # curated only
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import json
import math
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
CACHE = ROOT / ".cache"
OUT = ROOT / "out"
ASSET = ROOT.parent.parent / "assets" / "data" / "benue_gazetteer.json"
SCHEMA_VERSION = 1

BENUE_WD_ID = "Q429908"  # Benue State

GEONAMES_URL = "https://download.geonames.org/export/dump/NG.zip"
GEONAMES_CAT = {
    "PPL": "village", "PPLA": "town", "PPLA2": "town", "PPLA3": "town",
    "PPLA4": "town", "PPLL": "village", "PPLX": "district", "PPLF": "village",
    "STM": "river", "STMH": "river", "STMQ": "river", "AIRP": "airport",
    "AIRH": "airport", "UNIV": "university", "RESF": "reserve",
    "ADM2": "lga_seat", "ADM3": "ward_seat", "HLL": "hill", "MT": "hill",
    "PCL": "place", "PCLD": "place", "PCLF": "place",
}
WIKIDATA_CAT = re.compile(
    r"school|college|university|hospital|clinic|market|bank|"
    r"church|mosque|place of worship|stadium|airport|hotel|"
    r"village|town|city|locality|settlement|government|"
    r"station|park|bridge|river|hill|mountain|rock",
    re.I,
)


# ---------------------------------------------------------------- helpers ---
def log(msg: str) -> None:
    print(msg, flush=True)


def slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s or "unnamed"


def norm_name(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def haversine_km(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = p2 - p1
    dl = math.radians(b_lng - a_lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def http_get(url: str, timeout: int = 90, retries: int = 3) -> bytes:
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "vtrides-gazetteer/1.0"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except Exception as exc:  # noqa: BLE001 - report and retry
            last = exc
            wait = 20 * (attempt + 1)
            log(f"    retry in {wait}s ({exc})")
            time.sleep(wait)
    raise RuntimeError(f"GET failed: {url}: {last}")


def load_towns() -> list[dict]:
    data = json.loads((ROOT / "towns.json").read_text(encoding="utf-8"))
    for t in data["towns"]:
        t["north"] = t["lat"] + t["radius_deg"]
        t["south"] = t["lat"] - t["radius_deg"]
        t["east"] = t["lng"] + t["radius_deg"]
        t["west"] = t["lng"] - t["radius_deg"]
    return data["towns"]


def town_for(lat: float, lng: float, towns: list[dict]) -> str | None:
    for t in towns:
        if t["south"] <= lat <= t["north"] and t["west"] <= lng <= t["east"]:
            return t["name"]
    return None


def entry(
    eid: str,
    name: str,
    lat: float,
    lng: float,
    *,
    aliases: list[str] | None = None,
    locality: str = "",
    category: str = "place",
    precision: str = "exact",
    verified: bool = False,
    sources: list[str] = (),
    licenses: list[str] = (),
    notes: str = "",
) -> dict:
    return {
        "id": eid,
        "name": name,
        "aliases": aliases or [],
        "locality": locality,
        "lga": locality,
        "state": "Benue",
        "category": category,
        "lat": round(lat, 6),
        "lng": round(lng, 6),
        "precision": precision,
        "verified": verified,
        "sources": list(sources),
        "licenses": list(licenses),
        "notes": notes,
    }


# ---------------------------------------------------------------- curated ---
def load_curated(towns: list[dict]) -> list[dict]:
    out: list[dict] = []
    for path in sorted((ROOT / "curated").glob("*.csv")):
        with path.open(encoding="utf-8", newline="") as fh:
            for row in csv.DictReader(fh):
                if not row.get("id") or not row.get("name"):
                    continue
                aliases = [a.strip() for a in (row.get("aliases") or "").split("|") if a.strip()]
                lat, lng = float(row["lat"]), float(row["lng"])
                loc = row.get("locality") or ""
                out.append(
                    entry(
                        row["id"].strip(),
                        row["name"].strip(),
                        lat,
                        lng,
                        aliases=aliases,
                        locality=loc,
                        category=(row.get("category") or "place").strip(),
                        precision=(row.get("precision") or "exact").strip(),
                        verified=(row.get("verified", "false").strip().lower() == "true"),
                        sources=["curated"],
                        licenses=["project-owned"],
                        notes=(row.get("notes") or "").strip(),
                    )
                )
                if not loc and town_for(lat, lng, towns):
                    out[-1]["locality"] = town_for(lat, lng, towns)
        log(f"  curated: {path.name} ({path.stat().st_size} bytes)")
    return out


# ------------------------------------------------------------- geonames -----
def fetch_geonames(towns: list[dict]) -> list[dict]:
    CACHE.mkdir(exist_ok=True)
    zip_path = CACHE / "NG.zip"
    if not zip_path.exists():
        log(f"  downloading {GEONAMES_URL}")
        zip_path.write_bytes(http_get(GEONAMES_URL, timeout=180))
    out: list[dict] = []
    with zipfile.ZipFile(zip_path) as zf:
        with zf.open("NG.txt") as fh:
            for raw in io.TextIOWrapper(fh, encoding="utf-8"):
                p = raw.rstrip("\n").split("\t")
                if len(p) < 15:
                    continue
                if p[8] != "NG":
                    continue
                name, alt, lat, lng = p[1], p[3], float(p[4]), float(p[5])
                fclass, fcode = p[6], p[7]
                loc = town_for(lat, lng, towns)
                if not loc:
                    continue
                cat = GEONAMES_CAT.get(fcode)
                if cat is None:
                    continue
                if fclass not in ("P", "H", "A", "S", "T", "L"):
                    continue
                aliases = [a for a in alt.split(",") if a and a != name][:5]
                out.append(
                    entry(
                        f"gn-{slug(loc)}-{slug(name)}-{fcode.lower()}-{p[0]}",
                        name,
                        lat,
                        lng,
                        aliases=aliases,
                        locality=loc,
                        category=cat,
                        precision="exact",
                        verified=False,
                        sources=["geonames"],
                        licenses=["CC-BY-4.0"],
                        notes=f"GeoNames feature {fclass}.{fcode}",
                    )
                )
    log(f"  geonames: {len(out)} features in town boxes")
    return out


# -------------------------------------------------------------- wikidata ----
def fetch_wikidata(towns: list[dict]) -> list[dict]:
    query = f"""
SELECT ?item ?itemLabel ?coord ?typeLabel WHERE {{
  ?item wdt:P625 ?coord .
  ?item wdt:P131+ wd:{BENUE_WD_ID} .
  OPTIONAL {{ ?item wdt:P31 ?type . }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""
    cache = CACHE / "wikidata_benue.json"
    if cache.exists():
        raw = cache.read_bytes()
    else:
        url = (
            "https://query.wikidata.org/sparql?format=json&query="
            + urllib.parse.quote(query)
        )
        raw = http_get(url, timeout=180, retries=4)
        cache.write_bytes(raw)
        time.sleep(2)
    data = json.loads(raw)
    out: list[dict] = []
    for b in data["results"]["bindings"]:
        m = re.search(r"Point\((-?[\d.]+) (-?[\d.]+)\)", b["coord"]["value"])
        if not m:
            continue
        lng, lat = float(m.group(1)), float(m.group(2))
        loc = town_for(lat, lng, towns)
        if not loc:
            continue
        label = b.get("itemLabel", {}).get("value", "")
        if not label or label.startswith("Q"):
            continue
        type_label = b.get("typeLabel", {}).get("value", "").lower()
        cat_match = WIKIDATA_CAT.search(type_label)
        category = slug(cat_match.group(0)) if cat_match else "place"
        wd_id = b["item"]["value"].rsplit("/", 1)[-1]
        out.append(
            entry(
                f"wd-{wd_id}",
                label,
                lat,
                lng,
                locality=loc,
                category=category,
                precision="exact",
                verified=False,
                sources=["wikidata"],
                notes=f"Wikidata {wd_id}; instance-of: {type_label or 'unknown'}",
            )
        )
    log(f"  wikidata: {len(out)} items in town boxes")
    return out


# -------------------------------------------------------------- overture ----
OVERTURE_BASE = "https://overturemaps-us-west-2.s3.us-west-2.amazonaws.com"


def _overture_latest_release() -> str:
    xml = http_get(f"{OVERTURE_BASE}/?list-type=2&prefix=release/&delimiter=/",
                   timeout=60).decode()
    return sorted(re.findall(r"<Prefix>release/([^<]+)/</Prefix>", xml))[-1]


def _rg_hits(md, rg: int, bbox_cols: dict, towns: list[dict]) -> bool:
    xs: list[tuple[float, float]] = []
    ys: list[tuple[float, float]] = []
    for i, path in bbox_cols.items():
        st = md.row_group(rg).column(i).statistics
        if st is None or st.min is None:
            return True  # no stats: assume candidate
        (xs if path.endswith(("xmin", "xmax")) else ys).append((st.min, st.max))
    for lo, hi in xs:
        if all(hi < t["west"] or lo > t["east"] for t in towns):
            return False
    for lo, hi in ys:
        if all(hi < t["south"] or lo > t["north"] for t in towns):
            return False
    return True


def fetch_overture(towns: list[dict], refresh: bool = False) -> list[dict]:
    """Extract POIs inside the town boxes from the Overture places theme.

    Foursquare-sourced records are dropped so the whole extract stays under
    CDLA-Permissive-2.0 (no Apache-2.0 NOTICE obligations for the backend).
    """
    CACHE.mkdir(exist_ok=True)
    cache = CACHE / "overture_places.json"
    if cache.exists() and not refresh:
        rows = json.loads(cache.read_text(encoding="utf-8"))
        for r in rows:  # canonicalise locality for older caches
            loc = town_for(r["lat"], r["lng"], towns)
            if loc:
                r["locality"] = loc
                r["lga"] = loc
        log(f"  overture: {len(rows)} cached POIs")
        return rows

    import fsspec
    import pyarrow.parquet as pq

    release = _overture_latest_release()
    prefix = f"release/{release}/theme=places/type=place/"
    xml = http_get(
        f"{OVERTURE_BASE}/?list-type=2&prefix={urllib.parse.quote(prefix)}",
        timeout=60,
    ).decode()
    parts = [k for k in re.findall(r"<Key>([^<]+)</Key>", xml)
             if k.endswith(".parquet")]
    log(f"  overture: release {release}, {len(parts)} part files")

    out: list[dict] = []
    for n, key in enumerate(parts, 1):
        url = f"{OVERTURE_BASE}/{key}"
        try:
            with fsspec.open(url, "rb", block_size=8 * 1024 * 1024).open() as fh:
                pf = pq.ParquetFile(fh)
                md = pf.metadata
                bbox_cols = {
                    i: md.schema.column(i).path
                    for i in range(md.num_columns)
                    if md.schema.column(i).path.startswith("bbox.")
                }
                keep_rg = [rg for rg in range(md.num_row_groups)
                           if _rg_hits(md, rg, bbox_cols, towns)]
                for rg in keep_rg:
                    tbl = pf.read_row_group(rg, columns=[
                        "id", "names", "bbox", "basic_category",
                        "taxonomy", "addresses", "sources", "confidence",
                    ])
                    for row in tbl.to_pylist():
                        srcs = row.get("sources") or []
                        datasets = [(s.get("dataset") or "").lower() for s in srcs]
                        licenses = {(s.get("license") or "").strip() for s in srcs}
                        if "foursquare" in datasets:
                            continue
                        if any("apache" in x.lower() for x in licenses if x):
                            continue
                        bb = row.get("bbox") or {}
                        if None in (bb.get("xmin"), bb.get("xmax"),
                                    bb.get("ymin"), bb.get("ymax")):
                            continue
                        lng = (bb["xmin"] + bb["xmax"]) / 2
                        lat = (bb["ymin"] + bb["ymax"]) / 2
                        loc = town_for(lat, lng, towns)
                        if not loc:
                            continue
                        names = row.get("names") or {}
                        name = names.get("primary") or ""
                        if not name:
                            common = names.get("common") or {}
                            name = common.get("en") or ""
                        if not name:
                            continue
                        cat = (row.get("basic_category") or "").strip()
                        if not cat:
                            cat = ((row.get("taxonomy") or {}).get("primary") or "").strip()
                        addr_locality = ""
                        for a in (row.get("addresses") or []):
                            if a.get("locality"):
                                addr_locality = a["locality"]
                                break
                        oid = (row.get("id") or "").strip()
                        lic = sorted(x for x in licenses if x) or ["CDLA-Permissive-2.0"]
                        notes = f"Overture {oid}; confidence {row.get('confidence')}"
                        if addr_locality and slug(addr_locality) != slug(loc):
                            notes += f"; address locality: {addr_locality}"
                        out.append(
                            entry(
                                f"ov-{oid or slug(name)}",
                                name,
                                lat,
                                lng,
                                locality=loc,
                                category=slug(cat) if cat else "place",
                                precision="exact",
                                verified=False,
                                sources=["overture"],
                                licenses=lic,
                                notes=notes,
                            )
                        )
        except Exception as exc:  # noqa: BLE001 - keep building
            log(f"    part {n} failed: {exc}")
            continue
        log(f"    part {n}/{len(parts)} done - {len(out)} POIs so far")

    cache.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    log(f"  overture: {len(out)} POIs in town boxes")
    return out


# ------------------------------------------------------------------ merge ---
def _rank(e: dict) -> int:
    """Coordinate trust order when two records describe the same place."""
    if "curated" in e["sources"] and e["verified"]:
        return 0
    if "wikidata" in e["sources"]:
        return 1
    if "curated" in e["sources"]:
        return 2
    if "overture" in e["sources"]:
        return 3
    return 4  # geonames


def _match_key(e: dict, strip_words: tuple[str, ...]) -> str:
    """Normalised name with the town/state words removed, so that
    'Federal Medical Centre Makurdi' and 'Federal Medical Centre' match."""
    n = norm_name(e["name"])
    for w in strip_words:
        sw = norm_name(w)
        if sw and n.endswith(sw) and len(n) > len(sw) and len(n) - len(sw) >= 4:
            n = n[: -len(sw)]
    return n


# Places where Overture's geometry is authoritative even when the sources
# disagree beyond the normal 1 km merge radius. Review items 1 & 2 were
# resolved as "replace with Overture data" (2026-10-02): names/aliases of the
# other sources are kept, but lat/lng come from Overture.
PREFER_OVERTURE = {"judgesquarters", "modernmarket", "aperakustadium"}
PREFER_RADIUS_M = 5000


def dedupe(entries: list[dict], towns: list[dict]) -> list[dict]:
    """Merge records describing the same place in the same town.

    Names are compared with town words stripped; exact matches merge up to
    1 km apart (village coordinates differ between sources), or up to
    [PREFER_RADIUS_M] for entries listed in PREFER_OVERTURE. The
    higher-trust record supplies the coordinates - except for
    PREFER_OVERTURE entries, where Overture's coordinates always win.
    """
    strip_words = tuple({t["name"] for t in towns} | {"benue", "nigeria"})
    merged: dict[str, dict] = {}
    order: list[str] = []
    for e in entries:
        match_key = _match_key(e, strip_words)
        prefer = match_key in PREFER_OVERTURE
        radius_m = PREFER_RADIUS_M if prefer else 1000
        key = (e["locality"], match_key)
        hit = None
        for other_id in order:
            o = merged[other_id]
            if (o["locality"], _match_key(o, strip_words)) != key:
                continue
            if haversine_km(e["lat"], e["lng"], o["lat"], o["lng"]) * 1000 <= radius_m:
                hit = o
                break
        if hit is None:
            merged[e["id"]] = e
            order.append(e["id"])
            continue
        keep, drop = (e, hit) if _rank(e) < _rank(hit) else (hit, e)
        keep = dict(keep)
        keep["sources"] = sorted(set(keep["sources"]) | set(drop["sources"]))
        keep["licenses"] = sorted(set(keep.get("licenses", [])) | set(drop.get("licenses", [])))
        keep["aliases"] = sorted(
            set(keep["aliases"]) | set(drop["aliases"]) | {drop["name"], hit["name"], e["name"]}
            - {keep["name"]}
        )
        keep["notes"] = "; ".join(x for x in [keep["notes"], drop["notes"]] if x)
        keep["verified"] = bool(keep["verified"] or drop["verified"])
        if prefer:
            ov = e if "overture" in e["sources"] else hit if "overture" in hit["sources"] else None
            if ov is not None:
                keep["lat"] = ov["lat"]
                keep["lng"] = ov["lng"]
                if ov.get("precision"):
                    keep["precision"] = ov["precision"]
        merged[keep["id"]] = keep
        for k in list(merged):
            if merged[k] is hit or merged[k] is e:
                if k != keep["id"]:
                    merged.pop(k, None)
                    if k in order:
                        order.remove(k)
        if keep["id"] not in order:
            order.append(keep["id"])
    return [merged[i] for i in order if i in merged]


def validate(entries: list[dict], towns: list[dict]) -> list[str]:
    problems: list[str] = []
    seen_ids: set[str] = set()
    seen_names: dict[tuple[str, str], dict] = {}
    for e in entries:
        if e["id"] in seen_ids:
            problems.append(f"duplicate id: {e['id']}")
        seen_ids.add(e["id"])
        if not (-90 <= e["lat"] <= 90 and -180 <= e["lng"] <= 180):
            problems.append(f"{e['id']}: coordinates out of range")
        if not (6.2 <= e["lat"] <= 8.2 and 7.7 <= e["lng"] <= 9.9):
            problems.append(f"{e['id']}: outside Benue envelope ({e['lat']},{e['lng']})")
        key = (e["locality"], norm_name(e["name"]))
        if key in seen_names:
            other = seen_names[key]
            if other["id"] != e["id"] and haversine_km(
                e["lat"], e["lng"], other["lat"], other["lng"]
            ) < 1.5:
                problems.append(
                    f"near-duplicate in {e['locality']}: {e['name']} "
                    f"({other['id']} vs {e['id']}, {haversine_km(e['lat'], e['lng'], other['lat'], other['lng'])*1000:.0f} m)"
                )
        else:
            seen_names[key] = e
        if not e["locality"]:
            problems.append(f"{e['id']}: locality not resolved")
    return problems


# ------------------------------------------------------------------ build ---
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--skip-network", action="store_true", help="curated CSVs only")
    ap.add_argument("--skip-overture", action="store_true", help="skip the Overture places pull")
    ap.add_argument("--refresh-overture", action="store_true", help="re-pull Overture even if cached")
    ap.add_argument("--out", default=str(OUT), help="output directory")
    args = ap.parse_args()

    towns = load_towns()
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    log("loading curated CSVs ...")
    entries = load_curated(towns)
    if not args.skip_network:
        log("pulling GeoNames ...")
        entries += fetch_geonames(towns)
        log("pulling Wikidata ...")
        try:
            entries += fetch_wikidata(towns)
        except Exception as exc:  # noqa: BLE001
            log(f"  wikidata skipped: {exc}")
        if not args.skip_overture:
            log("pulling Overture places ...")
            try:
                entries += fetch_overture(towns, refresh=args.refresh_overture)
            except Exception as exc:  # noqa: BLE001
                log(f"  overture skipped: {exc}")

    before = len(entries)
    entries = dedupe(entries, towns)
    log(f"merged {before} -> {len(entries)} unique entries")

    problems = validate(entries, towns)
    for p in problems:
        log(f"  WARN {p}")

    entries.sort(key=lambda e: (e["locality"], e["name"].lower()))

    counts: dict[str, dict[str, int]] = {}
    for e in entries:
        counts.setdefault(e["locality"], {}).setdefault(e["category"], 0)
        counts[e["locality"]][e["category"]] += 1
    by_source: dict[str, int] = {}
    for e in entries:
        for s in e["sources"]:
            by_source[s] = by_source.get(s, 0) + 1

    doc = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "state": "Benue",
        "towns": [t["name"] for t in towns],
        "entry_count": len(entries),
        "sources": [
            {"name": "curated", "license": "project-owned", "attribution": "VT Rides / local curation"},
            {"name": "geonames", "license": "CC-BY-4.0",
             "attribution": "GeoNames (https://www.geonames.org/) - CC BY 4.0"},
            {"name": "wikidata", "license": "CC0-1.0",
             "attribution": "Wikidata (https://www.wikidata.org/) - CC0"},
            {"name": "overture", "license": "CDLA-Permissive-2.0",
             "attribution": ("Overture Maps Foundation places theme - CDLA "
                             "Permissive 2.0 (Meta, Microsoft, PinMeTo et al.); "
                             "Foursquare-sourced records excluded")},
        ],
        "counts_by_locality": counts,
        "counts_by_source": by_source,
        "entries": entries,
    }

    json_path = out_dir / "benue_gazetteer.json"
    json_path.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")

    csv_path = out_dir / "benue_gazetteer.csv"
    cols = ["id", "name", "aliases", "locality", "lga", "state", "category",
            "lat", "lng", "precision", "verified", "sources", "licenses", "notes"]
    with csv_path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for e in entries:
            row = dict(e)
            row["aliases"] = "|".join(e["aliases"])
            row["sources"] = "|".join(e["sources"])
            row["licenses"] = "|".join(e.get("licenses", []))
            row["verified"] = "true" if e["verified"] else "false"
            w.writerow({k: row[k] for k in cols})

    write_sources_md(out_dir, doc)

    ASSET.parent.mkdir(parents=True, exist_ok=True)
    ASSET.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")),
                     encoding="utf-8")

    log("")
    log(f"wrote {json_path} ({json_path.stat().st_size:,} bytes)")
    log(f"wrote {csv_path}")
    log(f"wrote {out_dir / 'SOURCES.md'}")
    log(f"wrote app asset {ASSET} ({ASSET.stat().st_size:,} bytes)")
    log(f"entries: {len(entries)}  by source: {by_source}")
    for loc, cats in sorted(counts.items()):
        log(f"  {loc}: {sum(cats.values())} {dict(sorted(cats.items()))}")
    if problems:
        log(f"\n{len(problems)} validation warning(s) - review before shipping")
    return 0


def write_sources_md(out_dir: pathlib.Path, doc: dict) -> None:
    lines = [
        "# Benue gazetteer - sources, licensing and provenance",
        "",
        f"Generated: {doc['generated_at']}  |  Schema version: {doc['schema_version']}",
        f"Entries: {doc['entry_count']}  |  Towns: {', '.join(doc['towns'])}",
        "",
        "## Sources",
        "",
    ]
    for s in doc["sources"]:
        lines.append(f"- **{s['name']}** - license: `{s['license']}` - attribution: {s['attribution']}")
    lines += [
        "",
        "Per-entry provenance is carried in the `sources` field of every record,",
        "and in the `sources` column of the CSV export.",
        "",
        "## Obligations when redistributing",
        "",
        "- GeoNames: keep the CC BY 4.0 attribution above.",
        "- Wikidata: CC0 - no obligation.",
        "- Curated entries: owned by this project (VT Rides).",
        "- Overture places: CDLA Permissive 2.0 - keep the attribution above "
        "(Foursquare-sourced records were excluded on purpose).",
        "- No OpenStreetMap data is included (OSM would impose ODbL share-alike).",
        "- No Google Maps / Places data is included (Google terms prohibit storage and redistribution).",
        "",
        "## Regenerating",
        "",
        "```",
        "python tool/gazetteer/build.py",
        "```",
        "",
        "Outputs: `out/benue_gazetteer.json` (handoff), `out/benue_gazetteer.csv`",
        "(spreadsheet review / contribution), `out/SOURCES.md` (this file), plus",
        "`assets/data/benue_gazetteer.json` (app asset).",
        "",
        "## Contribution workflow",
        "",
        "1. Edit `curated/<town>.csv` (never edit the generated files).",
        "2. Set `verified=true` only after a human confirmed name + coordinates.",
        "3. Re-run `build.py`; review the warnings it prints.",
        "4. Commit the CSVs together with the regenerated outputs.",
        "",
    ]
    (out_dir / "SOURCES.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
