#!/usr/bin/env python3
"""Lane IOS-30: five small INI mods for the Mods folder, made from YOUR OWN RotWK 2.01 install (tools/mod/README.md).

    python3 tools/mod/make_ini_mods.py --out <folder> [--rotwk <RotWK install>] [--copy-to <Mods folder>]... <mod>... | all

Each mod changes as few lines as it can and never the same file as another one (nor as SauronAtTheFortress, make_sauron_mod.py), so any
combination works in any order: the Mods tab's rule is "a later mod wins a whole file", and no two of these hold the same file. The tool checks
that before it writes anything. Where a mod adds rather than changes, it adds its own file in data\\ini\\object\\zzmods\\ (the game reads every
file of the Object folder, in name order, after the retail ones; such a file may hold any block, as retail's INI load has one block table):

  BalrogUnleashed  the Goblins recruit the Balrog at their fortress for 5,000 (60 s), his retail strength, no time limit. Adds
                   zzmods\\balrogunleashed.ini: "ChildObject WildBalrog MordorBalrog" (the spell book's Balrog, neutralunits.ini: Side Wild,
                   BuildCost / BuildTime, recruit text, KindOf without SUMMONED, RemoveModule ModuleTag_LifetimeUpdate), a PlayerTemplate
                   FactionWild block whose BuildableHeroesMP is retail's list plus WildBalrog (a PlayerTemplate parsed again takes only the fields
                   it names, RW 0x5FE852) and a copy of MordorBalrog's ExperienceLevel (rank 10) for WildBalrog. The fortress' hero menu
                   (WildFortressCommandSet, seven hero slots) has room.
  DoubleArmy       every command point limit x2: data\\ini\\gamedata.ini's five *_COMMAND_POINT_BONUS defines (every building's
                   CommandPointBonus but one is one of them) and the {Good|Evil}CommandPoints[MPn|AI|Bonus] start / cap pairs; the one literal
                   bonus (data\\ini\\object\\neutral\\hobbitworkpit.ini, 10) too. The Men marketplace's Grand Harvest (+100, CommandPointsUpgrade
                   in system.ini) stays: DarkLordsForAll changes that file.
  RapidBuild       buildings and units build four times faster: zzmods\\rapidbuild.ini holds a GameData block with retail's
                   MultiPlayUnitSpeedMult / MultiPlayBuildingSpeedMult x 0.25 (RW 0x73C39E: the build time of skirmish and multiplayer games;
                   OpenBFME merges a mod's Object-folder GameData block over gamedata.ini, lane MODS-3). Upgrades and hero recruiting keep their times.
  VeteranHeroes    every hero of the playable factions' BuildableHeroesMP starts at level 5: an ExperienceLevelCreate module (LevelToGrant 5, as the
                   ring heroes' LevelToGrant 10) at the end of each hero's own block (35 heroes in 33 files). Create-a-Hero and the ring heroes
                   (level 10 already) are left alone.
  DarkLordsForAll  every evil faction can recruit Sauron, every good faction Galadriel (their ring hero versions, BuildableRingHeroesMP: 10,000,
                   level 10) without the One Ring: the spell books' BuildableHeroListUpgrade (system.ini, which gives the ring hero's record) is
                   also triggered by each faction's own Upgrade_<side>Faction, and Command_RingHeroReviveSlot (commandbutton.ini) loses
                   NEED_UPGRADE. lotr.str: "Use the One Ring to summon the Dark Lord / the Storm Queen" -> "Summon the ...". Killed, they still
                   drop the One Ring (retail's ring hero). With SauronAtTheFortress on too, Mordor offers both Saurons.

The output holds bytes of your game files: keep it to yourself and never commit it; the tool refuses an output folder inside the repository.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Callable, NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from modkit import (MOD_OBJECT_FOLDER, POLICY, ModError, RetailArchives, body_eol, copy_mod, field_value, find_block,  # noqa: E402
                    find_object_block, find_unnamed_block, inside_repository, key, lines_of, list_field, set_value, split_comment,
                    write_mod_folder)

PLAYER_TEMPLATE = "data\\ini\\playertemplate.ini"
GAMEDATA = "data\\ini\\gamedata.ini"
COMMAND_SET = "data\\ini\\commandset.ini"
COMMAND_BUTTON = "data\\ini\\commandbutton.ini"
SYSTEM = "data\\ini\\object\\system\\system.ini"
NEUTRAL_UNITS = "data\\ini\\object\\neutral\\neutralunits.ini"
STRINGS = "data\\lotr.str"
OBJECT_FOLDER = "data\\ini\\object\\"
SAURON_MOD_FILES = [PLAYER_TEMPLATE]  # make_sauron_mod.py's one file (checked against these mods)
CRLF = "\r\n"


class Mod(NamedTuple):
    name: str
    title: str
    description: str
    build: Callable[[RetailArchives], list[tuple[str, bytes]]]


def _enc(text: str) -> bytes:
    return text.encode("latin-1")


def playable_factions(template_text: str) -> list[str]:
    """the PlayerTemplates with PlayableSide = Yes, in file order"""
    lines = lines_of(template_text)
    out = []
    for i, line in enumerate(lines):
        m = re.match(r"^\s*PlayerTemplate\s+(\S+)", line)
        if m:
            first, end = find_block(lines, "PlayerTemplate", m.group(1))
            try:
                _, side = field_value(lines, first, end, "PlayableSide")
            except ModError:
                continue
            if side.lower() == "yes":
                out.append(m.group(1))
    return out


def generic_slots(command_set_text: str, command_set: str) -> int:
    lines = lines_of(command_set_text)
    first, end = find_block(lines, "CommandSet", command_set)
    return sum(1 for l in lines[first + 1:end] if re.search(r"=\s*Command_GenericReviveSlot\d+\b", split_comment(l)[0]))


# ---------------------------------------------------------------------------------------------------------------------------------
# BalrogUnleashed
# ---------------------------------------------------------------------------------------------------------------------------------
BALROG = "MordorBalrog"
BALROG_HERO = "WildBalrog"
BALROG_FACTION = "FactionWild"
BALROG_FORTRESS_SET = "WildFortressCommandSet"
BALROG_COST, BALROG_TIME = 5000, 60  # as Drogoth, the Goblins' 5,000 hero (DROGOTH_BUILDCOST / _BUILDTIME)
BALROG_FILE = MOD_OBJECT_FOLDER + "balrogunleashed.ini"


EXPERIENCE_LEVELS = "data\\ini\\experiencelevels.ini"


def experience_levels_of(text: str, target: str) -> list[list[str]]:
    """the ExperienceLevel blocks (their lines, without line ends) whose TargetNames is exactly `target`; an ExperienceLevel nests one kind of
    block (SelectionDecal .. End)"""
    lines = [l.rstrip("\r\n") for l in lines_of(text)]
    out, i = [], 0
    while i < len(lines):
        if not re.match(r"^\s*ExperienceLevel\s+\w+", lines[i]):
            i += 1
            continue
        depth, j = 0, i + 1
        while j < len(lines):
            body = split_comment(lines[j])[0].strip()
            if re.match(r"^SelectionDecal\b", body, re.IGNORECASE):
                depth += 1
            elif re.match(r"^End\b", body, re.IGNORECASE):
                if depth == 0:
                    break
                depth -= 1
            j += 1
        if j == len(lines):
            raise ModError(f"experiencelevels.ini line {i + 1}: an ExperienceLevel without End")
        block = lines[i:j + 1]
        names = next((split_comment(l.split("=", 1)[1])[0].split() for l in block if re.match(r"^\s*TargetNames\s*=", l)), [])
        if names == [target]:
            out.append(block)
        i = j + 1
    return out


def balrog_text(template_text: str, units_text: str, command_set_text: str, levels_text: str) -> str:
    heroes = list_field(template_text, "PlayerTemplate", BALROG_FACTION, "BuildableHeroesMP")
    if any(h.lower() == BALROG_HERO.lower() for h in heroes):
        raise ModError(f"{BALROG_FACTION} already lists {BALROG_HERO}")
    slots = generic_slots(command_set_text, BALROG_FORTRESS_SET)
    others = [h for h in heroes if h.lower() != "createahero"]
    if len(others) + 1 > slots:
        raise ModError(f"{BALROG_FORTRESS_SET} has {slots} hero slots and {BALROG_FACTION} already fills {len(others)}: no room for the Balrog")
    lines = lines_of(units_text)
    first, end, kw, _ = find_object_block(lines, BALROG)
    _, kind_of = field_value(lines, first, end, "KindOf")
    kinds = kind_of.split()
    if "SUMMONED" not in kinds or "HERO" not in kinds:
        raise ModError(f"{BALROG}'s KindOf is not the spell book Balrog's (HERO ... SUMMONED): {kind_of}")
    if not any(re.match(r"^\s*Behavior\s*=\s*LifetimeUpdate\s+ModuleTag_LifetimeUpdate\b", l) for l in lines[first:end]):
        raise ModError(f"{BALROG} has no LifetimeUpdate ModuleTag_LifetimeUpdate to remove")
    levels = experience_levels_of(levels_text, BALROG)
    if len(levels) != 1:
        raise ModError(f"experiencelevels.ini: {len(levels)} ExperienceLevel blocks target {BALROG} alone; expected one")
    level = [re.sub(r"^(\s*ExperienceLevel\s+)\w+", r"\g<1>" + BALROG_HERO, levels[0][0])] + \
        [re.sub(r"^(\s*TargetNames\s*=\s*)" + BALROG + r"\b", r"\g<1>" + BALROG_HERO, l) for l in levels[0][1:]]
    return CRLF.join([
        "; BalrogUnleashed (an OpenBFME Mods-folder mod, tools/mod/make_ini_mods.py): the Goblins recruit the Balrog at their fortress.",
        f"; The spell book's Balrog ({BALROG}) as a hero of {BALROG_FACTION}: his own stats, no time limit, {BALROG_COST} and {BALROG_TIME} s as Drogoth.",
        "",
        f"ChildObject {BALROG_HERO} {BALROG}",
        "\tSide\t\t\t= Wild",
        f"\tBuildCost\t\t= {BALROG_COST}",
        f"\tBuildTime\t\t= {BALROG_TIME}",
        "\tRecruitText\t\t= CONTROLBAR:SummonBalrog",
        "\tReviveText\t\t= CONTROLBAR:SummonBalrog",
        "\tKindOf\t\t\t= " + " ".join(k for k in kinds if k != "SUMMONED"),
        "\tRemoveModule ModuleTag_LifetimeUpdate",
        "End",
        "",
        f"PlayerTemplate {BALROG_FACTION}",
        "\tBuildableHeroesMP\t= " + " ".join(heroes + [BALROG_HERO]),
        "End",
        "",
        f"; his rank, decal and the experience he gives, as {BALROG}'s (experiencelevels.ini)"] + level + [""])


def build_balrog(a: RetailArchives) -> list[tuple[str, bytes]]:
    _, template = a.text(PLAYER_TEMPLATE)
    _, units = a.text(NEUTRAL_UNITS)
    _, sets = a.text(COMMAND_SET)
    _, levels = a.text(EXPERIENCE_LEVELS)
    return [(BALROG_FILE, _enc(balrog_text(template, units, sets, levels)))]


# ---------------------------------------------------------------------------------------------------------------------------------
# DoubleArmy
# ---------------------------------------------------------------------------------------------------------------------------------
CP_DEFINE = re.compile(r"^(\s*#define\s+\w*COMMAND_POINT_BONUS\s+)(\d+)(.*)$")
CP_PAIR_KEY = re.compile(r"^(Good|Evil)CommandPoints(MP\d+|AI|Bonus)?$", re.IGNORECASE)


def _double_ints(value: str) -> str:
    out = []
    for tok in value.split():
        if not re.fullmatch(r"\d+", tok):
            raise ModError(f"'{value}': '{tok}' is not a whole number")
        out.append(str(int(tok) * 2))
    return " ".join(out)


def double_gamedata(text: str) -> tuple[str, int, int]:
    """(the text with every *_COMMAND_POINT_BONUS define and every command point pair of the GameData block doubled, defines, pairs)"""
    lines = lines_of(text)
    defines = 0
    for i, line in enumerate(lines):
        body, eol = body_eol(line)
        m = CP_DEFINE.match(body)
        if m:
            lines[i] = m.group(1) + str(int(m.group(2)) * 2) + m.group(3) + eol
            defines += 1
    first, end = find_unnamed_block(lines, "GameData")
    pairs = 0
    for i in range(first + 1, end):
        m = re.match(r"^\s*(\w+)\s*=(.*)$", lines[i].rstrip("\r\n"))
        if m and CP_PAIR_KEY.match(m.group(1)):
            lines[i] = set_value(lines[i], _double_ints(split_comment(m.group(2))[0]))
            pairs += 1
    if defines == 0 or pairs == 0:
        raise ModError(f"gamedata.ini: {defines} command point defines and {pairs} command point pairs; expected both")
    return "".join(lines), defines, pairs


def double_literal_bonuses(text: str) -> tuple[str, int]:
    """every `CommandPointBonus = <number>` (a literal, not one of the defines) doubled"""
    lines = lines_of(text)
    n = 0
    for i, line in enumerate(lines):
        m = re.match(r"^\s*CommandPointBonus\s*=(.*)$", line.rstrip("\r\n"))
        if m and re.fullmatch(r"\d+", split_comment(m.group(1))[0].strip()):
            lines[i] = set_value(line, str(int(split_comment(m.group(1))[0]) * 2))
            n += 1
    return "".join(lines), n


def build_double_army(a: RetailArchives) -> list[tuple[str, bytes]]:
    name, text = a.text(GAMEDATA)
    out = [(name, _enc(double_gamedata(text)[0]))]
    for k in a.names_under(OBJECT_FOLDER):
        if not k.endswith(".ini"):
            continue
        n, t = a.text(k)
        if "commandpointbonus" not in t.lower():
            continue
        patched, count = double_literal_bonuses(t)
        if count:
            out.append((n, _enc(patched)))
    return out


# ---------------------------------------------------------------------------------------------------------------------------------
# RapidBuild
# ---------------------------------------------------------------------------------------------------------------------------------
SPEED_KEYS = ("MultiPlayUnitSpeedMult", "MultiPlayBuildingSpeedMult")
SPEED_FACTOR = 0.25
RAPID_FILE = MOD_OBJECT_FOLDER + "rapidbuild.ini"


def _fmt(x: float) -> str:
    return f"{x:.4f}".rstrip("0").rstrip(".")


def rapid_text(gamedata_text: str, factor: float = SPEED_FACTOR) -> str:
    lines = lines_of(gamedata_text)
    first, end = find_unnamed_block(lines, "GameData")
    out = ["; RapidBuild (an OpenBFME Mods-folder mod, tools/mod/make_ini_mods.py): buildings and units build four times faster.",
           f"; Retail's skirmish / multiplayer build time factors (data\\ini\\gamedata.ini) x {_fmt(factor)}; OpenBFME merges this block over that file's.",
           "", "GameData"]
    for k in SPEED_KEYS:
        _, value = field_value(lines, first, end, k)
        parts = []
        for tok in value.split():
            m = re.fullmatch(r"(MP\d+):([0-9.]+)", tok)
            if not m:
                raise ModError(f"GameData {k}: '{tok}' is not MPn:<number>")
            parts.append(f"{m.group(1)}:{_fmt(float(m.group(2)) * factor)}")
        out.append(f"\t{k} = " + "\t".join(parts))
    out += ["End", ""]
    return CRLF.join(out)


def build_rapid(a: RetailArchives) -> list[tuple[str, bytes]]:
    _, text = a.text(GAMEDATA)
    return [(RAPID_FILE, _enc(rapid_text(text)))]


# ---------------------------------------------------------------------------------------------------------------------------------
# VeteranHeroes
# ---------------------------------------------------------------------------------------------------------------------------------
VETERAN_LEVEL = 5
VETERAN_TAG = "ModuleTag_VeteranHeroesLevel"


def playable_heroes(template_text: str) -> list[str]:
    heroes = []
    for faction in playable_factions(template_text):
        for h in list_field(template_text, "PlayerTemplate", faction, "BuildableHeroesMP"):
            if h.lower() != "createahero" and h not in heroes:
                heroes.append(h)
    return heroes


def veteran_module(level: int = VETERAN_LEVEL) -> list[str]:
    return [f"\tBehavior = ExperienceLevelCreate {VETERAN_TAG}\t; VeteranHeroes (OpenBFME Mods folder): start at level {level}",
            f"\t\tLevelToGrant\t= {level}",
            "\t\tMPOnly\t\t\t= No",
            "\tEnd"]


def add_level_module(text: str, hero: str, level: int = VETERAN_LEVEL) -> str:
    """`text` with the ExperienceLevelCreate module added just before `hero`'s own End (the line end of the file's End line)"""
    lines = lines_of(text)
    first, end, kw, _ = find_object_block(lines, hero)
    block = "".join(lines[first:end])
    if re.search(r"\bExperienceLevelCreate\b", block):
        raise ModError(f"{kw} {hero} already has an ExperienceLevelCreate")
    eol = body_eol(lines[end])[1] or CRLF
    lines[end:end] = [l + eol for l in veteran_module(level)]
    return "".join(lines)


def build_veteran(a: RetailArchives) -> list[tuple[str, bytes]]:
    _, template = a.text(PLAYER_TEMPLATE)
    heroes = playable_heroes(template)
    where: dict[str, tuple[str, str]] = {}  # hero -> (file key, parent)
    texts: dict[str, tuple[str, str]] = {}
    for k in a.names_under(OBJECT_FOLDER):
        if not k.endswith(".ini"):
            continue
        n, t = a.text(k)
        for h in heroes:
            if h in where or not re.search(r"(?im)^\s*(?:Object|ChildObject)\s+" + re.escape(h) + r"\b", t):
                continue
            _, _, _, parent = find_object_block(lines_of(t), h)
            where[h] = (k, parent)
            texts[k] = (n, t)
    missing = [h for h in heroes if h not in where]
    if missing:
        raise ModError("no object file defines " + " ".join(missing))
    patched: dict[str, str] = {}
    for h in heroes:
        k, parent = where[h]
        if parent and parent in heroes:
            continue  # a ChildObject of a patched hero inherits the module
        patched[k] = add_level_module(patched.get(k, texts[k][1]), h)
    return [(texts[k][0], _enc(patched[k])) for k in sorted(patched)]


# ---------------------------------------------------------------------------------------------------------------------------------
# DarkLordsForAll
# ---------------------------------------------------------------------------------------------------------------------------------
RING_SLOT = "Command_RingHeroReviveSlot"
RING_HERO_FILES = ("data\\ini\\object\\evilfaction\\units\\mordor\\sauron.ini", "data\\ini\\object\\goodfaction\\units\\elven\\galadriel.ini")
RING_PREFIX = "Use the One Ring to "


def ring_slot_without_upgrade(text: str) -> str:
    lines = lines_of(text)
    first, end = find_block(lines, "CommandButton", RING_SLOT)
    i, value = field_value(lines, first, end, "Options")
    opts = value.split()
    if "NEED_UPGRADE" not in opts:
        raise ModError(f"{RING_SLOT}'s Options have no NEED_UPGRADE: {value}")
    lines[i] = set_value(lines[i], " ".join(o for o in opts if o != "NEED_UPGRADE"))
    return "".join(lines)


def faction_upgrades(template_text: str) -> list[str]:
    """each playable faction's own Upgrade_<side>Faction (its InitialUpgrades), for the factions that have a ring hero"""
    lines = lines_of(template_text)
    out = []
    for faction in playable_factions(template_text):
        first, end = find_block(lines, "PlayerTemplate", faction)
        _, ring = field_value(lines, first, end, "BuildableRingHeroesMP")
        _, initial = field_value(lines, first, end, "InitialUpgrades")
        own = [u for u in initial.split() if re.fullmatch(r"Upgrade_\w+Faction", u)]
        if not ring.split() or len(own) != 1:
            raise ModError(f"{faction}: ring heroes '{ring}', faction upgrades {own}: expected a ring hero and one Upgrade_<side>Faction")
        out.append(own[0])
    return out


