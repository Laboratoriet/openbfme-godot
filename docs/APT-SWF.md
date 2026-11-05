# APT ↔ SWF converter

`openbfme_apt_swf` turns the game's Apt menu movies (`.apt` + `.const` + `.dat` + `_geometry/*.ru`, one BIG per movie) into
standard SWF files that SWF tools open (JPEXS Free Flash Decompiler, Ruffle), and turns such a SWF back into the Apt files:

- **unedited**, the files come back byte for byte;
- **edited** placements, text fields, button records and frame labels are written back into the `.apt` records;
- other edits are refused with the tag named (they need a full Apt writer, see "Not yet").

It is a tool, not part of the game library. It builds on the Apt player's own reader and decoder (`AptFile`, `AptActionDecoder`).
It reads the game files at run time and writes only to the folder given with `--out`: no game data belongs in this repository.

What cannot come back is the original authoring source (the `.fla`: layer names, guides, comments, symbol folders, the
ActionScript source text). The SWF is the compiled movie, as the Apt files are; JPEXS can export it to FLA/XFL, which gives an
editable project but not the original one.

## Build and run

```sh
cmake --build engine/build --target openbfme_apt_swf
export ROTWK_INSTALL=... BFME2_INSTALL=...

openbfme_apt_swf roundtrip --game rotwk --out out/rotwk     # every movie: export, import, compare; out/rotwk/report.md
openbfme_apt_swf roundtrip --game bfme2 --out out/bfme2
openbfme_apt_swf roundtrip --game rotwk --big <mod>/apt.big --out out/mod   # a mod's movies over the game
openbfme_apt_swf export --game rotwk --movie Options --out out/x           # one movie
openbfme_apt_swf export --game rotwk --resolve-strings --out out/preview   # a preview: "$Label" texts replaced by the game's strings
openbfme_apt_swf import Options.swf --out out/mod-src                      # SWF -> .apt / .const / .dat / .ru
openbfme_apt_swf pack-big out/mod-src Mod.big                              # a BIG for -mod
openbfme_apt_swf info Options.swf                                          # tags, text fields, named placements
openbfme_apt_swf set-text IN.swf OUT.swf 84 "New text"                     # tiny editor for tests
openbfme_apt_swf move IN.swf OUT.swf 62 0 37 -150 0                        # sprite 62, frame 0, depth 37, 150 px left
```

`--game` mounts the archives as the game does (`RetailArchivePolicy`); each movie is read from the archive that provides it.
`--big` converts every movie in the given archives; files a mod does not ship (a `.const` next to a replaced `.apt`) come from
the mount, as the game reads them. A `--resolve-strings` preview has no private tags and is not meant to go back to Apt.

## The SWF

The SWF version is 6 for every movie: EA's runtime looks names up case-insensitively (`AptObject.h`: `_strcmpi` keys) whatever
the Apt version, SWF players are case-sensitive from version 7, and the menus rely on it (RotWK's buttons bind a text field to
`ButtonName` and set `buttonName`). The stage is the movie's size, the frame rate is 1000 / ms-per-frame.
Apt character ids stay the SWF character ids; characters the converter adds get ids above the movie's last one.

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
| imports / exports | `ImportAssets2` (`<movie>.swf`) / `ExportAssets` |
| image, static text, morph, sound, video, non-root movie | an empty one-frame sprite (no decoded layout yet) |

### Actions

APT keeps SWF's opcode numbers for the standard actions but stores operands differently, and adds EA opcodes. Every program is
decoded with `AptActionDecoder` and written as standard AVM1 (`AptSwfAvm1.h`):

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
  byte (0); `DefineFunction(2)` headers are rebuilt. SWF's two flag bytes are the 2nd and 3rd of the 3 bytes the decoder
  reads as `flags`: the bit `AptFunction2Flags` calls `PRELOAD_EXTERN` (0x10000) is SWF's `PreloadGlobal`. Evidence: RotWK
  `QuitMenu.apt`'s `InitialSetup` (bytes `00 6A 01`) reads register 2 as `_global` (`if (extern.InGame) { r2.InGame = true; … }`,
  with `_root` in register 1), and LibreSAGE/AptTools writes the same bytes. The interpreter's reading is a question below.

The expansions agree with LibreSAGE/AptTools' `apt-convert/src/bytecode.rs` (MIT), which was read for comparison; no code was taken.
JPEXS decompiles the resulting AVM1 to readable ActionScript.

