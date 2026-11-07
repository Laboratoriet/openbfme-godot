# APT edit recipes

A recipe is a small text file that describes edits to one Apt movie: placements to add, move, rename or take out, frame
labels, removals, new text fields, new frame scripts and changed script numbers. It holds no game data, so it can be shared;
`openbfme_apt_swf apply` (docs/APT-SWF.md) applies it to the user's **own** copy of the movie, whichever version that is
(2.01, a later patch, a mod).

A recipe goes through the same path as an edit made in a SWF editor: `apply` exports the movie to SWF, the recipe edits the
SWF's standard tags (`AptSwfRecipe.h`), and the importer writes the edits into the `.apt` (`AptSwfImport.h`). So a recipe can
do exactly what a SWF edit can, and is refused where a SWF edit would be.

```sh
openbfme_apt_swf apply stats.recipe --big "<game>/apt/Stats.big" --out out/stats --pack out/Stats-mod.big
```

`apply` prints each step, then each edit the importer wrote, and writes:

- `out/stats/files/`: the movie's files with the edits (`Stats.apt`, `Stats.const`, ... unedited files unchanged);
- `out/stats/Stats.swf`: the edited SWF, to look at in JPEXS or Ruffle;
- with `--pack`, a BIG of `files/` to load with `-mod`.

The movie comes from `--big` (archives, later ones win file by file; a mod's archive after the game's), `--dir` (loose files:
`Stats.apt`, `Stats.const`, `Stats.dat`, `Stats_geometry/*.ru`), `--game rotwk|bfme2` (the game's own archives, in the full
build) or `--swf` (a SWF made by `export`).

## An example

```
openbfme-apt-recipe 1
movie Stats
note Ten faction cards in two rows of five

# the card this recipe copies must be there
expect sprite=92 name=6 character=62

# three more cards, copies of card 6 (scale, colour) at new depths
place  sprite=92 frame=1 depth=408 character=62 name=7 like=6 x=2.6 y=132.15
place  sprite=92 frame=1 depth=409 character=62 name=8 like=6 x=105.6 y=132.15
place  sprite=92 frame=1 depth=410 character=62 name=9 like=6 x=208.6 y=132.15

# the first row moves up
set    sprite=92 name=0 y=41.15
set    sprite=92 name=1 y=41.15

# the page's refresh loop counts to 10, not 7
value  sprite=92 frame=1 action=1 old=7 new=10
```

## The format

- The first line that is not empty or a comment is `openbfme-apt-recipe 1`: the format and its version. A newer version is
  refused, not guessed at.
- Then `movie NAME`, before any edit: the movie the recipe is for (compared without case with the movie being edited).
- One step per line: a verb, then `key=value` settings in any order. A bare word is a flag (`readonly`, `move`).
- Values with spaces go in double quotes: `to="Square One"`; inside quotes, `\"` and `\\` are a quote and a backslash.
- `#` starts a comment line. Empty lines are ignored. Windows (CRLF) line endings are fine.
- `sprite=0` is the root timeline; any other number is a `DefineSprite`'s character id. Frames count from 1, as JPEXS shows
  them. Positions and sizes are pixels.
- Steps run in order, each on the result of the ones before. The first problem stops the recipe with its line number and
  verb (`line 3 (place): depth 1 is already used in frame 1 of sprite 0 (pick a free depth)`), and nothing is written.

`openbfme_apt_swf info Stats.swf --all` lists every placement with its sprite, frame, depth, character, name and position:
the numbers a recipe needs.

### Choosing a placement

`expect`, `set`, `rename` and `delete` act on one existing placement, chosen by:

| setting | |
|---|---|
| `sprite=N` | the timeline (required) |
| `name=NAME` | the instance name |
| `depth=N` | the depth |
| `frame=N` | only placements in that frame |
| `character=N` | only placements of that character |

`name=` or `depth=` is required. The selection must match exactly one placement that places a character; with none or
several the recipe stops (`2 placements match (sprite=92 depth=41): add frame= or depth= to pick one`). With `frame=` and
`depth=` and no `name=`, it may also pick a Move placement (one that only moves the instance at that depth in that frame).

## Steps