def hero_list_triggers(text: str, upgrades: list[str]) -> tuple[str, int]:
    """every BuildableHeroListUpgrade module's TriggeredBy (the spell books') with `upgrades` added; (text, modules)"""
    lines = lines_of(text)
    n = 0
    for i, line in enumerate(lines):
        if not re.match(r"^\s*Behavior\s*=\s*BuildableHeroListUpgrade\b", line):
            continue
        for j in range(i + 1, len(lines)):
            body = split_comment(lines[j].rstrip("\r\n"))[0].strip()
            if re.match(r"^End\b", body, re.IGNORECASE):
                raise ModError(f"line {i + 1}: a BuildableHeroListUpgrade without TriggeredBy")
            m = re.match(r"^TriggeredBy\s*=(.*)$", body, re.IGNORECASE)
            if m:
                have = m.group(1).split()
                if have != ["Upgrade_RingHero"]:
                    raise ModError(f"line {j + 1}: TriggeredBy is '{m.group(1).strip()}', not retail's Upgrade_RingHero")
                lines[j] = set_value(lines[j], " ".join(have + upgrades))
                n += 1
                break
    if n == 0:
        raise ModError("no BuildableHeroListUpgrade module")
    return "".join(lines), n


def summon_text(text: str, labels: list[str]) -> str:
    """lotr.str with each label's "Use the One Ring to summon X" as "Summon X" (every other byte kept)"""
    lines = lines_of(text)
    for label in labels:
        at = next((i for i, l in enumerate(lines) if l.strip().lower() == label.lower()), None)
        if at is None:
            raise ModError(f"lotr.str has no {label}")
        j = next((j for j in range(at + 1, len(lines)) if lines[j].lstrip().startswith('"')), None)
        if j is None or lines[j].strip().upper() == "END":
            raise ModError(f"lotr.str: {label} has no text")
        body, eol = body_eol(lines[j])
        m = re.match(r'^(\s*")' + re.escape(RING_PREFIX) + r'([a-z])(.*)$', body)
        if not m:
            raise ModError(f"lotr.str: {label} is '{body.strip()}', not '{RING_PREFIX}...'")
        lines[j] = m.group(1) + m.group(2).upper() + m.group(3) + eol
    return "".join(lines)


