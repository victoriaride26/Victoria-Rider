#!/usr/bin/env python3
"""View / search the Benue gazetteer built by build.py.

Usage:
  python tool/gazetteer/view.py --list               # HTML list of everything
  python tool/gazetteer/view.py --list --open        # ...and open it
  python tool/gazetteer/view.py wurukum              # search names + aliases
  python tool/gazetteer/view.py --near 7.7136,8.5839 # landmarks near a point
  python tool/gazetteer/view.py --near 7.7136,8.5839 --radius 500
  python tool/gazetteer/view.py --town Makurdi       # list a town (default 50)
  python tool/gazetteer/view.py --town Gboko --limit 0   # list everything
  python tool/gazetteer/view.py --map                # write an HTML map
  python tool/gazetteer/view.py --map --town Makurdi --open

The list (out/gazetteer_list.html) has a filter box - type a few letters and
it narrows instantly; nothing there? Then add it with add.py.
The map (out/gazetteer_map.html) plots every entry as a Leaflet pin coloured
by source - open it whenever you need to eyeball coordinates before setting
verified=true in the curated CSVs.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "out" / "benue_gazetteer.json"
MAP_OUT = ROOT / "out" / "gazetteer_map.html"
LIST_OUT = ROOT / "out" / "gazetteer_list.html"

SOURCE_COLORS = {
    "curated": "#d73027",
    "overture": "#4575b4",
    "wikidata": "#1a9850",
    "geonames": "#fdae61",
}


def norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def haversine_m(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    import math
    r = 6371000.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = math.radians(b_lat - a_lat)
    dl = math.radians(b_lng - a_lng)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def load() -> list[dict]:
    if not DATA.exists():
        sys.exit(f"{DATA} not found - run `python tool/gazetteer/build.py` first.")
    return json.loads(DATA.read_text(encoding="utf-8"))["entries"]


def score(entry: dict, q: str) -> int:
    """Same ranking the Dart gazetteer uses: 0 exact, 1 prefix, 2 substring."""
    best = -1
    for candidate in [entry["name"], *entry.get("aliases", [])]:
        c = norm(candidate)
        if not c:
            continue
        if c == q:
            s = 0
        elif c.startswith(q):
            s = 1
        elif len(q) >= 3 and q in c:
            s = 2
        else:
            continue
        if best < 0 or s < best:
            best = s
    return best


def print_entries(entries: list[dict]) -> None:
    for e in entries:
        aliases = ", ".join(e.get("aliases", []))
        if len(aliases) > 60:
            aliases = aliases[:57] + "..."
        print(f"{e['name'][:38]:38} | {e['locality'][:13]:13} | "
              f"{e['lat']:9.5f},{e['lng']:9.5f} | {'+'.join(e['sources']):22} | {aliases}")


def write_map(entries: list[dict]) -> None:
    # One marker group per source so the layer control can toggle them.
    layers: dict[str, list[dict]] = {}
    for e in entries:
        source = e["sources"][0] if e.get("sources") else "unknown"
        layers.setdefault(source, []).append(e)
    marker_js = []
    for source, items in sorted(layers.items()):
        color = SOURCE_COLORS.get(source, "#999999")
        marker_js.append(f"const layer_{re.sub(r'[^a-z0-9]', '_', source)} = L.layerGroup();")
        for e in items:
            popup = json.dumps(
                f"<b>{e['name']}</b><br>{e['locality']} &middot; {e.get('category', '')}<br>"
                f"{e['lat']:.5f}, {e['lng']:.5f} ({e.get('precision', '?')})<br>"
                f"sources: {', '.join(e.get('sources', []))}<br>"
                f"aliases: {', '.join(e.get('aliases', []))}"
            )
            marker_js.append(
                f"L.marker([{e['lat']}, {e['lng']}], {{icon: L.divIcon({{className: '', "
                f"html: '<div style=\"background:{color};width:12px;height:12px;border-radius:50%;"
                f"border:2px solid #fff;box-shadow:0 0 3px #000\"></div>', "
                f"iconSize: [12, 12], iconAnchor: [6, 6]}})}})"
                f".bindPopup({popup})"
                f".addTo(layer_{re.sub(r'[^a-z0-9]', '_', source)});"
            )
    control = (
        "L.control.layers({}, {\n"
        + ",\n".join(
            f"  '{src} ({len(items)})': layer_{re.sub(r'[^a-z0-9]', '_', src)}"
            for src, items in sorted(layers.items())
        )
        + "}).addTo(map);"
    )
    fit = "map.fitBounds([[" + "],[".join(
        f"{e['lat']},{e['lng']}" for e in entries[:500]
    ) + "]])" if entries else ""

    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>Benue gazetteer</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>html,body,#map{{height:100%;margin:0}}</style></head>
<body><div id="map"></div>
<script>
const map = L.map('map').setView([7.4, 8.7], 8);
L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png',
  {{attribution: '&copy; OpenStreetMap contributors'}});
{chr(10).join(marker_js)}
{control}
{fit}
</script></body></html>
"""
    MAP_OUT.write_text(html, encoding="utf-8")


