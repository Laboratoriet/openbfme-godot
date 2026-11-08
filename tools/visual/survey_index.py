#!/usr/bin/env python3
"""The visual survey's index (lane VIS-1): index.html (thumbnails of every contact sheet, the flags beside them) and INDEX.md in the sheets folder.

  python3 tools/visual/survey_index.py --flags <flags.json> --catalog <catalog.json> --sheets <vis-out>

Reads the flags tools/visual/survey_flags.py wrote; links the sheets by relative paths (the folder can be moved as a whole).
"""
from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path

FACTION_NAMES = {"men": "Men", "elves": "Elves", "dwarves": "Dwarves", "isengard": "Isengard", "mordor": "Mordor", "wild": "Goblins (Wild)",
                 "angmar": "Angmar"}
KEYS = {"FactionMen": "men", "FactionElves": "elves", "FactionDwarves": "dwarves", "FactionIsengard": "isengard", "FactionMordor": "mordor",
        "FactionWild": "wild", "FactionAngmar": "angmar"}
CONFIGS = ["fwd-def", "fwd-low", "mob-def", "mob-low"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--flags", required=True)
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--sheets", required=True)
    args = ap.parse_args()
    rows = json.load(open(args.flags))
    cat = json.load(open(args.catalog))
    sheets = Path(args.sheets)
    by = {(r["template"], r["config"]): r for r in rows}
    configs = [c for c in CONFIGS if any(r["config"] == c for r in rows)]
    css = """
:root{--bg:#14120f;--fg:#e9e2d0;--muted:#a49a83;--line:#3a342a;--flag:#e0a040;--ok:#7fae6a}
body{background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,system-ui,sans-serif;margin:0;padding:16px}
h1{font-size:20px;margin:0 0 4px} h2{font-size:17px;margin:28px 0 8px;border-bottom:1px solid var(--line);padding-bottom:4px}
.obj{display:grid;grid-template-columns:220px 1fr;gap:12px;padding:10px 0;border-bottom:1px solid var(--line)}
.name{font-weight:600} .kind{color:var(--muted);font-size:12px}
.thumbs{display:flex;gap:8px;flex-wrap:wrap} .thumbs a{display:block;text-align:center;color:var(--muted);font-size:11px;text-decoration:none}
.thumbs img{width:200px;height:auto;display:block;border:1px solid var(--line)}
ul{margin:4px 0 0 0;padding-left:18px} li{color:var(--flag)} li.none{color:var(--ok);list-style:none;margin-left:-18px}
.cfg{color:var(--muted)}
@media (max-width:640px){.obj{grid-template-columns:1fr}.thumbs img{width:44vw}}
"""
    out = ["<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>",
           "<title>Visual survey</title><style>" + css + "</style></head><body>",
           "<h1>OpenBFME visual survey (lane VIS-1)</h1>",
           f"<p class=kind>{len(set(r['template'] for r in rows))} objects, configurations: {', '.join(configs)}. Each sheet: one row per phase "
           "(units: idle, move, attack, hero powers, slope, die; buildings: finished, damaged, badly damaged, destroyed). Flags from "
           "tools/visual/survey_flags.py; see bfme/VISUAL-SURVEY.md for the triage.</p>"]
    md = ["# Visual survey index (lane VIS-1)", "", f"Configurations: {', '.join(configs)}. Sheets: `<faction>/<object>-<config>.jpg`.", ""]
    for fname, entry in ((k, v) for k, v in cat.items() if k in KEYS):
        key = KEYS[fname]
        out.append(f"<h2>{html.escape(FACTION_NAMES[key])}</h2>")
        md += [f"## {FACTION_NAMES[key]}", "", "| object | kind | flags (" + ", ".join(configs) + ") |", "|---|---|---|"]
        for kind in ("units", "heroes", "buildings"):
            for t in entry[kind]:
                out.append(f"<div class=obj><div><div class=name>{html.escape(t)}</div><div class=kind>{kind[:-1]}</div>")
                flags_html, flags_md = [], []
                for c in configs:
                    r = by.get((t, c))
                    if r is None:
                        continue
                    for f in r["flags"]:
                        flags_html.append(f"<li><span class=cfg>{c}</span> {html.escape(f['kind'])}: {html.escape(f['what'])}</li>")
                        flags_md.append(f"{c} {f['kind']}")
                out.append("<ul>" + ("".join(flags_html) if flags_html else "<li class=none>no flags</li>") + "</ul></div><div class=thumbs>")
                for c in configs:
                    p = sheets / key / f"{t}-{c}.jpg"
                    if p.exists():
                        rel = os.path.relpath(p, sheets)
                        out.append(f"<a href='{rel}'><img loading=lazy src='{rel}' alt='{html.escape(t)} {c}'>{c}</a>")
                    fl = sheets / key / f"{t}-{c}-flicker.jpg"
                    if fl.exists():
                        rel = os.path.relpath(fl, sheets)
                        out.append(f"<a href='{rel}'><img loading=lazy src='{rel}' alt='flicker'>{c} flicker</a>")
                out.append("</div></div>")
                md.append(f"| [{t}]({key}/{t}-{configs[0]}.jpg) | {kind[:-1]} | {', '.join(flags_md) if flags_md else '-'} |")
        md.append("")
    out.append("</body></html>")
    (sheets / "index.html").write_text("\n".join(out))
    (sheets / "INDEX.md").write_text("\n".join(md) + "\n")
    print(f"wrote {sheets / 'index.html'} and INDEX.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
