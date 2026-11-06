// OpenBFME. GPL-3.0.
//
// SWF -> APT (the APT <-> SWF converter, tool only; docs/APT-SWF.md).
//
// The SWF must come from the exporter (AptSwfExport.h): its private tags carry the original movie files and, per standard
// tag, a digest and where in the .apt the tag came from.  Import:
//
//  1. Every standard tag whose digest matches the manifest is unedited.  With no edits the original files come back as
//     they were, byte for byte (.apt, .const, .dat and every .ru).
//  2. An edited tag is decoded, compared field by field with the SWF form of its original APT record (the same functions
//     the exporter used), and each changed field is written into that record of the .apt.  A field whose SWF value still
//     equals the conversion of the original keeps its original bytes, so a float that SWF's fixed point cannot hold
//     survives an edit of a neighbouring field.  New strings (a renamed instance, a changed text) are appended to the .apt
//     and the record's pointer is moved to them.
//
//  3. The tags are lined up with the APT records by structure, not by position: definitions by character id, frame items
//     timeline by timeline and frame by frame (the unedited items are anchors; between them an edited item pairs with the
//     exported item of the same kind, a placement with the same depth first).  Items the SWF adds become new records, items
//     it leaves out are taken out of their frame: a changed frame gets a new item-pointer list and its timeline a new frame
//     table, appended to the .apt (the old tables stay unreferenced, since other records may share them).  A DefineEditText
//     with a new id becomes a new APT text character (the next id); placements of it are written with that id.
//
// Re-encoded field edits: PlaceObject2 (depth, character, matrix, colour transform, ratio, instance name, clip depth, flags),
// DefineEditText (bounds, font, size, colour, alignment, read-only / multiline / word-wrap, variable, text), DefineButton2
// records (state, depth, matrix, colour) and the menu flag, FrameLabel names, RemoveObject2 depths, SetBackgroundColor.
// Structural edits: new PlaceObject2 (without clip actions), RemoveObject2, FrameLabel and SetBackgroundColor items, frame
// items taken out or reordered, new DefineEditText characters.  Edited and new DoAction / DoInitAction lists are assembled into
// new APT programs (AptSwfAssemble.h; each checked by decoding it back) and their items pointed at them.  Anything else (shapes,
// bitmaps, clip and button actions, new sprites / shapes / buttons, added or removed frames, imports and exports) is an error
// naming the tag.

#pragma once

#include "Libraries/Source/Apt/AptSwfExport.h"

#include <string>
#include <vector>

namespace aptswf
{

struct ImportResult
{
	std::string movieName;
	std::string producer;
	std::vector<AptMovieFile> files;   // the movie's files (the originals, with the edits applied to the .apt)
	std::vector<std::string> edits;    // one line per re-encoded field change
	std::vector<std::string> ignored;  // SWF changes with no APT field (reported, not applied)
	std::size_t standardTags = 0;
	std::size_t editedTags = 0;
};

bool importSwf(const std::vector<std::uint8_t> &swfBytes, ImportResult &out, std::string *error);

} // namespace aptswf