def build_dark_lords(a: RetailArchives) -> list[tuple[str, bytes]]:
    _, template = a.text(PLAYER_TEMPLATE)
    bname, buttons = a.text(COMMAND_BUTTON)
    sname, system = a.text(SYSTEM)
    lname, strings = a.text(STRINGS)
    labels = []
    for f in RING_HERO_FILES:
        lines = lines_of(a.text(f)[1])
        heads = [h for h in re.findall(r"(?im)^\s*ChildObject\s+(\w+_RingHero)\s+(\w+)", "".join(lines))]
        if len(heads) != 1:
            raise ModError(f"{f}: expected one ChildObject <hero>_RingHero")
        first, end, _, _ = find_object_block(lines, heads[0][1])
        labels.append(field_value(lines, first, end, "RecruitText")[1])
    return [(bname, _enc(ring_slot_without_upgrade(buttons))),
            (sname, _enc(hero_list_triggers(system, faction_upgrades(template))[0])),
            (lname, _enc(summon_text(strings, labels)))]


# ---------------------------------------------------------------------------------------------------------------------------------
MODS = {m.name: m for m in [
    Mod("BalrogUnleashed", "Balrog unleashed",
        "The Goblins can recruit the Balrog at their fortress' hero menu for 5,000. He keeps his retail strength and stays until he is killed.",
        build_balrog),
    Mod("DoubleArmy", "Double army",
        "Every faction's command point limit is doubled: the starting limit, the cap and every building's bonus.", build_double_army),
    Mod("RapidBuild", "Rapid build", "Buildings and units are built four times faster in skirmish and multiplayer games.", build_rapid),
    Mod("VeteranHeroes", "Veteran heroes", "Every faction's heroes start at level 5.", build_veteran),
    Mod("DarkLordsForAll", "Dark lords for all",
        "Every evil faction can recruit Sauron, every good faction Galadriel, at the fortress' ring hero slot for 10,000, without the One Ring.",
        build_dark_lords),
]}


