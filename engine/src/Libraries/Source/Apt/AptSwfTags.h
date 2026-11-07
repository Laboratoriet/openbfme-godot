// OpenBFME. GPL-3.0.
//
// The SWF tags the APT <-> SWF converter edits, as structs with an encoder and a decoder each (SWF 19: PlaceObject2,
// DefineEditText, DefineButton2, FrameLabel).  The exporter writes them, the importer reads them back to find edits, and
// the CLI's small editor changes them (tool only).

#pragma once

#include "Libraries/Source/Apt/AptSwfFormat.h"

#include <cstdint>
#include <string>
#include <vector>

namespace aptswf
{

struct SwfPlaceObject2
{
	std::uint8_t flags = 0; // ClipActions 0x80, ClipDepth 0x40, Name 0x20, Ratio 0x10, ColorTransform 0x08, Matrix 0x04, Character 0x02, Move 0x01
	std::uint16_t depth = 0;
	std::uint16_t characterId = 0;
	SwfMatrix matrix;
	SwfCxform cxform;
	std::uint16_t ratio = 0;
	std::string name;
	std::uint16_t clipDepth = 0;
	std::vector<std::uint8_t> clipActions; // CLIPACTIONS, raw
};

struct SwfEditText
{
	std::uint16_t id = 0;
	std::int32_t bounds[4] = { 0, 0, 0, 0 }; // twips: xmin xmax ymin ymax
	std::uint8_t flags1 = 0; // HasText 0x80, WordWrap 0x40, Multiline 0x20, Password 0x10, ReadOnly 0x08, HasTextColor 0x04, HasMaxLength 0x02, HasFont 0x01
	std::uint8_t flags2 = 0; // HasFontClass 0x80, AutoSize 0x40, HasLayout 0x20, NoSelect 0x10, Border 0x08, WasStatic 0x04, HTML 0x02, UseOutlines 0x01
	std::uint16_t fontId = 0;
	std::string fontClass;
	std::uint16_t fontHeight = 0; // twips
	std::uint8_t color[4] = { 0, 0, 0, 255 };
	std::uint16_t maxLength = 0;
	std::uint8_t align = 0;
	std::uint16_t leftMargin = 0, rightMargin = 0, indent = 0;
	std::int16_t leading = 0;
	std::string variableName;
	std::string initialText;
};

struct SwfButtonRecord
{
	std::uint8_t flags = 0; // StateHitTest 0x08, StateDown 0x04, StateOver 0x02, StateUp 0x01
	std::uint16_t characterId = 0;
	std::uint16_t depth = 0;
	SwfMatrix matrix;
	SwfCxform cxform;
};

struct SwfButton2
{
	std::uint16_t id = 0;
	std::uint8_t flags = 0; // TrackAsMenu 0x01
	std::vector<SwfButtonRecord> records;
	std::vector<std::uint8_t> condActions; // the BUTTONCONDACTION list, raw
};

// True when two DefineShape3 bodies draw the same thing: the same id, bounds, style layers and paths (absolute points, the
// fill / line selection of each path), whatever the bit widths, record splits or redundant style records of the encoding.
// Bitmap fill matrices may differ by `matrixTolerance` in each 16.16 / twip value (JPEXS's XML keeps 8 decimal digits).
// False also when either body does not decode (*why says what differs).
bool shapesEquivalent(const std::vector<std::uint8_t> &a, const std::vector<std::uint8_t> &b, std::int32_t matrixTolerance, std::string *why);

std::vector<std::uint8_t> encodePlaceObject2(const SwfPlaceObject2 &p);
bool decodePlaceObject2(const std::vector<std::uint8_t> &body, SwfPlaceObject2 &out);
std::vector<std::uint8_t> encodeEditText(const SwfEditText &t);
bool decodeEditText(const std::vector<std::uint8_t> &body, SwfEditText &out);
std::vector<std::uint8_t> encodeButton2(const SwfButton2 &b);
bool decodeButton2(const std::vector<std::uint8_t> &body, SwfButton2 &out);

} // namespace aptswf
