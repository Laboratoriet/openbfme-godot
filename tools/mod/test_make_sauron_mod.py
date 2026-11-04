"""Lane IOS-28: tools/mod/make_sauron_mod.py on a made-up install (no game bytes: every INI line here is invented for the test)."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
TOOL = HERE / "make_sauron_mod.py"
_spec = importlib.util.spec_from_file_location("make_sauron_mod", TOOL)
msm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(msm)

TEMPLATE = (
    "PlayerTemplate FactionMen\r\n"
    "\tBuildableHeroesMP = CreateAHero HeroA HeroB\r\n"
    "End\r\n"
    "\r\n"
    "PlayerTemplate FactionMordor\r\n"
    "\tSide = Mordor\r\n"
    "\tBuildableHeroesMP\t\t= CreateAHero EvilA EvilB ;// EvilC\r\n"
    "\tBuildableRingHeroesMP = MordorSauron_RingHero\r\n"
    "End\r\n"
)
SAURON = "Object MordorSauron\n  BuildCost = 1\nEnd\nChildObject MordorSauron_RingHero MordorSauron\nEnd\n"
SETS = "CommandSet MordorFortressCommandSet\n  15 = Command_RingHeroReviveSlot\n  17 = Command_GenericReviveSlot1\n  18 = Command_GenericReviveSlot2\n" \
       "  19 = Command_GenericReviveSlot3 // a note\nEnd\n"


def test_add_hero_changes_one_line_and_keeps_the_rest():
    out = msm.add_hero(TEMPLATE)
    assert out.splitlines(keepends=True)[6] == "\tBuildableHeroesMP\t\t= CreateAHero EvilA EvilB MordorSauron ;// EvilC\r\n"
    before, after = TEMPLATE.splitlines(keepends=True), out.splitlines(keepends=True)
    assert len(before) == len(after) == 9
    assert [i for i in range(9) if before[i] != after[i]] == [6]
    assert msm.heroes_of(out) == ["CreateAHero", "EvilA", "EvilB", "MordorSauron"]
    assert msm.heroes_of(out, "FactionMen") == ["CreateAHero", "HeroA", "HeroB"]


def test_add_hero_twice_is_refused():
    with pytest.raises(msm.ModError, match="already lists MordorSauron"):
        msm.add_hero(msm.add_hero(TEMPLATE))


def test_a_missing_faction_or_line_is_an_error():
    with pytest.raises(msm.ModError, match="there is no PlayerTemplate FactionMordor"):
        msm.add_hero("PlayerTemplate FactionMen\nEnd\n")
    with pytest.raises(msm.ModError, match="has no BuildableHeroesMP"):
        msm.add_hero("PlayerTemplate FactionMordor\n Side = Mordor\nEnd\n")


def test_generic_slots_counts_the_fortress_hero_slots():
    assert msm.generic_slots(SETS) == 3


def _install(tmp_path: Path, template: str = TEMPLATE) -> tuple[Path, Path]:
    """a made-up RotWK folder: a patch archive that wins commandset.ini and an INI archive under it, with its own policy"""
    rotwk = tmp_path / "RotWK"
    rotwk.mkdir()
    msm.write_big(rotwk / "_patch.big", [("data\\ini\\commandset.ini", SETS.encode())])
    msm.write_big(rotwk / "INI.big", [("data\\ini\\commandset.ini", b"CommandSet Nothing\nEnd\n"),
                                       ("data\\ini\\PlayerTemplate.ini", template.encode("latin-1")),
                                       ("data\\ini\\object\\evilfaction\\units\\mordor\\sauron.ini", SAURON.encode())])
    policy = tmp_path / "policy.json"
    policy.write_text(json.dumps({"archives": [{"path": "_patch.big"}, {"path": "ini.big"}]}))
    return rotwk, policy


def test_make_writes_the_mod_folder(tmp_path):
    rotwk, policy = _install(tmp_path)
    r = msm.make(rotwk, tmp_path / "out", policy)
    folder = tmp_path / "out" / "SauronAtTheFortress"
    assert sorted(p.name for p in folder.iterdir()) == ["SauronAtTheFortress.big", "mod.txt"]
    assert r["from"] == "INI.big" and r["slots"] == 3
    index = msm.read_big_index(folder / "SauronAtTheFortress.big")
    assert [(n, s) for n, _, s in index] == [("data\\ini\\PlayerTemplate.ini", len(msm.add_hero(TEMPLATE)))]  # the archive's own spelling
    data = (folder / "SauronAtTheFortress.big").read_bytes()
    _, off, size = index[0]
    assert data[off:off + size].decode("latin-1") == msm.add_hero(TEMPLATE)
    assert data[4:8] == len(data).to_bytes(4, "little")
    assert (folder / "mod.txt").read_text() == "Title = Sauron at the fortress\n" \
        "Description = Mordor can recruit Sauron at its fortress' hero menu for 10,000, without the One Ring.\n"


def test_no_room_in_the_hero_menu_is_an_error(tmp_path):
    rotwk, policy = _install(tmp_path, TEMPLATE.replace("EvilA EvilB", "EvilA EvilB EvilC"))
    with pytest.raises(msm.ModError, match="has 3 hero slots and FactionMordor already fills 3"):
        msm.make(rotwk, tmp_path / "out", policy)


def test_the_cli_refuses_an_output_inside_the_repository(tmp_path):
    r = subprocess.run([sys.executable, str(TOOL), "--rotwk", str(tmp_path), "--out", str(HERE)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 2 and "inside the repository" in r.stderr, r.stderr
