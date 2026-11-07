# APT ↔ SWF converter

`openbfme_apt_swf` turns the game's Apt menu movies into standard SWF files. A movie is the set of files one menu BIG
carries: `<Movie>.apt`, `<Movie>.const`, `<Movie>.dat` and `<Movie>_geometry/*.ru`, plus the textures its image map names.

- Every movie of RotWK 2.01, BFME2 1.06 and the mods tried so far converts.
- JPEXS Free Flash Decompiler opens the SWF and decompiles every script to readable ActionScript; Ruffle plays it.
- The SWF also carries the original files in a private tag, so that it can be turned back into the same Apt files (the
  import, a separate change).

It is a tool, not part of the game library. It builds on the Apt player's own reader and decoder (`AptFile`,
`AptActionDecoder`). It reads the game's files at run time and writes only to the folder given with `--out`; nothing it
writes belongs in this repository (CONTRIBUTING.md, "The one rule").

## What the SWF holds and what it does not

The SWF is a compiled movie, as the Apt files are. With its private tag it holds all of the Apt data, but it cannot invent
what neither file has:

| | |
|---|---|
| **Kept exactly** | every byte of the original files (they ride along in a private tag); every record the SWF expresses: shapes as drawn, timelines, placements, buttons, text fields, labels, imports and exports, every action program |
| **Kept as an equivalent** | scripts: decompiled by JPEXS from the AVM1, so local names, comments and formatting are the decompiler's, not the author's; shapes: polygons, because `.ru` stores triangles (the original curves are gone) |
| **Not in the files at all** | the authoring source, the `.fla`: layer names, guides, folders, the library's symbol names, the ActionScript source text and its comments. JPEXS can export a converted SWF to FLA / XFL, which gives an editable project, not the original one |
| **Not converted yet** | glyph outlines (fonts are by name only; text renders in a substitute face), image characters placed directly, static text, morph shapes, sounds, video (each an empty placeholder sprite), the `.dat` image map's rectangle form |

## Build and run

The tool is a target of the engine's CMake project:

```sh
cmake --build engine/build --target openbfme_apt_swf
openbfme_apt_swf --help                 # the commands
openbfme_apt_swf help export            # a command's arguments and options
```

```sh
export ROTWK_INSTALL=... BFME2_INSTALL=...

openbfme_apt_swf export --game rotwk --movie Options --out out/options     # one movie: out/options/Options.swf
openbfme_apt_swf export --game rotwk --out out/rotwk                        # every movie, and out/rotwk/report.md
openbfme_apt_swf export --game rotwk --resolve-strings --out out/preview    # a preview: "$Label" texts as the game shows them
openbfme_apt_swf export --big <mod>/apt.big --out out/mod                   # a mod's movies (the game behind them when set)
openbfme_apt_swf info out/options/Options.swf                               # tags, text fields and named placements
```

Where the movies come from:

- `--game rotwk|bfme2` mounts the archives as the game does (`RetailArchivePolicy`; `rotwk` needs `ROTWK_INSTALL` and
  `BFME2_INSTALL`, `bfme2` needs `BFME2_INSTALL`); each movie is read from the archive that provides it.
- `--big ARCHIVE` (repeatable) converts every movie in the archives given. With the installs set, the game is mounted behind
  them: files a mod does not ship (a `.const` next to a replaced `.apt`, the textures) come from the game, as the game reads
  them. Without the installs, the archives are read alone; each movie's BIG carries its textures
  (`art/Textures/apt_<movie>_<n>.tga`), later archives win file by file.
- `--movie NAME` (repeatable) picks movies.

A `--resolve-strings` preview has no private tags: it is for looking at, not for going back to APT.

## The SWF

The SWF version is 6 for every movie: EA's runtime looks names up case-insensitively (`AptObject.h`: `_strcmpi` keys)
whatever the Apt version, SWF players are case-sensitive from version 7, and the menus rely on it (RotWK's buttons bind a
text field to `ButtonName` and set `buttonName`). The stage is the movie's size, the frame rate is 1000 / ms-per-frame. Apt
character ids stay the SWF character ids; characters the converter adds get ids above the movie's last one.

