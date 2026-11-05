# Retail mod compatibility (lane MODCOMPAT-1)

Goal (owner, 2026-10-28): every retail RotWK mod works in OpenBFME as it does in retail RotWK 2.01, including its own menus and movies.
Mods are data for the retail engine, so the way there is the retail engine itself: every gap a mod finds is a retail code path that is not
ported yet, ported from the decomp with its RW evidence like any other retail behaviour. A mod that ships its own game program (Edain
Unchained's `game.dat`, Age of the Ring) is the exception: its program's changes are decoded and rebuilt as named features
(docs/MODS.md, "Mods that change the game program").

## How progress is measured

1. **The gap census** (`tools/mod/gap_census.py`, `logs/mod-gap-census.md`): one headless skirmish per All In One package; the unported
   modules, script actions and conditions each game ran into, ranked by how many packages hit them, and (the static side, which sizes a
   module port) every object template of the mod whose behavior modules name an unported class. The porting lanes take it top-down.
2. **The per-mod checklist** below, against retail RotWK 2.01 running the same mod on a Windows machine (the reference captures). A mod is
   compatible when every row passes.

## The per-mod checklist

For each mod (its All In One package, or its `-mod` folder), with the same files in retail and in OpenBFME:

| # | Check | Retail reference | OpenBFME | Pass when |
|---|---|---|---|---|
| 1 | It mounts | the mod's files in the game folder / `-mod` | `--mod-install` / `--mod` (the launcher's Play) | no mount error; the identity names the mod |
| 2 | Its data loads | retail's own load | the start log's INI messages | every message is one retail also hits (the mod's own data bugs), none ours |
| 3 | The intro movies | a capture of the start-up from launch to the main menu | the same start-up | the same movies in the same order (the mod's own where it has them), with sound |
| 4 | The main menu | a screenshot of the main menu after its intro | the same | the same layout, text, images and background movie |
| 5 | Every shell screen | a screenshot of each screen reached from the main menu: skirmish setup, options, multiplayer / LAN, the campaign menus, the mod's own screens | the same | each screen matches: buttons, lists, text, images; every button leads where retail's does |
| 6 | A skirmish | a skirmish on a map the mod ships or a retail map it supports, each of its factions once | the same setup | it starts; the factions, heroes, buildings and spell book are the mod's; 3000 frames against a hard computer player run without an error or a stop the mod causes |
| 7 | Two players | a LAN game of two copies with the mod | two peers with the mod | the lobby accepts both; 3000 frames in lockstep (0 desyncs) |
| 8 | The in-game interface | screenshots of the control bar, the build menus, the hero bar (Edain Unchained's), the palantir | the same | the same buttons, icons, tooltips and counters |
| 9 | A save and a load | a skirmish saved and loaded | the same | the loaded game continues; OpenBFME's loaded game hashes as the uninterrupted one |
| 10 | Its maps | each map the mod adds, loaded in a skirmish | the same | every map starts and its scripts run |

A row that fails names the gap: the retail function (RW address) it needs, or the mod program change it needs. It goes on the census list.

## The order

1. Movies and menus first (what a player sees first): the mod's intro and menu movies (fixed: a mod's `Data\Movies`, and an install-folder
   mod's movies, which retail has in its game folder), then each shell screen against the retail screenshots.
2. Then the census list top-down, by how many mods each gap reaches: the AI's script actions and conditions, the unported modules.
3. Age of the Ring: its game program decoded (a function-by-function comparison with retail 2.01's) and each change rebuilt as a feature.

Mods covered first: Edain 4.8.5.3, Edain Unchained 4.4.3, then the rest of the All In One RotWK packages, then Age of the Ring.

## Edain 4.8.5.4 on macOS with the Mobile renderer (lane IOS-31, 2026-11-05)

The All In One package `0ff0ab7a` laid out by `tools/mod/aio_package.py` (38 files, every MD5 as the service lists it; 6.2 GB on disk: some
archives are listed with Size 0), turned on in the Mods folder (Options › Mods) and also mounted with `--mod-install`. No retail capture was
made, so a row "passes" here only as far as OpenBFME's own checks go; the retail reference captures are still to do.

| # | Check | Result |
|---|---|---|
| 1 | It mounts | yes: 14 archives in RotWK's load order, `lang\English.big` and `lang\englishpatch201.big` included; identity `mod install Edain`; no engine edits (no `game.dat`) |
| 2 | Its data loads | 11202 object templates, 9 playable factions, 2 INI messages: `ExperienceLevels.ini` (macro `SUMMONED_HERO_WEAK` has no value) and `RiskCampaign.ini` (Living World `WorldText`, S-1321) |
| 3 | The intro movies | the package has no `edainintro.vp6` (Edain's `Overall_Game_Intro`) and names no logo movies ("None"): nothing plays, as the package would in retail |
| 4 | The main menu | Edain's menu (SOLO PLAY / MULTIPLAYER / OPTIONS / MY HEROES / QUIT) over the rune background: the package's shell maps ship disabled (`*.big.bak`) |
| 5 | Every shell screen | MODUI-1: 87 Apt movies load, 0 failed; the MENU-1 walk 28 ok, 1 failed, nothing beyond 2.01's own failure (LAN's `LastLanLobbyScreen` extern) |
| 6 | A skirmish | starts with Edain's factions (Gondor, Dwarves, Misty Mountains, Angmar ...), castles and build plots; a 12-minute 4-player game of hard computer players ran to its end with no script error and no crash (64 W3D model messages: Edain models' missing textures and sub objects, presentation only; the same game unmodded: 12); the gap census (3000 frames) hit `AimWeaponBehavior` (10 objects), `LocomotorSetUpgrade` (4), `RubbleRiseUpdate` (2), `EvacuateDamage` (1); 57 unported module classes appear in Edain's templates (AimWeaponBehavior 86 templates, EvacuateDamage 67, TooltipUpgrade 57 ...) |
| 7 | Two players | not run (Mods-folder mods keep LAN and online off; `--mod-install` LAN not tried) |
| 8 | The in-game interface | the Palantir, the keep's and the build plots' radial menus show Edain's buttons; the QA bot cannot build Edain's plot economy (it looks for retail's side bar), so its scripted Gondor lost after 5 minutes |
| 9 | A save and a load | not run |
| 10 | Its maps | the lobby lists 246 maps with Edain's; Fords of Isen II, Udun and Fall Back 4p played; Edain's own maps not tried one by one |

`edainfactions1_test.gd` (written for 4.8.5.3): each clan choice (Erebor, Iron Hills, Ered Luin) and the Dwarven AI pass when their game
command runs on its own; inside the test's wrapper the keep is often not picked ("no clickable keep") and one AI child exited 134 once, which
did not happen again: a harness flake to look at, not a 4.8.5.4 difference (the clan buttons and upgrades have the 4.8.5.3 names).

Memory and frame times, the same 10-minute 4-player game (Udun, hard computer players, the camera on the computer unit farthest from its
base) on an M2 Max with the Mobile renderer in a 1335×939 window, `--gpu-probe --perf`:

| | RotWK 2.01 | Edain 4.8.5.4 | Edain, Texture Quality Medium (reduction 1) |
|---|---|---|---|
| video memory, peak (after 6 min) | 638 MB (585 MB) | 673 MB (658 MB) | 649 MB in its 6 min (597 MB where Edain at full textures had 645 MB) |
| process memory (RSS), peak | 1.70 GB | 2.36 GB | 2.29 GB |
| objects, peak | 590 | 952 | 893 |
| frame time p95 / p99, mean of the 5 s windows | 10.2 / 15.2 ms | 11.9 / 17.1 ms | 10.9 / 16.5 ms |
| frame rate (display cap 120) | 116 | 115 | 116 |

## Edain 4.8.5.4 on touch (lane IOS-39, 2026-11-05)

The owner's first Edain play on the iPhone Duo (oval Palantir, no selection rings, the vine's buttons, building on castle plots), worked on the
Mac stand-in (`--rendering-method mobile --touch`, 1335×939 and 939×1335, HUD size 125 %, Edain turned on in the Mods folder). "Ours" is
OpenBFME's code (shared with upstream unless marked OpenBFME presentation); "Edain's" is the mod's data, which retail runs the same way.

| Finding | Whose | What was done |
|---|---|---|
| **No selection rings, no veterancy.** Edain's `includes\experiencelevels.inc` has `#define SUMMONED_HERO_WEAK` and `_STRONG` with nothing after the name. The port's #define pass threw "has no value" on them, which drops the whole `ExperienceLevels.ini`: Edain ran with no experience level at all, so no rank, no level bonus and no `SelectionDecal` (the ring is the level's decal). | ours (a port error) | Fixed as retail: RotWK's pass reads "#define" into the value's buffer first and `AsciiString::nextToken` leaves its token alone on an empty rest (RW 0x42D106 .. 0x42D1BC, 0x4366DC -> 0x436783), so such a macro's value is "#define" and the file loads. Edain's start log now has one INI message (RiskCampaign.ini), not two. Test: `#define: empty value ...` (test_ini_macro.cpp). |
| **The oval Palantir.** `___edain_apt_widescreen.big` (first in RotWK's load order, so retail uses it too) ships a widescreen build of `Palantir.apt`: every top-level clip is placed at x 0.75 about its screen edge, so retail's stretch of the 4:3 stage to 16:9 draws it round. Our layout (`AptPalantir::setViewportSize`, upstream's widescreen correction and the HUD size) already draws the HUD round, and narrowed Edain's build a second time: x / y about 0.70 on the Duo. The round-HUD guard missed it (it took the top-level clips' own matrices as uniform). | ours (OpenBFME presentation) | `AptUniformHud::widescreenBuild` measures the build's factor from the structure (the median x / y of the top-level clips: 1 for RotWK's movies, 0.75 for Edain's) and the layout undoes it about each clip's group anchor before its own transform; the rule's correction and audit count it. Groups by RotWK's clip names, else (a mod's own clip) by where the clip stands. RotWK's layout is unchanged. Guard: `hud2 palantir: a widescreen build of the movie ...` (RotWK's movie squeezed like Edain's: same boxes, round, hit test, landscape / portrait / 4:3, 100 and 125 %). Screenshots `night4-hud-round-*.png`. |
| **The vine's buttons** (+, −, barrel, map) | Edain's | Edain's spell book (`GondorSpellBookCommandSet`, the SpellBookUI vine, RotWK's `InGameSpellBook.apt`): `Command_SpellBookGeneralView` / `UnitView` (+ / −: the camera's view distance, "Sichtweite"), `Command_SpellBookDecomission` (the barrel: dismiss units at a target), `Command_SpielsystemGondor` (the map: NONPRESSABLE, its help explains the faction's game system); bought powers join them (the horn). They are the vine's own buttons, so they were already round and scaled with the Palantir (SpellBookUI is laid out by IOS-27) and a held finger shows their help as for any power. Nothing to change. |
| **Building on castle plots.** A plot is `GondorBuildingFoundation` (KindOf BASE_FOUNDATION EXPANSION_PAD, a W3DFloorDraw plus a picked model) with `GondorFoundationCommandSet`: eleven `FOUNDATION_CONSTRUCT` buttons, all `Radial = Yes`. A tap selects the plot and its bubbles ring it (round, 11 of them); a tap on a bubble builds. The scripted QA player could not: it pressed buttons on the Palantir or the side bar only, and the control bar lists radial buttons with the side bar's, which is hidden while the bubbles show (`button_window_missing`). | ours (the QA harness) | `qa_player.gd` presses a button on its bubble when one shows it. A 4-minute Edain QA game now builds on its plots (a well) and buys castle upgrades; screenshots `night4-plot-radial-bubbles.png`, `night4-plot-built-well.png`. |
| **Rings on Edain's castle floor.** On open ground the rings show (`night4-rings-terrain-landscape.png`, `night4-rings-hud-portrait.png`); on the castle's floor (`GBCastleFloor`, a W3DFloorDraw model laid over the terrain) they do not (`night4-rings-castle-floor-gap.png`): the device draws merge decals in the terrain shader and on KINDOF WALK_ON_TOP_OF_WALL models only (SELWALL-1), and the floor covers the terrain. | ours, open | How retail draws a projected decal over a floor draw was not read (S-2522). Making floor models decal receivers (`|sel`) was tried and is not enough (the floor's material path draws none). Next step: read W3DFloorDraw's render (its draw order / `ForceToBack`) and the projected-shadow pass's receivers. RotWK's own fortress floors have the same gap. |
| **Save and load with Edain.** `--save-test` on Evendim and on Edain's Trollshaws: the save is refused at load ("loads with state hash X ... the save recorded Y"); the same build saves and loads RotWK. Not caused by the #define fix (the same refusal with it reverted). | ours (upstream), open | Some state an Edain object holds is in the state hash but not in the snapshot. Next: bisect with `GameLogic::setSnapshotModuleFilter` over Edain's module classes (the 57 unported / Edain-only ones first). |
| Edain's maps | — | `map edain archet` (castles, plots, QA game), `map edain trollshaws` (to the save), `map edain ford of bruinen` (portrait, 40 s): start and run, no script error. The map list's picture of Ford of Bruinen is a colour-mapped TGA, which the preview does not draw (an unported image type, ours). |
| Edain's menus by touch | — | `--menu1-walk --touch` with Edain: the main menu, the campaign difficulty, the skirmish's profile prompt and lobby (246 maps), Options and LAN pass; the walk's other steps look for RotWK's button names (MultiPlayNav.Online, SoloPlayNav.LoadGame, MyHeroes ...), which Edain's main menu renames: a walk script limit, not a touch one. |
| Small mods with Edain | ours (OpenBFME) | Allowed (2026-11-05); the Mods tab now warns: the Status row says "2 mods, with a warning", and the note, the row's help and the small mod's help say that its files replace Edain's where both have one. |
| Two copies on LAN | — | Not run: Mods-folder mods keep LAN off by design; a LAN check needs two `--mod-install` peers (`--lan=host|join --lan-targets=127.0.0.1`), left for a later night. |