### The private tag

Tag code **1000**, ignored by players; JPEXS keeps it when it saves (also through its XML export). Each body starts with the
8 bytes `OBFAPT1\0` and a kind byte:

- **1, manifest**: movie name, producer, then for every standard tag in flattened order (a `DefineSprite` followed by its own
  tags) the SHA-256 of (u16 code + body), and where it came from (kind, `.apt` record offset, character id);
- **2, file**: the archive path and the bytes of one original file (`.apt`, `.const`, `.dat`, each `.ru`).

## SWF → Apt

1. A standard tag whose digest matches the manifest is unedited. With none edited, the original files are written as they were.
2. Otherwise the export is regenerated from the original files (its structure does not depend on the textures: a texture that
   does not load becomes a 1 × 1 stand-in with the same id), and each changed tag is compared with its regenerated twin:
   - `DefineShape3`: compared as a drawing (layers, styles, paths as absolute points), so an editor's re-encoding of the same
     shape is not an edit; a real shape edit is refused;
   - `PlaceObject2`, `DefineEditText`, `DefineButton2`, `FrameLabel`: decoded and compared field by field with the SWF form of
     the original record (the exporter's own functions); each changed field is written into that record of the `.apt`. A field
     whose SWF value still equals the conversion of the original keeps its original bytes, so floats that SWF's fixed point
     cannot hold survive an edit next to them. New strings (an instance name, a text) are appended to the `.apt` and the record
     points at them. 16.16 values may differ by 1 (JPEXS's XML keeps 8 decimal digits);
   - anything else that changed is refused, naming the tag.
3. Adding or removing tags is refused (a structural edit).

## Verification

- `engine/tests/test_apt_swf.cpp`: bit fields, zlib, the AVM1 lowering (exact bytes), branch re-targeting, triangle outlines,
  the export of a synthetic movie, the byte-exact round trip, a text and a placement edit re-encoded (unedited floats kept),
  and the refusals. Synthetic movies only.
- `openbfme_apt_swf roundtrip` over a game mount writes `report.md` with per-type byte-identical counts and the notes (what the
  SWF cannot express) with the number of movies each applies to.

## Not yet (questions for people who know the format)

- **Image characters (type 7)**: their record is only a texture id. How does the runtime size and place an image character
  that is placed directly, and is the `.dat` `N=x y w h` rectangle a sub-rectangle of the image's own texture or of an atlas?
- **Static text, morph, sound, video, non-root movie characters**: the layouts are not decoded.
- **Fonts**: Apt font characters carry a u32 glyph list but no outlines; text renders in the player's substitute face. What
  do the glyph values index?
- **Frame labels** carry two more fields (flags, a frame id) with no SWF place; their meaning is unverified.
- **Button records** carry 4 floats after the colour (+52..+67) whose meaning is unknown; they are kept only in the private
  tag. The transition byte follows SWF's order, so 0x80 is `IdleToOverDown` (`AptFile.h` calls it `OverDownToIdle`).
- **DefineFunction2 flags**: is the byte before SWF's two flag bytes (`AptFunction2Flags::PRELOAD_GLOBAL` = 0x1) ever set, and
  is there an EA "PreloadExtern" at all? The interpreter (`AptActionInterpreter.cpp`) preloads `extern` for 0x10000 and
  `_global` for 0x1, which the QuitMenu evidence above contradicts.
- **Apt version 7** movies run with SWF 6 rules in a SWF player (case-insensitive names, as in the game; but SWF 6's
  undefined-to-string and to-number rules).
- **Strings**: texts a script sets at run time (`buttonName = "$Settings"`) show their `$Label` key in a SWF player; the game
  resolves them when it draws. `--resolve-strings` only resolves the texts stored in the movie.
- **Opcode 0x56** (`EA_PushThis` in OpenSAGE / AptTools) appears in BFME2's OnlineQuickMatch but not in the RotWK census the
  decoder accepts; such programs are exported as empty action lists (the original bytes stay in the private tag).
- **Curves**: `.ru` holds triangles only, so SWF shapes are polygons; the original curves are not recoverable.
- **Full Apt writer**: structural edits (new tags, new characters), shape edits (re-triangulation), bitmap edits (TGA) and
  action edits (an AVM1 → Apt assembler that re-encodes the EA forms and the `.const` table) are the next steps.