def write_list(entries: list[dict]) -> None:
    rows = []
    for e in sorted(entries, key=lambda x: (x["locality"], x["name"].lower())):
        blob = norm(" ".join([e["name"], *e.get("aliases", []), e["locality"]]))
        sources = ", ".join(e.get("sources", []))
        dot = f'<span class="dot" style="background:{SOURCE_COLORS.get(sources.split(",")[0].strip(), "#999")}"></span>'
        rows.append(
            f'<tr data-s="{blob}">'
            f"<td>{html.escape(e['name'])}</td>"
            f"<td>{html.escape(', '.join(e.get('aliases', [])))}</td>"
            f"<td>{html.escape(e['locality'])}</td>"
            f"<td class='num'>{e['lat']:.5f}, {e['lng']:.5f}</td>"
            f"<td>{html.escape(e.get('category', ''))}</td>"
            f"<td>{dot} {html.escape(sources)}</td>"
            f"<td>{'yes' if e.get('verified') else ''}</td>"
            f"</tr>"
        )

    out = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Benue gazetteer - list</title>
<style>
  body {{ font: 14px/1.4 system-ui, sans-serif; margin: 0; color: #222; }}
  header {{ position: sticky; top: 0; background: #fff; padding: 12px 16px;
            border-bottom: 1px solid #ddd; z-index: 1; }}
  #q {{ width: 60%; padding: 8px 12px; font-size: 16px; border: 1px solid #bbb;
        border-radius: 8px; }}
  #count {{ color: #666; margin-left: 12px; }}
  .hint {{ color: #0a7; font-size: 12px; margin-left: 12px; }}
  table {{ border-collapse: collapse; width: 100%; }}
  th, td {{ text-align: left; padding: 6px 10px; border-bottom: 1px solid #eee;
            vertical-align: top; }}
  th {{ position: sticky; top: 61px; background: #f7f7f7; font-size: 12px;
        text-transform: uppercase; letter-spacing: .04em; color: #555; }}
  tr:nth-child(even) {{ background: #fafafa; }}
  td.num {{ font-variant-numeric: tabular-nums; white-space: nowrap; }}
  .dot {{ display: inline-block; width: 9px; height: 9px; border-radius: 50%;
          margin-right: 4px; }}
</style></head>
<body>
<header>
  <input id="q" type="search" placeholder="Filter all {len(entries)} places..."
         autofocus>
  <span id="count">{len(entries)} / {len(entries)}</span>
  <span class="hint">not found? <code>python tool/gazetteer/add.py</code></span>
</header>
<table>
<thead><tr><th>Name</th><th>Aliases</th><th>Town</th><th>Coords</th>
<th>Category</th><th>Sources</th><th>Verified</th></tr></thead>
<tbody id="rows">
{chr(10).join(rows)}
</tbody></table>
<script>
const q = document.getElementById('q');
const rows = [...document.querySelectorAll('#rows tr')];
const count = document.getElementById('count');
function apply() {{
  const s = q.value.toLowerCase().replace(/[^a-z0-9]+/g, '');
  let shown = 0;
  for (const r of rows) {{
    const hit = !s || r.dataset.s.includes(s);
    r.style.display = hit ? '' : 'none';
    if (hit) shown++;
  }}
  count.textContent = shown + ' / ' + rows.length;
}}
q.addEventListener('input', apply);
</script>
</body></html>
"""
    LIST_OUT.write_text(out, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("query", nargs="?", help="name or alias to search for")
    ap.add_argument("--town", help="restrict to one locality")
    ap.add_argument("--near", metavar="LAT,LNG",
                    help="list landmarks within --radius of a point, nearest first")
    ap.add_argument("--radius", type=int, default=1000,
                    help="radius in metres for --near (default 1000)")
    ap.add_argument("--limit", type=int, default=50,
                    help="max rows to print (0 = all, default 50)")
    ap.add_argument("--map", action="store_true", help="write out/gazetteer_map.html")
    ap.add_argument("--list", action="store_true",
                    help="write out/gazetteer_list.html (filterable table of everything)")
    ap.add_argument("--open", action="store_true",
                    help="open the generated map/list in the default browser")
    args = ap.parse_args()

    entries = load()
    if args.town:
        entries = [e for e in entries if e["locality"].lower() == args.town.lower()]
        if not entries:
            towns = sorted({e["locality"] for e in load()})
            sys.exit(f"No entries in '{args.town}'. Known towns: {', '.join(towns)}")

    if args.near:
        try:
            lat_s, lng_s = args.near.split(",")
            plat, plng = float(lat_s), float(lng_s)
        except ValueError:
            sys.exit("--near expects LAT,LNG e.g. --near 7.7136,8.5839")
        nearby = sorted(
            ((haversine_m(plat, plng, e["lat"], e["lng"]), e) for e in entries),
            key=lambda t: t[0],
        )
        hits = [(d, e) for d, e in nearby if d <= args.radius]
        if not hits:
            print(f"Nothing within {args.radius} m of ({plat}, {plng}).")
            return 1
        print(f"{len(hits)} landmark(s) within {args.radius} m of "
              f"({plat}, {plng}):")
        for d, e in hits:
            aliases = ", ".join(e.get("aliases", []))
            if len(aliases) > 50:
                aliases = aliases[:47] + "..."
            print(f"{d:6.0f} m | {e['name'][:36]:36} | {e['locality'][:10]:10} | "
                  f"{'+'.join(e['sources']):22} | {aliases}")
        return 0

    if args.list:
        write_list(entries)
        print(f"wrote {LIST_OUT} ({len(entries)} entries)")
        if args.open:
            webbrowser.open(LIST_OUT.as_uri())
        return 0

    if args.map:
        write_map(entries)
        print(f"wrote {MAP_OUT} ({len(entries)} entries)")
        if args.open:
            webbrowser.open(MAP_OUT.as_uri())
        return 0

    if args.query:
        q = norm(args.query)
        hits = sorted(
            ((score(e, q), e) for e in entries if score(e, q) >= 0),
            key=lambda t: (t[0], t[1]["name"].lower()),
        )
        if not hits:
            print(f"No match for '{args.query}'"
                  + (f" in {args.town}" if args.town else "") + ".")
            return 1
        print(f"{len(hits)} match(es) for '{args.query}':")
        print_entries([e for _, e in hits])
        return 0

    if args.limit:
        entries = entries[: args.limit]
    print(f"{len(entries)} entries" + (f" in {args.town}" if args.town else ""))
    print_entries(entries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
