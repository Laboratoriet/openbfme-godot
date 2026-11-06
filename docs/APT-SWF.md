# APT ↔ SWF converter

`openbfme_apt_swf` turns the game's Apt menu movies (`.apt` + `.const` + `.dat` + `_geometry/*.ru`, one BIG per movie) into
standard SWF files that SWF tools open (JPEXS Free Flash Decompiler, Ruffle), and turns such a SWF back into the Apt files:

- **unedited**, the files come back byte for byte;
- **edited** placements, text fields, button records and frame labels are written back into the `.apt` records;
- **structural** edits are written as new records: new placements of existing characters, removals, frame labels, new text
  fields, frame items taken out;
- **actions** (edited or new frame actions, edited clip and button actions, clip events of new placements) are assembled back
  into APT programs;
- other edits are refused with the tag named (they need a full Apt writer, see "Not yet").

Edits can also be written as a **recipe**, a small text file the converter applies to anyone's own copy of a movie (below).

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
openbfme_apt_swf reassemble --game rotwk --out out/asm [--write]           # every action program assembled back to APT and checked
openbfme_apt_swf pack-big out/mod-src Mod.big                              # a BIG for -mod
openbfme_apt_swf info Options.swf [--all]                                  # tags, text fields, named (--all: every) placement
openbfme_apt_swf apply my.recipe --game rotwk --out out/stats --pack Stats-mod.big   # a recipe on the game's movie
openbfme_apt_swf apply my.recipe --big apt/Stats.big --out out/stats       # ... on the movie in these archives (later ones win)
openbfme_apt_swf apply my.recipe --dir loose/ --out out/stats              # ... on loose files (Stats.apt, Stats.const, ...)
openbfme_apt_swf set-text IN.swf OUT.swf 84 "New text"                     # tiny editor for tests
openbfme_apt_swf move IN.swf OUT.swf 62 0 37 -150 0                        # sprite 62, frame 0, depth 37, 150 px left
```

`--game` mounts the archives as the game does (`RetailArchivePolicy`); each movie is read from the archive that provides it.
`--big` converts every movie in the given archives; files a mod does not ship (a `.const` next to a replaced `.apt`) come from
the mount, as the game reads them. A `--resolve-strings` preview has no private tags and is not meant to go back to Apt.
Without `--game` and without `ROTWK_INSTALL` / `BFME2_INSTALL`, `--big` reads the archives alone: the movies and their textures
(`art/Textures/apt_<movie>_<n>.tga`, which each movie's BIG carries), later archives over earlier ones file by file.

### The standalone command line

Everything but `--game` and `--resolve-strings` needs only the converter and five engine sources, so the tool also builds on
its own, without the game library (the define `OPENBFME_APTSWF_STANDALONE` leaves the retail mount out). From `engine/`:

```sh
SRC="src/Libraries/Source/Apt/AptSwfTool.cpp src/Libraries/Source/Apt/AptSwfFormat.cpp src/Libraries/Source/Apt/AptSwfAvm1.cpp
     src/Libraries/Source/Apt/AptSwfTags.cpp src/Libraries/Source/Apt/AptSwfExport.cpp src/Libraries/Source/Apt/AptSwfImport.cpp
     src/Libraries/Source/Apt/AptSwfRecipe.cpp src/Libraries/Source/Apt/AptFile.cpp src/Libraries/Source/Apt/AptActionDecoder.cpp
     src/Common/Sha256.cpp src/Common/System/FloatFromChars.cpp src/GameClient/TGAFile.cpp"
