# Mod tools

- `asset_pack_from_big.py`: a mod archive's models and textures as an asset pack (lane SDK-1, `docs/MODS.md`).
- `aio_package.py`, `gap_census.py`: All In One launcher packages and the mod compatibility census (lanes MODS-2, MODCOMPAT).
- `make_sauron_mod.py`: the "Sauron at the fortress" test mod for the Mods folder (lane IOS-28), made from **your own** game files.
- `make_ini_mods.py`: five more small INI mods for the Mods folder (lane IOS-30), from your own game files too.
- `modkit.py`: what the two share (the RotWK archives in the game's order, the BIGF writer, line edits that keep every other byte, the mod folder).

## Sauron at the fortress

Mordor recruits Sauron at its fortress like its other heroes, for 10,000, without the One Ring. The ring hero is untouched.

```sh
python3 tools/mod/make_sauron_mod.py --rotwk "<your RotWK 2.01 folder>" --out "<a folder outside the repository>" \
    [--copy-to "<OpenBFME's Mods folder>"]
```

`--rotwk` defaults to `ROTWK_INSTALL`. The tool reads `data\ini\playertemplate.ini` from the RotWK archives (the first archive in the
pinned 2.01 order that holds it, as the game mounts them), adds `MordorSauron` (the campaign's Sauron) to the end of `FactionMordor`'s
`BuildableHeroesMP`, and writes `<out>/SauronAtTheFortress/` with `SauronAtTheFortress.big` (that one file) and `mod.txt`. It checks that
`Object MordorSauron` exists and that the fortress' hero menu (`MordorFortressCommandSet`, seven hero slots) has room. Nothing else changes.

Then drop the `SauronAtTheFortress` folder into the Mods folder:
- **Mac / PC:** `Mods` in the RotWK user data folder (`--copy-to` does it; Options › Mods › OPEN shows where).
- **iPhone / iPad:** the Files app, On My iPhone › OpenBFME › Mods (AirDrop or Finder file sharing, then move it there).

Turn it on in Options › Mods, ACCEPT, restart, play Mordor in a skirmish: select the fortress, open its heroes bubble, and Sauron is the
last portrait.

The output holds bytes of your game files. Keep it to yourself and never commit it: the tool refuses an output folder inside the repository,
and the commit gate refuses `.big` files. Its test (`test_make_sauron_mod.py`) uses made-up INI text only.

## Five more INI mods (lane IOS-30)

```sh
python3 tools/mod/make_ini_mods.py --rotwk "<your RotWK 2.01 folder>" --out "<a folder outside the repository>" \
    [--copy-to "<OpenBFME's Mods folder>"] all          # or some of: BalrogUnleashed DoubleArmy RapidBuild VeteranHeroes DarkLordsForAll
```

| Mod | What it does | What it changes |
|---|---|---|
| BalrogUnleashed | The Goblins recruit the Balrog at their fortress (5,000, 60 s), his retail strength and rank 10, no time limit | adds `data\ini\object\zzmods\balrogunleashed.ini`: `ChildObject WildBalrog MordorBalrog` (Side, cost, recruit text, KindOf without SUMMONED, `RemoveModule ModuleTag_LifetimeUpdate`), `FactionWild`'s `BuildableHeroesMP` plus WildBalrog, his ExperienceLevel |
| DoubleArmy | Every command point limit x2 (two players: 200 + fortress 200 = 400 at the start, cap 2,000) | `gamedata.ini`: the five `*_COMMAND_POINT_BONUS` defines and the `{Good\|Evil}CommandPoints*` pairs; `hobbitworkpit.ini`'s literal bonus |
| RapidBuild | Units and buildings build four times faster in skirmish / multiplayer (30 s: 150 -> 35 frames) | adds `zzmods\rapidbuild.ini`: a GameData block with `MultiPlayUnitSpeedMult` / `MultiPlayBuildingSpeedMult` x 0.25 (merged over gamedata.ini) |
| VeteranHeroes | Every hero of the seven factions starts at level 5 | an `ExperienceLevelCreate` module (LevelToGrant 5) at the end of each of the 35 heroes' blocks (33 files) |
| DarkLordsForAll | Evil factions recruit Sauron, good ones Galadriel (the ring heroes: 10,000, level 10) without the One Ring | `system.ini`: the spell books' `BuildableHeroListUpgrade` also triggered by each `Upgrade_<side>Faction`; `commandbutton.ini`: `Command_RingHeroReviveSlot` without NEED_UPGRADE; `lotr.str`: "Summon the Dark Lord / the Storm Queen" |

**Combinations.** The Mods tab's rule is "a mod turned on later wins a whole file". No two of these six mods (with SauronAtTheFortress) hold
the same file, and the tool checks it, so every combination works in any order. Notes:
- DarkLordsForAll + SauronAtTheFortress: Mordor offers both Saurons, the campaign one in a hero slot and the ring hero in the ring slot.
- DoubleArmy leaves the Men marketplace's Grand Harvest (+100, `system.ini`) at retail: that file is DarkLordsForAll's.
- VeteranHeroes does not touch the ring heroes (level 10 already), Create-a-Hero or the Balrog (rank 10, his own ExperienceLevel).
- Ring heroes still drop the One Ring when they die (retail's ring hero).
- RapidBuild changes the skirmish / multiplayer factors only: upgrades and hero recruiting keep their times.

Verified on the Mac with `hud6_player.gd`'s modbalrog, modcp, modbuild, modlevel, moddarklords and modall scenarios. The output holds bytes of your
game files: keep it to yourself; the tool refuses an output folder inside the repository. Its test (`test_make_ini_mods.py`) uses made-up INI text only.
