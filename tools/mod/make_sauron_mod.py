#!/usr/bin/env python3
"""Lane IOS-28: make the "Sauron at the fortress" test mod from YOUR OWN RotWK 2.01 install (tools/mod/README.md).

    python3 tools/mod/make_sauron_mod.py --out <folder> [--rotwk <RotWK install>] [--copy-to <Mods folder>]...

What the mod changes, and why that is the hook (RotWK 2.01's own data, read from the install):
  * Sauron exists twice in data\\ini\\object\\evilfaction\\units\\mordor\\sauron.ini: "Object MordorSauron" (BuildCost SAURON_BUILDCOST
    = 10000, the campaign's) and "ChildObject MordorSauron_RingHero MordorSauron" (the ring hero: removes the ring upgrade, drops the ring
    when he dies).
  * Every evil faction's PlayerTemplate (data\\ini\\playertemplate.ini) names the ring hero in BuildableRingHeroesMP; the fortress' hero
    menu (CommandSet MordorFortressCommandSet, slots 15..23) shows it in Command_RingHeroReviveSlot, which needs Upgrade_RingHero or
    Upgrade_FortressRingHero (the One Ring brought home). The other heroes fill Command_GenericReviveSlot1..7 in the order of the
    template's BuildableHeroesMP (CreateAHero first, its own slot).
  * Mordor lists CreateAHero and five heroes, so two generic slots are free. The mod adds "MordorSauron" at the end of FactionMordor's
    BuildableHeroesMP: Sauron is then a hero of the fortress' hero menu like the others, for 10,000, no ring needed. The ring hero
    is untouched (the One Ring still summons him). One line of one file: the mod archive holds only data\\ini\\playertemplate.ini.

The output is a folder mod: <out>/SauronAtTheFortress/ with SauronAtTheFortress.big (BIGF, as the 2.01 patch archives) and mod.txt (the
Mods menu's title and description). Drop the folder into OpenBFME's Mods folder. It holds bytes of your game files: keep it to yourself,
never commit it (the commit gate refuses .big files anyway). Nothing is read from anywhere else and the install is only read.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from modkit import (POLICY, ROOT, ModError, RetailArchives, copy_mod, find_case_insensitive, inside_repository, key,  # noqa: E402,F401
                    read_big_index, write_big, write_mod_folder)
from modkit import find_block as _block  # noqa: E402
from modkit import split_comment as _split_comment  # noqa: E402

MOD_NAME = "SauronAtTheFortress"
TITLE = "Sauron at the fortress"
DESCRIPTION = "Mordor can recruit Sauron at its fortress' hero menu for 10,000, without the One Ring."
PLAYER_TEMPLATE = "data\\ini\\playertemplate.ini"
SAURON_INI = "data\\ini\\object\\evilfaction\\units\\mordor\\sauron.ini"
COMMAND_SET = "data\\ini\\commandset.ini"
FACTION = "FactionMordor"
HERO = "MordorSauron"
FORTRESS_SET = "MordorFortressCommandSet"


# ---------------------------------------------------------------------------------------------------------------------------------
# the INI change (BIG reading / writing and the line helpers: modkit.py, shared with make_ini_mods.py)
# ---------------------------------------------------------------------------------------------------------------------------------
def heroes_of(text: str, faction: str = FACTION) -> list[str]:
    lines = text.splitlines()
    first, end = _block(lines, "PlayerTemplate", faction)
    for line in lines[first + 1:end]:
        m = re.match(r"^\s*BuildableHeroesMP\s*=(.*)$", line, re.IGNORECASE)
        if m:
            return _split_comment(m.group(1))[0].split()
    raise ModError(f"PlayerTemplate {faction} has no BuildableHeroesMP")


def add_hero(text: str, hero: str = HERO, faction: str = FACTION) -> str:
    """the playertemplate.ini text with `hero` added at the end of `faction`'s BuildableHeroesMP; every other byte unchanged"""
    lines = text.splitlines(keepends=True)
    first, end = _block([l.rstrip("\r\n") for l in lines], "PlayerTemplate", faction)
    for i in range(first + 1, end):
        body = lines[i].rstrip("\r\n")
        eol = lines[i][len(body):]
        m = re.match(r"^(\s*BuildableHeroesMP\s*=)(.*)$", body, re.IGNORECASE)
        if not m:
            continue
        value, comment = _split_comment(m.group(2))
        if any(h.lower() == hero.lower() for h in value.split()):
            raise ModError(f"{faction} already lists {hero} in BuildableHeroesMP: nothing to change")
        stripped = value.rstrip()
        gap = value[len(stripped):] or (" " if comment else "")
        lines[i] = m.group(1) + stripped + " " + hero + gap + comment + eol
        return "".join(lines)
    raise ModError(f"PlayerTemplate {faction} has no BuildableHeroesMP")