| Apt | SWF |
|---|---|
| shape (`.ru` styles `s` / `tc` / `l` with `t` triangles and `l` lines) | `DefineShape3`. Each `.ru` style group is a new style layer (`StateNewStyles`), drawn above the previous one as Apt draws its groups. Triangles are turned into outlines: every triangle is made clockwise, shared edges cancel, the rest is chained into loops (fill style 1) |
| textured style (`tc:r:g:b:a:img:m11:m12:m21:m22:tx:ty`) | clipped bitmap fill (0x41) of a `DefineBitsLossless2` (premultiplied ARGB from the TGA `apt_<movie>_<n>.tga` the `.dat` names); the fill matrix is 20 × the inverse of the `.ru` UV matrix (Apt maps shape pixels to texture pixels, SWF bitmap pixels to shape twips) |
| sprite, root timeline | `DefineSprite`; items in file order: `PlaceObject2`, `RemoveObject2`, `DoAction`, `FrameLabel`, `SetBackgroundColor`, then `ShowFrame` |
| place object | `PlaceObject2`: the flag bits are SWF's; matrix (16.16 / twips), tint and additive colour as `CXFORMWITHALPHA` (tint 255 = 256), ratio × 65536, name, clip depth, clip actions (the 24-bit event mask is SWF's `CLIPEVENTFLAGS` bit for bit) |
| init action | `DoInitAction` (root timeline) |
| button | `DefineButton2`: records with their state bits, matrix and colour multiply; the two condition bytes are Apt's transition mask and the low byte of `keyCode` (SWF's `key << 1 \| OverDownToIdle`, as `AptInput.cpp` reads it); Apt's hit mesh (the button's own triangles) becomes a shape that replaces the character of hit-only shape records |
| edit text | `DefineEditText`: bounds, font, height, colour, alignment, read-only / multiline / word-wrap, variable, initial text |
| font | `DefineFont2` with the name and no glyphs (a device font) |
| imports / exports | `ImportAssets2` (`<movie>.swf`) / `ExportAssets`, so converted movies load their shared symbols (MenuExport) from each other |
| image, static text, morph, sound, video, non-root movie | an empty one-frame sprite (no decoded layout yet) |

### Actions

APT keeps SWF's opcode numbers for the standard actions but stores operands differently, and adds EA opcodes. Every program
is decoded with `AptActionDecoder` and written as standard AVM1 (`AptSwfAvm1.h`):

- `PushData` and `ConstantPool` entries are resolved from the `.const` table into typed `Push` values and a string pool;
- each EA opcode becomes the standard sequence the interpreter runs for it (`AptActionInterpreter.cpp`):

| EA opcode | AVM1 |
|---|---|
| 0x59 / 0x5A PushZero / PushOne, 0xB5–0xB7 PushByte / Short / Long | `Push int` |
| 0xB4 PushFloat | `Push float` (the same 32 bits) |
| 0x73 / 0x74 PushTrue / False, 0x75 PushNull, 0x76 PushUndefined | `Push` boolean / null / undefined |
| 0x70 PushThisVar, 0x71 PushGlobalVar | `Push "this"` / `"_global"`, `GetVariable` |
| 0x72 ZeroVar | `Push 0`, `SetVariable` |
| 0x5B CallFuncPop, 0x5D CallMethodPop | `CallFunction` / `CallMethod`, `Pop` |
| 0x5E CallMethod (set-variable form) | `CallMethod`, `SetVariable` |
| 0xA1 PushString s, 0xA2 PushConstantByte i | `Push s`, `Push constant8 i` |
| 0xA4 / 0xA6 Get / SetStringVar s | `Push s`, `GetVariable` / `SetVariable` |
| 0xA5 / 0xA7 Get / SetStringMember s | `Push s`, `GetMember` / `SetMember` |
| 0xAE PushValueOfVar i, 0xAF GetNamedMember i | `Push constant8 i`, `GetVariable` / `GetMember` |
| 0xB0 / 0xB1 CallNamedFunc(Pop) i | `Push constant8 i`, `CallFunction`, `Pop` / `SetVariable` |
| 0xB2 / 0xB3 CallNamedMethod(Pop) i | `Push constant8 i`, `CallMethod`, `Pop` / `SetVariable` |

- branches are re-targeted after the expansion; `GotoFrame2`'s u32 becomes the play-flag byte; `GetURL2` gets SWF's flags
  byte (0); `DefineFunction(2)` headers are rebuilt.
- SWF's two `DefineFunction2` flag bytes are the 2nd and 3rd of the 3 bytes the decoder reads as `flags`: the bit
  `AptFunction2Flags` calls `PRELOAD_EXTERN` (0x10000) is SWF's `PreloadGlobal`. Evidence: RotWK `QuitMenu.apt`'s
  `InitialSetup` (bytes `00 6A 01`) reads register 2 as `_global` (`if (extern.InGame) { r2.InGame = true; … }`, with `_root`
  in register 1), and AptTools writes the same bytes. The interpreter's reading is a question below.

