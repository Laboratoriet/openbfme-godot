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