def check_independent(built: dict[str, list[str]]) -> None:
    """no two mods (these and SauronAtTheFortress) hold the same file: then the Mods tab's 'a later mod wins a whole file' never drops a change"""
    owner: dict[str, str] = {key(p): "SauronAtTheFortress" for p in SAURON_MOD_FILES}
    for name, paths in built.items():
        for p in paths:
            if key(p) in owner and owner[key(p)] != name:
                raise ModError(f"{name} and {owner[key(p)]} both change {p}")
            owner[key(p)] = name


def make(rotwk: Path, out: Path, names: list[str], policy: Path = POLICY) -> dict[str, dict]:
    archives = RetailArchives(rotwk, policy)
    files = {n: MODS[n].build(archives) for n in names}
    check_independent({n: [p for p, _ in f] for n, f in files.items()})
    return {n: write_mod_folder(out, n, files[n], MODS[n].title, MODS[n].description) for n in names}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mods", nargs="+", help="mod names (" + ", ".join(MODS) + ") or all")
    ap.add_argument("--rotwk", default=os.environ.get("ROTWK_INSTALL", ""), help="the RotWK 2.01 install folder (default: ROTWK_INSTALL)")
    ap.add_argument("--out", required=True, help="the folder the mod folders are written into (keep it outside the repository)")
    ap.add_argument("--copy-to", action="append", default=[], help="also copy the mod folders into this Mods folder (repeatable)")
    a = ap.parse_args(argv)
    names = list(MODS) if a.mods == ["all"] else a.mods
    unknown = [n for n in names if n not in MODS]
    if unknown:
        print(f"make_ini_mods: unknown mod {' '.join(unknown)} (known: {', '.join(MODS)})", file=sys.stderr)
        return 2
    if not a.rotwk:
        print("make_ini_mods: no RotWK install: pass --rotwk or set ROTWK_INSTALL", file=sys.stderr)
        return 2
    out = Path(a.out).resolve()
    if inside_repository(out):
        print(f"make_ini_mods: {out} is inside the repository; the mods hold bytes of your game files, write them elsewhere", file=sys.stderr)
        return 2
    try:
        made = make(Path(a.rotwk), out, names)
    except (ModError, OSError, ValueError) as e:
        print(f"make_ini_mods: {e}", file=sys.stderr)
        return 1
    for n, r in made.items():
        print(f"make_ini_mods: {r['archive']}: {len(r['files'])} file(s): {', '.join(r['files'][:4])}{' ...' if len(r['files']) > 4 else ''}")
        for dest in a.copy_to:
            print(f"make_ini_mods: copied to {copy_mod(r['folder'], Path(dest))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
