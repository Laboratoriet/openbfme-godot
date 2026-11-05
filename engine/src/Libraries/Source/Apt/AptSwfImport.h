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
// Re-encoded edit kinds in this milestone: PlaceObject2 (depth, character, matrix, colour transform, ratio, instance name,
// clip depth, flags), DefineEditText (bounds, font, size, colour, alignment, read-only / multiline / word-wrap, variable,
// text), DefineButton2 records (state, depth, matrix, colour) and the menu flag, FrameLabel names.  Anything else that
// changed (shapes, bitmaps, actions, added or removed tags) is an error naming the tag: it needs the full APT writer.

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
