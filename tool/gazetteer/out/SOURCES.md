# Benue gazetteer - sources, licensing and provenance

Generated: 2026-10-03T07:36:13+00:00  |  Schema version: 1
Entries: 2020  |  Towns: Makurdi, Gboko, Otukpo, Katsina-Ala, Vandeikya

## Sources

- **curated** - license: `project-owned` - attribution: VT Rides / local curation
- **geonames** - license: `CC-BY-4.0` - attribution: GeoNames (https://www.geonames.org/) - CC BY 4.0
- **wikidata** - license: `CC0-1.0` - attribution: Wikidata (https://www.wikidata.org/) - CC0
- **overture** - license: `CDLA-Permissive-2.0` - attribution: Overture Maps Foundation places theme - CDLA Permissive 2.0 (Meta, Microsoft, PinMeTo et al.); Foursquare-sourced records excluded

Per-entry provenance is carried in the `sources` field of every record,
and in the `sources` column of the CSV export.

## Obligations when redistributing

- GeoNames: keep the CC BY 4.0 attribution above.
- Wikidata: CC0 - no obligation.
- Curated entries: owned by this project (VT Rides).
- Overture places: CDLA Permissive 2.0 - keep the attribution above (Foursquare-sourced records were excluded on purpose).
- No OpenStreetMap data is included (OSM would impose ODbL share-alike).
- No Google Maps / Places data is included (Google terms prohibit storage and redistribution).

## Regenerating

```
python tool/gazetteer/build.py
```

Outputs: `out/benue_gazetteer.json` (handoff), `out/benue_gazetteer.csv`
(spreadsheet review / contribution), `out/SOURCES.md` (this file), plus
`assets/data/benue_gazetteer.json` (app asset).

## Contribution workflow

1. Edit `curated/<town>.csv` (never edit the generated files).
2. Set `verified=true` only after a human confirmed name + coordinates.
3. Re-run `build.py`; review the warnings it prints.
4. Commit the CSVs together with the regenerated outputs.
