#!/usr/bin/env python3
"""The visual survey's catalog (lane VIS-1): every buildable unit, hero and building of each playable faction, read from the player's own game files.

Reads the pure retail mount (tools/fx/bigfs.py: ROTWK_INSTALL then BFME2_INSTALL, the pinned archive order):
  data\\ini\\playertemplate.ini  the playable factions (PlayableSide = Yes): the builder (StartingUnit0), the fortress (StartingBuilding) and the heroes
                                (BuildableHeroesMP, Create-a-Hero left out: it has no fixed model);
  data\\ini\\commandset.ini / commandbutton.ini and every object's CommandSet: from the builder and the fortress, the structures their buttons construct
                                (DOZER_CONSTRUCT, FOUNDATION_CONSTRUCT: the fortress plots, CASTLE_UNPACK_EXPLICIT_OBJECT), walked again from each
                                structure, and the units the structures train (UNIT_BUILD).

Writes one JSON file (--out): { "<faction>": { side, builder, fortress, units: [..], heroes: [..], buildings: [..] } } with template names only (no
retail bytes). godot/scripts/vissurvey_player.gd reads it (game.gd --vissurvey=<catalog.json>).

  python3 tools/visual/survey_catalog.py --out <scratch>/catalog.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "fx"))
sys.path.insert(0, str(HERE.parent / "hover"))
import bigfs  # noqa: E402
import hover_inventory as inv  # noqa: E402

STRUCTURE_COMMANDS = ("DOZER_CONSTRUCT", "FOUNDATION_CONSTRUCT", "CASTLE_UNPACK_EXPLICIT_OBJECT")
UNIT_COMMANDS = ("UNIT_BUILD",)
FACTION_ORDER = ("FactionMen", "FactionElves", "FactionDwarves", "FactionIsengard", "FactionMordor", "FactionWild", "FactionAngmar")


def set_buttons(sets: dict, set_name: str) -> list[str]:
    fields = sets.get(set_name, {})
    out = []
    for slot in range(1, 34):
        out += fields.get(str(slot), [])
    return out


def catalog(mount: bigfs.Mount) -> dict:
    sets = dict(inv.blocks(mount.read("data\\ini\\commandset.ini").decode("latin-1"), "CommandSet"))
    buttons = dict(inv.blocks(mount.read("data\\ini\\commandbutton.ini").decode("latin-1"), "CommandButton"))
    templates = dict(inv.blocks(mount.read("data\\ini\\playertemplate.ini").decode("latin-1"), "PlayerTemplate"))
    obj_sets = inv.object_command_sets(mount)

    def built(obj: str, commands: tuple[str, ...]) -> list[str]:
        out = []
        for bname in set_buttons(sets, obj_sets.get(obj, "")):
            b = buttons.get(bname, {})
            cmd = (b.get("Command") or [""])[0].split()[:1]
            if cmd and cmd[0] in commands and b.get("Object"):
                for o in b["Object"][0].split():
                    if o not in out:
                        out.append(o)
        return out

    result = {}
    for name in FACTION_ORDER:
        f = templates.get(name)
        if f is None or (f.get("PlayableSide") or ["No"])[0].lower() != "yes":
            raise SystemExit(f"{name}: not a playable PlayerTemplate in this install")
        builder = f["StartingUnit0"][0].split()[0]
        fortress = f["StartingBuilding"][0].split()[0]
        heroes = [h for h in " ".join(f.get("BuildableHeroesMP", [])).split() if h != "CreateAHero"]
        buildings = [fortress]
        todo = [builder, fortress]
        seen = set(todo)
        while todo:
            o = todo.pop(0)
            for s in built(o, STRUCTURE_COMMANDS):
                if s not in buildings:
                    buildings.append(s)
                if s not in seen:
                    seen.add(s)
                    todo.append(s)
        units = [builder]
        for s in buildings:
            for u in built(s, UNIT_COMMANDS):
                if u not in units and u not in heroes:
                    units.append(u)
        result[name] = {"side": (f.get("Side") or [""])[0], "builder": builder, "fortress": fortress, "units": units, "heroes": heroes,
                        "buildings": buildings}
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, required=True, help="the catalog JSON to write")
    args = ap.parse_args()
    cat = catalog(bigfs.Mount())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(cat, indent=1) + "\n")
    for name, f in cat.items():
        print(f"{name}: {len(f['units'])} units, {len(f['heroes'])} heroes, {len(f['buildings'])} buildings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
