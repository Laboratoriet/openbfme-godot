"""Lane IOS-30: tools/mod/make_ini_mods.py on a made-up install (no game bytes: every INI line here is invented for the test)."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
TOOL = HERE / "make_ini_mods.py"
_spec = importlib.util.spec_from_file_location("make_ini_mods", TOOL)
mim = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mim)
mk = sys.modules["modkit"]

TEMPLATE = (
    "PlayerTemplate FactionCivilian\r\n"
    "\tPlayableSide = No\r\n"
    "End\r\n"
    "PlayerTemplate FactionMen\r\n"
    "\tPlayableSide = Yes\r\n"
    "\tInitialUpgrades = Upgrade_MenFaction ; born with\r\n"
    "\tBuildableHeroesMP = CreateAHero HeroA HeroB\r\n"
    "\tBuildableRingHeroesMP = GoodQueen_RingHero\r\n"
    "End\r\n"
    "PlayerTemplate FactionWild\r\n"
    "\tPlayableSide = Yes\r\n"
    "\tInitialUpgrades = Upgrade_WildFaction Upgrade_SomethingElse\r\n"
    "\tBuildableHeroesMP = CreateAHero HeroC // HeroZ\r\n"
    "\tBuildableRingHeroesMP = DarkLord_RingHero\r\n"
    "End\r\n"
    "PlayerTemplate FactionTest\r\n"
    "\tPlayableSide = No\r\n"
    "\tBuildableHeroesMP = CreateAHero HeroQ\r\n"
    "End\r\n"
)
UNITS = (
    "Object MordorBalrog\r\n"
    "\tDraw = W3DScriptedModelDraw ModuleTag_Draw\r\n"
    "\t\tModelConditionState = NONE\r\n"
    "\t\tEnd\r\n"
    "\tEnd\r\n"
    "\tKindOf = HERO SELECTABLE MONSTER SUMMONED\r\n"
    "\tBehavior = LifetimeUpdate ModuleTag_LifetimeUpdate\r\n"
    "\t\tMinLifetime = 1\r\n"
    "\tEnd\r\n"
    "End\r\n"
    "\r\n"
    "; a comment\r\n"
    "Object SomethingElse\r\n"
    "End\r\n"
)
SETS = ("CommandSet WildFortressCommandSet\r\n  14 = Command_RingHeroReviveSlot\r\n  16 = Command_GenericReviveSlot1\r\n"
        "  17 = Command_GenericReviveSlot2\r\n  18 = Command_GenericReviveSlot3 ; note\r\nEnd\r\n")
LEVELS = (
    "ExperienceLevel Monster\r\n\tTargetNames = MordorBalrog SomethingElse\r\n\tRank = 2\r\nEnd\r\n"
    "ExperienceLevel Monster\r\n\tTargetNames = MordorBalrog\r\n\tRank = 9\r\n\tSelectionDecal\r\n\t\tTexture = x\r\n\tEnd\r\nEnd\r\n"
)
GAMEDATA = (
    "#define SOME_HEALTH 400\r\n"
    "#define GENERIC_FORTRESS_COMMAND_POINT_BONUS\t\t100\r\n"
    "#define GENERIC_FARM_COMMAND_POINT_BONUS 30 ; farms\r\n"
    "GameData\r\n"
    "  GoodCommandPoints \t= 100 150\r\n"
    "  EvilCommandPointsBonus = 50 \r\n"
    "  GoodCommandPointsMP2 \t= 100 1000\t\t; 2 players\r\n"
    "  MaxCommandPointsX = 7\r\n"
    "  MultiPlayUnitSpeedMult =\t\tMP1:1.0\t\tMP2:0.5\r\n"
    "  MultiPlayBuildingSpeedMult =\tMP1:2.0\tMP2:1.0\r\n"
    "End\r\n"
)
PIT = "Object Pit\r\n\tCommandPointBonus\t\t= 10; BALANCE\r\nEnd\r\n"
FORT = "Object Fort\r\n\tCommandPointBonus = GENERIC_FORTRESS_COMMAND_POINT_BONUS\r\nEnd\r\n"
HEROES = (
    "Object HeroA\r\n\tBehavior = AIUpdate ModuleTag_AI\r\n\t\tX = 1\r\n\tEnd\r\nEnd\r\n"
    "ChildObject HeroB HeroA\r\n\tSide = Men\r\nEnd\r\n"
)
HERO_C = "Object HeroC ;BALANCE\r\n\tBody = ActiveBody ModuleTag_Body\r\n\tEnd\r\nEnd\r\n"
BUTTONS = ("CommandButton Command_Other\r\n\tOptions = NEED_UPGRADE\r\nEnd\r\n"
           "CommandButton Command_RingHeroReviveSlot\r\n\tCommand = REVIVE\r\n\tOptions\t\t= HIDE_WHILE_DISABLED NEED_UPGRADE CANCELABLE\t;Hides\r\n"
           "\tNeededUpgrade = Upgrade_RingHero\r\nEnd\r\n")
SYSTEM = ("Object EvilBook\r\n\tBehavior = BuildableHeroListUpgrade BitsUpgrade\r\n\t\tTriggeredBy = Upgrade_RingHero\r\n\tEnd\r\nEnd\r\n"
          "Object GoodBook\r\n\tBehavior = BuildableHeroListUpgrade BitsUpgrade\r\n\t\tTriggeredBy = Upgrade_RingHero ; ring\r\n\tEnd\r\nEnd\r\n")
DARK = "Object DarkLord\r\n\tRecruitText = CONTROLBAR:DarkRecruit\r\nEnd\r\nChildObject DarkLord_RingHero DarkLord\r\nEnd\r\n"
QUEEN = "Object GoodQueen\r\n\tRecruitText = CONTROLBAR:QueenRecruit\r\nEnd\r\nChildObject GoodQueen_RingHero GoodQueen\r\nEnd\r\n"
STRINGS = ('CONTROLBAR:DarkRecruit\r\n"Use the One Ring to summon the Dark One"\r\nEND\r\n\r\n'
           'CONTROLBAR:QueenRecruit\r\n// context\r\n"Use the One Ring to summon the Queen"\r\nEND\r\n'
           'OTHER:Label\r\n"Use the One Ring to summon nobody"\r\nEND\r\n')


def _install(tmp_path: Path) -> tuple[Path, Path]:
    rotwk = tmp_path / "RotWK"
    rotwk.mkdir()
    mk.write_big(rotwk / "INI.big", [
        ("data\\ini\\PlayerTemplate.ini", TEMPLATE.encode()), ("data\\ini\\commandset.ini", SETS.encode()),
        ("data\\ini\\experiencelevels.ini", LEVELS.encode()), ("data\\ini\\gamedata.ini", GAMEDATA.encode()),
        ("data\\ini\\commandbutton.ini", BUTTONS.encode()),
        ("data\\ini\\object\\neutral\\neutralunits.ini", UNITS.encode()), ("data\\ini\\object\\neutral\\pit.ini", PIT.encode()),
        ("data\\ini\\object\\good\\fort.ini", FORT.encode()), ("data\\ini\\object\\good\\heroes.ini", HEROES.encode()),
        ("data\\ini\\object\\wild\\heroc.ini", HERO_C.encode()), ("data\\ini\\object\\system\\system.ini", SYSTEM.encode()),
        ("data\\ini\\object\\evilfaction\\units\\mordor\\sauron.ini", DARK.encode()),
        ("data\\ini\\object\\goodfaction\\units\\elven\\galadriel.ini", QUEEN.encode())])
    mk.write_big(rotwk / "English.big", [("data\\lotr.str", STRINGS.encode())])
    policy = tmp_path / "policy.json"
    policy.write_text(json.dumps({"archives": [{"path": "ini.big"}, {"path": "english.big"}]}))
    return rotwk, policy


# ---- the pieces ----

def test_playable_factions_and_heroes():
    assert mim.playable_factions(TEMPLATE) == ["FactionMen", "FactionWild"]
    assert mim.playable_heroes(TEMPLATE) == ["HeroA", "HeroB", "HeroC"]
    assert mim.faction_upgrades(TEMPLATE) == ["Upgrade_MenFaction", "Upgrade_WildFaction"]


def test_balrog_text():
    text = mim.balrog_text(TEMPLATE, UNITS, SETS, LEVELS)
    lines = text.split("\r\n")
    assert lines[3:12] == ["ChildObject WildBalrog MordorBalrog", "\tSide\t\t\t= Wild", "\tBuildCost\t\t= 5000", "\tBuildTime\t\t= 60",
                           "\tRecruitText\t\t= CONTROLBAR:SummonBalrog", "\tReviveText\t\t= CONTROLBAR:SummonBalrog",
                           "\tKindOf\t\t\t= HERO SELECTABLE MONSTER", "\tRemoveModule ModuleTag_LifetimeUpdate", "End"]
    assert "PlayerTemplate FactionWild\r\n\tBuildableHeroesMP\t= CreateAHero HeroC WildBalrog\r\nEnd" in text
    # the one level block that targets the Balrog alone, renamed and retargeted, its nested block kept
    assert "ExperienceLevel WildBalrog\r\n\tTargetNames = WildBalrog\r\n\tRank = 9\r\n\tSelectionDecal\r\n\t\tTexture = x\r\n\tEnd\r\nEnd\r\n" in text
    assert text.endswith("\r\n")


def test_balrog_needs_room_and_the_summoned_balrog():
    full = SETS.replace("  17 = Command_GenericReviveSlot2\r\n  18 = Command_GenericReviveSlot3 ; note\r\n", "")
    with pytest.raises(mk.ModError, match="has 1 hero slots and FactionWild already fills 1"):
        mim.balrog_text(TEMPLATE, UNITS, full, LEVELS)
    with pytest.raises(mk.ModError, match="KindOf is not the spell book Balrog's"):
        mim.balrog_text(TEMPLATE, UNITS.replace(" SUMMONED", ""), SETS, LEVELS)
    with pytest.raises(mk.ModError, match="no LifetimeUpdate"):
        mim.balrog_text(TEMPLATE, UNITS.replace("LifetimeUpdate ModuleTag_LifetimeUpdate", "Other ModuleTag_X"), SETS, LEVELS)


def test_double_gamedata_changes_only_the_command_point_lines():
    out, defines, pairs = mim.double_gamedata(GAMEDATA)
    assert (defines, pairs) == (2, 3)
    before, after = GAMEDATA.splitlines(keepends=True), out.splitlines(keepends=True)
    changed = {i: after[i] for i in range(len(before)) if before[i] != after[i]}
    assert changed == {1: "#define GENERIC_FORTRESS_COMMAND_POINT_BONUS\t\t200\r\n", 2: "#define GENERIC_FARM_COMMAND_POINT_BONUS 60 ; farms\r\n",
                       4: "  GoodCommandPoints \t= 200 300\r\n", 5: "  EvilCommandPointsBonus = 100 \r\n",
                       6: "  GoodCommandPointsMP2 \t= 200 2000\t\t; 2 players\r\n"}


def test_double_literal_bonuses_keeps_the_spacing():
    assert mim.double_literal_bonuses(PIT) == ("Object Pit\r\n\tCommandPointBonus\t\t= 20; BALANCE\r\nEnd\r\n", 1)
    assert mim.double_literal_bonuses(FORT) == (FORT, 0)  # a define: gamedata.ini doubles it


def test_rapid_text():
    assert mim.rapid_text(GAMEDATA).split("\r\n")[3:7] == [
        "GameData", "\tMultiPlayUnitSpeedMult = MP1:0.25\tMP2:0.125", "\tMultiPlayBuildingSpeedMult = MP1:0.5\tMP2:0.25", "End"]


def test_add_level_module_goes_before_the_heros_own_end():
    out = mim.add_level_module(HEROES, "HeroA")
    lines = out.split("\r\n")
    assert lines[3:9] == ["\tEnd", "\tBehavior = ExperienceLevelCreate ModuleTag_VeteranHeroesLevel\t; VeteranHeroes (OpenBFME Mods folder): start at level 5",
                          "\t\tLevelToGrant\t= 5", "\t\tMPOnly\t\t\t= No", "\tEnd", "End"]
    assert out.replace("".join(l + "\r\n" for l in mim.veteran_module()), "") == HEROES
    with pytest.raises(mk.ModError, match="already has an ExperienceLevelCreate"):
        mim.add_level_module(out, "HeroA")


def test_find_object_block_refuses_what_it_does_not_understand():
    lines = mk.lines_of("Object A\r\n\tX = 1\r\nEnd\r\nWeapon Stray\r\nEnd\r\n; c\r\nObject B\r\nEnd\r\n")
    with pytest.raises(mk.ModError, match="line 4 \\('Weapon Stray'\\) starts a block of its own"):
        mk.find_object_block(lines, "A")
    with pytest.raises(mk.ModError, match="line 4 \\('X = 2'\\) stands between its End and the next object"):
        mk.find_object_block(mk.lines_of("Object A\r\nEnd\r\n\r\nX = 2\r\n"), "A")
    assert mk.find_object_block(lines, "B") == (6, 7, "Object", "")
    with pytest.raises(mk.ModError, match="there is no Object C"):
        mk.find_object_block(lines, "C")


def test_dark_lords_pieces():
    out = mim.ring_slot_without_upgrade(BUTTONS)
    assert "\tOptions\t\t= HIDE_WHILE_DISABLED CANCELABLE\t;Hides\r\n" in out
    assert out.count("NEED_UPGRADE") == 1  # Command_Other keeps its own
    text, n = mim.hero_list_triggers(SYSTEM, ["Upgrade_MenFaction", "Upgrade_WildFaction"])
    assert n == 2
    assert "\t\tTriggeredBy = Upgrade_RingHero Upgrade_MenFaction Upgrade_WildFaction\r\n" in text
    assert "\t\tTriggeredBy = Upgrade_RingHero Upgrade_MenFaction Upgrade_WildFaction ; ring\r\n" in text
    with pytest.raises(mk.ModError, match="not retail's Upgrade_RingHero"):
        mim.hero_list_triggers(text, ["Upgrade_MenFaction"])
    s = mim.summon_text(STRINGS, ["CONTROLBAR:DarkRecruit", "CONTROLBAR:QueenRecruit"])
    assert '"Summon the Dark One"\r\n' in s and '"Summon the Queen"\r\n' in s and '"Use the One Ring to summon nobody"' in s
    with pytest.raises(mk.ModError, match="has no CONTROLBAR:Missing"):
        mim.summon_text(STRINGS, ["CONTROLBAR:Missing"])


def test_check_independent():
    mim.check_independent({"A": ["data\\ini\\x.ini"], "B": ["data\\ini\\y.ini"]})
    with pytest.raises(mk.ModError, match="B and A both change data/ini/X.ini"):
        mim.check_independent({"A": ["data\\ini\\x.ini"], "B": ["data/ini/X.ini"]})
    with pytest.raises(mk.ModError, match="A and SauronAtTheFortress both change"):
        mim.check_independent({"A": ["DATA\\INI\\PlayerTemplate.ini"]})


# ---- end to end on the made-up install ----

def test_make_all_five(tmp_path):
    rotwk, policy = _install(tmp_path)
    made = mim.make(rotwk, tmp_path / "out", list(mim.MODS), policy)
    assert {n: r["files"] for n, r in made.items()} == {
        "BalrogUnleashed": ["data\\ini\\object\\zzmods\\balrogunleashed.ini"],
        "DoubleArmy": ["data\\ini\\gamedata.ini", "data\\ini\\object\\neutral\\pit.ini"],
        "RapidBuild": ["data\\ini\\object\\zzmods\\rapidbuild.ini"],
        "VeteranHeroes": ["data\\ini\\object\\good\\heroes.ini", "data\\ini\\object\\wild\\heroc.ini"],
        "DarkLordsForAll": ["data\\ini\\commandbutton.ini", "data\\ini\\object\\system\\system.ini", "data\\lotr.str"]}
    for n in mim.MODS:
        folder = tmp_path / "out" / n
        assert sorted(p.name for p in folder.iterdir()) == [n + ".big", "mod.txt"]
        assert (folder / "mod.txt").read_text() == f"Title = {mim.MODS[n].title}\nDescription = {mim.MODS[n].description}\n"
    # HeroB is a ChildObject of HeroA (a patched hero): it inherits the module, so only HeroA's and HeroC's blocks change
    big = tmp_path / "out" / "VeteranHeroes" / "VeteranHeroes.big"
    data = big.read_bytes()
    heroes = {name: data[off:off + size].decode() for name, off, size in mk.read_big_index(big)}
    assert heroes["data\\ini\\object\\good\\heroes.ini"].count("ExperienceLevelCreate") == 1
    assert heroes["data\\ini\\object\\wild\\heroc.ini"].count("ExperienceLevelCreate") == 1


def test_the_cli(tmp_path):
    r = subprocess.run([sys.executable, str(TOOL), "--rotwk", str(tmp_path), "--out", str(HERE), "all"], capture_output=True, text=True, timeout=60)
    assert r.returncode == 2 and "inside the repository" in r.stderr, r.stderr
    r = subprocess.run([sys.executable, str(TOOL), "--rotwk", str(tmp_path), "--out", str(tmp_path / "o"), "NoSuchMod"], capture_output=True, text=True,
                       timeout=60)
    assert r.returncode == 2 and "unknown mod NoSuchMod" in r.stderr, r.stderr
