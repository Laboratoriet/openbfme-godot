// OpenBFME. GPL-3.0.
//
// Edit recipes for the APT <-> SWF converter (tool only; docs/APT-SWF.md "Recipes").
//
// A recipe is a small text file that describes edits to one movie: placements to add, move, rename or take out, frame labels,
// removals and new text fields.  It holds no game data, so it can be shared; the converter applies it to the user's OWN copy of
// the movie (any version: 2.01, 2.02, a mod), through the same path as an edit made in a SWF editor: the recipe edits the
// exported SWF's standard tags, and the importer writes them back into the .apt (AptSwfImport.h).
//
//   # comments start with '#'
//   openbfme-apt-recipe 1                         the first line: the format and its version
//   movie Stats                                   the movie it is for (checked against the SWF)
//   note Ten faction buttons in two rows          printed when the recipe is applied
//   expect sprite=92 name=6 character=62          a check: a placement with these values exists (else the recipe stops)
//   place  sprite=92 frame=1 depth=408 character=62 name=7 like=1 x=-250.4 y=150
//   set    sprite=92 name=0 x=-250.4 y=40         change an existing placement (x y dx dy scale depth character)
//   rename sprite=323 name=PlayerList to=PlayerListAll
//   delete sprite=92 frame=1 name=6               take a placement out of its frame
//   remove sprite=92 frame=2 depth=408            add a RemoveObject2 (the instance at that depth goes away from that frame on)
//   label  sprite=92 frame=1 name=_ten            add a frame label
//   text   id=Name7 font=12 bounds=0,0,120,20 height=14 color=FFFFFFFF align=center text="$Stats:FactionName_7" var=""
//          [readonly] [multiline] [wordwrap]       a new text field; `place ... character=Name7` places it
//   value  sprite=92 frame=1 action=1 old=7 new=10 a pushed integer in the frame's 1st action list (exactly one, or count=N)
//   action sprite=0 frame=1                       a new action list at the end of the frame, in p-code (JPEXS's names), up to `end`:
//            Push "_root"                           Push "s", 12, 1.5, true, false, null, undefined, register1 (comma-separated)
//            GetVariable                            the APT runtime's single-byte actions by name (GetMember, SetMember, CallMethod, ...)
//            If done / Jump done / done:            branches to a label in the same block
//            DefineFunction "" 0 {  ...  }          a function (DefineFunction, the body up to a `}` line)
//          end                                      (also GotoFrame N, GotoLabel "x", StoreRegister N, GetURL "url" "target")
//
// sprite=0 is the root timeline; frames count from 1 (as JPEXS shows them).  A placement is selected by name= or depth= (with
// optional frame= and character=); it must match exactly one placing tag (one with a character).  `like=NAME` starts a new
// placement as a copy of an existing one in the same sprite (flags, matrix, colour) before x / y / scale / name / depth apply.
// Numbers are pixels; scale=sx,sy sets the matrix scale.  Values with spaces go in double quotes.

#pragma once

#include "Libraries/Source/Apt/AptSwfFormat.h"

#include <string>
#include <vector>

namespace aptswf
{

struct RecipeResult
{
	std::string movie;               // the recipe's movie line
	std::vector<std::string> notes;  // its note lines
	std::vector<std::string> log;    // one line per applied step
};

// Applies the recipe to the SWF's standard tags (private tags are left as they are).  False with *error naming the line on the
// first problem; the SWF is then partly edited and must not be used.
bool applyRecipe(const std::string &text, SwfFile &swf, const std::string &movieName, RecipeResult &out, std::string *error);

} // namespace aptswf