def generic_slots(text: str, command_set: str = FORTRESS_SET) -> int:
    """how many Command_GenericReviveSlot buttons the command set has (the heroes after CreateAHero fill them in order)"""
    lines = text.splitlines()
    first, end = _block(lines, "CommandSet", command_set)
    return sum(1 for l in lines[first + 1:end] if re.search(r"=\s*Command_GenericReviveSlot\d+\b", _split_comment(l)[0]))


def make(rotwk: Path, out: Path, policy: Path = POLICY) -> dict:
    """writes <out>/SauronAtTheFortress/{SauronAtTheFortress.big, mod.txt}; returns what it did"""
    archives = RetailArchives(rotwk, policy)
    name, data, source = archives.read(PLAYER_TEMPLATE)
    _, sauron, _ = archives.read(SAURON_INI)
    if not re.search(r"^\s*Object\s+" + HERO + r"\b", sauron.decode("latin-1"), re.MULTILINE | re.IGNORECASE):
        raise ModError(f"{SAURON_INI} does not define Object {HERO}")
    _, sets, _ = archives.read(COMMAND_SET)
    text = data.decode("latin-1")
    heroes = heroes_of(text)
    slots = generic_slots(sets.decode("latin-1"))
    others = [h for h in heroes if h.lower() != "createahero"]
    if len(others) + 1 > slots:
        raise ModError(f"{FORTRESS_SET} has {slots} hero slots and {FACTION} already fills {len(others)}: no room for {HERO}")
    patched = add_hero(text).encode("latin-1")
    r = write_mod_folder(out, MOD_NAME, [(name, patched)], TITLE, DESCRIPTION)
    return {"folder": r["folder"], "archive": r["archive"], "file": name, "from": source, "heroes": heroes + [HERO], "slots": slots}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rotwk", default=os.environ.get("ROTWK_INSTALL", ""), help="the RotWK 2.01 install folder (default: ROTWK_INSTALL)")
    ap.add_argument("--out", required=True, help="the folder the mod folder is written into (keep it outside the repository)")
    ap.add_argument("--copy-to", action="append", default=[], help="also copy the mod folder into this Mods folder (repeatable)")
    a = ap.parse_args(argv)
    if not a.rotwk:
        print("make_sauron_mod: no RotWK install: pass --rotwk or set ROTWK_INSTALL", file=sys.stderr)
        return 2
    out = Path(a.out).resolve()
    if inside_repository(out):
        print(f"make_sauron_mod: {out} is inside the repository; the mod holds bytes of your game files, write it elsewhere", file=sys.stderr)
        return 2
    try:
        r = make(Path(a.rotwk), out)
    except (ModError, OSError, ValueError) as e:
        print(f"make_sauron_mod: {e}", file=sys.stderr)
        return 1
    print(f"make_sauron_mod: {r['archive']}: {r['file']} (from {r['from']}), {FACTION} heroes now {' '.join(r['heroes'])} "
          f"({len(r['heroes']) - 1} heroes in the fortress' {r['slots']} generic hero slots)")
    for dest in a.copy_to:
        print(f"make_sauron_mod: copied to {copy_mod(r['folder'], Path(dest))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