FLAGS="-std=c++17 -O2 -DOPENBFME_APTSWF_STANDALONE -Isrc -isystem thirdparty/fast_float/include"
SRC="$SRC src/Libraries/Source/Apt/AptSwfAssemble.cpp"
c++ $FLAGS -o openbfme_apt_swf $SRC                                                        # macOS / Linux
zig c++ -target x86_64-windows-gnu -static -s $FLAGS -o openbfme_apt_swf.exe $SRC          # Windows x86_64 from macOS / Linux
x86_64-w64-mingw32-g++ -static -s $FLAGS -o openbfme_apt_swf.exe $SRC                      # or with mingw-w64
```

On Windows itself, the same sources build with MSVC (`cl /std:c++17 /O2 /EHsc /DOPENBFME_APTSWF_STANDALONE /Isrc
/Ithirdparty/fast_float/include <sources> /Fe:openbfme_apt_swf.exe`) or MSYS2's MinGW g++.

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
3. **Structure.** The edited SWF's tags are lined up with the regenerated export by structure, not by position:
   - definitions by character id;
   - frame items timeline by timeline (the root, each sprite) and frame by frame: the unedited items are anchors (their
     longest common sequence); between two anchors an edited item pairs with the exported item of the same kind (a placement
     or removal with the same depth first) and goes through step 2.
4. What the SWF adds becomes new records appended to the `.apt`; nothing is moved, so every other record keeps its offset:
   - a frame whose item list changed (items added, taken out or reordered) gets a new item-pointer list, and its timeline a
     new frame table with that list (the old tables stay in the file unreferenced: other records may share them);
   - a new `PlaceObject2` (without clip actions) becomes a place-object record. Fields SWF leaves out take the values every
     retail record has (RotWK 2.01's 47 822 place objects): character -1, identity matrix, tint `FF FF FF FF`, additive 0,
     ratio 0, no name, clip depth -1, no clip actions;
   - a new `RemoveObject2` becomes a remove record; a new `FrameLabel` a label record with flags `0x70000` and its frame's
     index (all 1 799 retail labels); a new `SetBackgroundColor` a background record with alpha `FF`;
   - a `DefineEditText` with a new id becomes a new edit-text character with the next APT id (the character table is copied
     with one more entry); placements of the SWF id are written with the APT id. It needs one of the movie's fonts. Text and
     variable strings are appended (retail text records never hold a null string pointer);
   - the written `.apt` is parsed again with the game's reader (`AptFile::parse`); a failure is an error.
5. **Actions.** Programs are assembled into new APT programs at the end of the `.apt` (below), and what pointed at the old
   program points at the new one; the same actions in another encoding (an editor's re-save) are not an edit:
   - an edited or new `DoAction` / `DoInitAction`: the frame item's code pointer, or a new action record;
   - an edited placement's clip actions: the same events (flags, key codes) in the same order; each event record whose
     actions changed points at its new program;
   - an edited button's actions: the same entries and conditions; each changed one points at its new program;
   - a new placement with clip actions: a new event table (mask, key code, a zero word as in every retail record, the
     program) and its list record.
6. Refused, naming the tag: clip events or button actions added, removed or given other conditions, clip actions added to
   or removed from a placement, new shapes / sprites / buttons / bitmaps, removed characters, frames added or removed,
   imports and exports, placements of characters the converter made (bitmaps, button hit shapes).

### Actions back to APT

`AptSwfAssemble.h` is the inverse of the AVM1 lowering for the actions the APT runtime has (the decoder's 86 opcodes). It
writes APT's own layout: aligned opcodes start their operand on a 4-byte boundary, strings and tables follow the code and are
reached by pointer, branches are 32-bit offsets from the next instruction, `DefineFunction(2)` headers carry the body size and
EA's 8-byte trailer. Values go out with EA's push opcodes, the forms the retail compiler uses everywhere: `EA_PushString` for
strings (a constant-pool reference is resolved, so no `.const` strings are added), `EA_PushZero` / `One` / `Byte` / `Short` /
`Long` for integers, `EA_PushFloat` (a double that is neither a float nor an integer becomes the nearest float32: APT's numbers
are float32), `EA_PushTrue` / `False` / `Null` / `Undefined`; a register push is a `PushData` of a `.const` register entry (an
existing one, else a new one appended to the `.const`, whose strings then move by 8 bytes each). `GotoFrame2` takes the play
flag as its u32, `GetURL2` has no operand: the runtime decides from the URL and the target (`AptActionInterpreter.cpp`: a
`.swf` into a clip value loads the movie, anything else goes to the host), so SWF's send method (GET / POST, which JPEXS's
compiler sets on `fscommand`) is dropped. Refused, naming the action: anything outside the runtime's census (`With`, `Try`,
`SetTarget`, ...), `GotoFrame2`'s scene bias, `GetURL2` loading variables or into a sprite path.

A script edited in JPEXS's ActionScript editor comes back this way: JPEXS compiles the source to AVM1, the importer assembles
that (checked as above). Tested with RotWK's Stats root script, decompiled and recompiled by JPEXS with three lines added
(`-importScript`), running in OpenBFME.

Every assembled program is checked before it is kept: decoded with the game's `AptActionDecoder`, converted to AVM1 again and
compared action by action (`avm1Normalized`: pushes split into single values, constants resolved, branch targets as indices)
with the SWF's. `openbfme_apt_swf reassemble` runs that on every program of a mount (frame, init, clip and button actions);
`--write` also writes the movies with every program reference pointed at its re-assembled copy, to run them in the game.

## Recipes

A recipe describes structural and placement edits as text, so they can be shared without the game's files and applied to
any copy of a movie (another patch version, a mod). `openbfme_apt_swf apply` exports the movie, applies the recipe to the
SWF's standard tags (`AptSwfRecipe.h`), and imports the result as above, so a recipe can do exactly what a SWF edit can.

```
openbfme-apt-recipe 1                                  the format and its version (the first line)
movie Stats                                            the movie it is for (checked)
note Ten faction cards                                 printed when it is applied
expect sprite=92 name=6 character=62                   a check that this is the movie the recipe was written for
place  sprite=92 frame=1 depth=408 character=62 name=7 like=6 x=2.6 y=132.15 scale=0.55,0.55
place  sprite=92 frame=20 depth=408 move x=2.6 y=142.4  a Move placement (moves the instance at that depth)
set    sprite=92 name=0 x=-317.4 y=41.15               change a placement (x y dx dy scale to-depth to-character)
set    sprite=92 frame=20 depth=41 y=51.4              ... also a Move placement, chosen by frame= and depth=
rename sprite=323 name=PlayerList to=PlayerListAll
delete sprite=92 frame=1 name=6                        take a placement out of its frame
remove sprite=92 frame=2 depth=408                     add a RemoveObject2
label  sprite=92 frame=1 name=_ten                     add a frame label
value  sprite=92 frame=1 action=1 old=7 new=10        a pushed integer in the frame's 1st action list (exactly one, or count=N)
action sprite=0 frame=1                                a new action list at the end of the frame, in p-code, up to `end`
  Push "_root"                                         values: "s", 12, 1.5, true, false, null, undefined, register1
  GetVariable                                          the runtime's single-byte actions by their SWF / JPEXS names
  If done / Jump done / done:                          branches to labels in the same block
  DefineFunction "" 0 {   ...   }                      a function; also GotoFrame N, GotoLabel "x", StoreRegister N, GetURL "u" "t"
