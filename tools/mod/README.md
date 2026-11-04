# Mod tools

- `asset_pack_from_big.py`: a mod archive's models and textures as an asset pack (lane SDK-1, `docs/MODS.md`).
- `aio_package.py`, `gap_census.py`: All In One launcher packages and the mod compatibility census (lanes MODS-2, MODCOMPAT).
- `make_sauron_mod.py`: the "Sauron at the fortress" test mod for the Mods folder (lane IOS-28), made from **your own** game files.

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