| step | settings | what it does |
|---|---|---|
| `note TEXT` | | printed when the recipe is applied |
| `expect` | a placement (above) | checks that this copy of the movie is the one the recipe was written for; stops if no placement matches |
| `place` | `sprite= frame= depth=`, then `character=N` or `like=NAME` or `move`; optional `name= x= y= dx= dy= scale=` | adds a `PlaceObject2` at the end of the frame |
| `set` | a placement; any of `x= y= dx= dy= scale= to-depth= to-character=` | changes that placement |
| `rename` | a placement; `to=NEWNAME` | gives it another instance name |
| `delete` | a placement | takes it out of its frame |
| `remove` | `sprite= frame= depth=` | adds a `RemoveObject2`: the instance at that depth goes away from that frame on |
| `label` | `sprite= frame= name=` | adds a frame label |
| `text` | `id= font= bounds= height=`; optional `color= align= text= var= readonly multiline wordwrap` | defines a new text field |
| `action` | `sprite= frame=`, then p-code lines up to `end` | adds a frame script at the end of the frame |
| `value` | `sprite= frame= action= old= new=`; optional `count=` | changes an integer a frame script pushes |

### place

- `character=N` places character N (an existing one of the movie, or the `id` of a `text` step of this recipe).
- `like=NAME` starts as a copy of the named placement in the same sprite: its character, matrix, colour, ratio and clip
  depth, never its clip actions, its Move flag or its name. Settings on the line then apply on top.
- `move` writes a Move placement: it changes the instance already at that depth from that frame on (no new instance; a
  different layout for a later frame of the page, for example).
- `x=` / `y=` set the position, `dx=` / `dy=` move it, `scale=SX,SY` sets the matrix scale.
- The depth must be free in that frame, unless the step is a `move`.

### set

`x= y= dx= dy= scale=` as for `place`; `to-depth=N` moves the placement to another depth, `to-character=N` makes it place
another character.

### text

| setting | |
|---|---|
| `id=NAME` | the name `place ... character=NAME` uses for it |
| `font=N` | the character id of one of the movie's fonts |
| `bounds=X0,Y0,X1,Y1` | the text box, in pixels |
| `height=N` | the font size, in pixels |
| `color=RRGGBBAA` | 8 hex digits (default `FFFFFFFF`) |
| `align=left|right|center` | (default `left`) |
| `text="..."` | the initial text; a `$Label` is a string the game looks up (`$Stats:FactionName_7`) |
| `var=NAME` | the variable the field shows |
| `readonly`, `multiline`, `wordwrap` | flags |

The importer gives the new field the next free Apt character id.

### action

```
# _root.FactionColor[7] = 0xFFAA00;
action sprite=0 frame=1
  Push "_root"
  GetVariable
  Push "FactionColor"
  GetMember
  Push 7, 16755200
  SetMember
end
```

The lines between `action` and `end` are AVM1 in p-code, with JPEXS's names. The block becomes a new `DoAction` at the end of
the frame; the importer assembles it into an APT program (docs/APT-SWF.md, "Actions back to APT").

| p-code | |
|---|---|
| `Push V, V, ...` | values: `"string"`, an integer, a number with a `.` or exponent (pushed as a float), `true`, `false`, `null`, `undefined`, `registerN` (0..255) |
| `NAME:` | a label (alone on its line) |
| `Jump NAME`, `If NAME` | a branch to a label in the same block (a function body is its own block) |
| `GotoFrame N`, `StoreRegister N` | |
| `GotoLabel "label"`, `GetURL "url" "target"` | |
| `DefineFunction "name" N "param1" ... {` | a function with N parameters; its body follows, closed by a `}` line |
| the runtime's one-byte actions | `NextFrame Play Stop Subtract Multiply Divide Not StringEquals Pop ToInteger GetVariable SetVariable StringAdd GetProperty SetProperty CloneSprite RemoveSprite Trace RandomNumber Delete Delete2 DefineLocal CallFunction Return Modulo NewObject DefineLocal2 InitArray InitObject TypeOf Add2 Less2 Equals2 ToNumber ToString PushDuplicate GetMember SetMember Increment Decrement CallMethod Enumerate2 BitAnd BitRShift Greater` |

Lines starting with `;` or `#` inside the block are comments. Actions the Apt runtime does not have are not accepted.

### value

`value sprite=92 frame=1 action=1 old=7 new=10` finds the frame's first script (`action=2` the second, counting the scripts
of that frame), and changes every pushed integer 7 in it, function bodies included, to 10. There must be exactly one such
push, or `count=N` of them; anything else stops the recipe (it is not the script the recipe was written for).

## Writing a recipe

1. `openbfme_apt_swf export --big "<game>/apt/Stats.big" --out out/x`, then `openbfme_apt_swf info out/x/Stats.swf --all`
   for the placements, and JPEXS for the scripts (p-code view) and the layout.
2. Start with `expect` lines for what the recipe relies on, so that it stops on a copy it was not written for.
3. Apply it, look at `out/.../<Movie>.swf` in JPEXS or Ruffle, load the BIG with `-mod`, adjust, repeat.
4. Share the recipe file, never the edited movie: the edited files are still the game's data.