end
text   id=Name7 font=12 bounds=0,0,120,20 height=14 color=FFFFFFFF align=center text="$Stats:FactionName_7" var=""
place  sprite=92 frame=1 depth=411 character=Name7 x=0 y=0      place the new text field
```

`sprite=0` is the root timeline; frames count from 1 (as JPEXS shows them); numbers are pixels. A placement is chosen by
`name=` or `depth=` (with `frame=` and `character=` to narrow it down) and must match exactly one placing tag. `like=NAME`
starts a new placement as a copy of a named one (matrix, colour; not its name, Move flag or clip actions). Comments start
with `#`; values with spaces go in double quotes. Every problem stops the recipe with the line named.

## Verification

- `engine/tests/test_apt_swf.cpp`: bit fields, zlib, the AVM1 lowering (exact bytes), branch re-targeting, triangle outlines,
  the export of a synthetic movie, the byte-exact round trip, a text and a placement edit re-encoded (unedited floats kept),
  each structural edit (a new placement in the root and in a sprite, a removal and an item taken out, a frame label, a new
  text field placed by its SWF id; each edited movie converts again with no edits to the same bytes), an edited and a new
  frame action assembled back (pushes, a branch, a function, a register push and its new `.const` entry), edited clip and
  button actions and a new placement with two clip events (one a key press), the normalized comparison, a recipe of every step, the recipe's and the importer's refusals. Synthetic movies only.
- `openbfme_apt_swf reassemble` over a mount: every action program assembled back and checked.
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
- **Full Apt writer**: new shapes, sprites and buttons, frames added or removed, shape edits (re-triangulation) and bitmap
  edits (TGA) are the next steps.