### The private tag

Tag code **1000**, ignored by players; JPEXS keeps it when it saves (also through its XML export). Each body starts with the
8 bytes `OBFAPT1\0` and a kind byte:

- **1, manifest**: movie name, producer, then for every standard tag in flattened order (a `DefineSprite` followed by its own
  tags) the SHA-256 of (u16 code + body), and where it came from (kind, `.apt` record offset, character id);
- **2, file**: the archive path and the bytes of one original file (`.apt`, `.const`, `.dat`, each `.ru`).

They are what makes the way back exact: an importer finds the edited tags by their digests and writes only those into the
original records. `export --no-embed` leaves the private tags out: a smaller SWF to look at.

## Verification

- `engine/tests/test_apt_swf.cpp` (synthetic movies only, built byte by byte with `AptTestUtil.h`): bit fields, zlib, the
  AVM1 lowering (exact bytes), branch re-targeting, triangle outlines, the shape comparison, and the export of a synthetic
  movie (its tags, and that their structure does not depend on whether the textures load).
- With the game files (`export` over a mount; numbers of 2026-11):

| | RotWK 2.01 | BFME2 1.06 |
|---|---:|---:|
| movies converted | 86 / 86 | 84 / 84 |
| JPEXS opens it and decompiles every script | 86 | 84 |
| Ruffle 0.7.1 loads without a panic | 86 | 84 |

## Prior work and comparison

- **[LibreSAGE/AptTools](https://github.com/LibreSAGE/AptTools)** (Rust; MIT per its `Cargo.toml`) converts APT to SWF and
  back and was the reference this converter was checked against. Its decompiled QuitMenu showed three mistakes here (the
  `DefineFunction2` preload flags, the button key byte, SWF 7's case-sensitivity), all fixed. Its EA-opcode expansions
  (`apt-convert/src/bytecode.rs`) agree with the table above; no code was taken from it. The goals differ: AptTools rebuilds
  a movie from a semantic model, this tool keeps the original bytes and writes edits into them.

  | (AptTools 0.1.0, 2026-11) | openbfme_apt_swf | AptTools |
  |---|---|---|
  | APT → SWF, RotWK / BFME2 | 86 / 84 | 86 / 84 |
  | `.ru` colours | R, G, B, A (as RW 0x4A8AD5 reads them) | red and blue swapped |
- **OpenSAGE** names EA's opcodes as they are used here (`EA_PushThis` for 0x56, below).
- **JPEXS Free Flash Decompiler** and **Ruffle** are the SWF tools the output is tested with.

## Not yet (questions for people who know the format)

- **Image characters (type 7)** carry only a texture id. None is placed directly in either game (0 of RotWK's 1 240, BFME2's
  1 271); they are the bitmaps of shape fills. Is the `.dat` `N=x y w h` form a sub-rectangle of the image's own texture
  (as OpenBFME reads it, S-2704) or of an atlas?
- **Static text, morph, sound, video, non-root movie characters**: the layouts are not decoded.
- **Fonts**: Apt font characters carry a u32 glyph list but no outlines. What do the glyph values index?
- **Frame labels**: what do the three bits of `0x70000` mean?
- **Button records** carry 4 floats after the colour (+52..+67) whose meaning is unknown; they are kept only in the private
  tag. The transition byte follows SWF's order, so 0x80 is `IdleToOverDown` (`AptFile.h` calls it `OverDownToIdle`).
- **Clip event records**: the u32 at +4 is 0 in all 895 RotWK records (new ones are written so). A run-time link?
- **DefineFunction2 flags**: is the byte before SWF's two flag bytes ever set, and is there an EA "PreloadExtern" at all? The
  interpreter (`AptActionInterpreter.cpp`) preloads `extern` for 0x10000, which the QuitMenu evidence above contradicts.
- **Opcode 0x56** (`EA_PushThis` in OpenSAGE / AptTools) appears in BFME2's OnlineQuickMatch, outside the RotWK census the
  decoder accepts; such programs are exported as empty action lists (the original bytes stay in the private tag).
- **Constant types** 2 (property) and 3 (none), and `PushData` type 8: no verified run-time meaning.
- **Apt version 7** movies run with SWF 6 rules in a SWF player (case-insensitive names, as in the game; but SWF 6's
  undefined-to-string and to-number rules).
- **Strings**: texts a script sets at run time (`buttonName = "$Settings"`) show their `$Label` key in a SWF player; the game
  resolves them when it draws. `--resolve-strings` only resolves the texts stored in the movie.
