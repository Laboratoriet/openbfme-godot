// OpenBFME. GPL-3.0.
//
// APT movie -> SWF (the APT <-> SWF converter, tool only; docs/APT-SWF.md).
//
// A movie is the file set retail mounts for it (AptLoad.h): X.apt, X.const, optionally X.dat and X_geometry/<id>.ru, plus
// the textures its image map names (art/Textures/apt_X_<n>.tga).  The SWF has two layers:
//
//  * Standard tags any SWF tool reads: DefineShape3 (from the .ru triangles and lines; textured fills reference
//    DefineBitsLossless2 bitmaps made from the TGA textures), DefineSprite + PlaceObject2 / RemoveObject2 / FrameLabel /
//    DoAction / ShowFrame (the timelines), DefineButton2, DefineEditText, DefineFont2 (name only, no outlines),
//    ImportAssets2 / ExportAssets, DoInitAction, SetBackgroundColor.  APT character ids are kept as SWF character ids;
//    characters the converter adds (bitmaps, button hit shapes, placeholders) get ids above the movie's last one.
//  * Private tags (code SWF_TAG_OPENBFME_APT = 1000) with the original APT-side data, so SWF -> APT is exact for anything
//    not edited.  Each private tag body starts with the 8-byte magic "OBFAPT1\0" and a kind byte:
//      kind 1 manifest: cstring movie name, cstring producer, u32 tag count, then per standard tag (in the flattened order:
//             a DefineSprite is followed by its own tags) the SHA-256 of (u16 code + body) - the edit detector - and its
//             origin (u8 TagOrigin::Kind, u32 .apt offset of the record, u32 character id);
//      kind 2 file:     cstring archive path ("MainMenu.apt", "MainMenu_geometry/44.ru", ...), u32 size, the bytes.
//    Players and editors skip an unknown tag; JPEXS keeps it when it saves.
//
// The standard tags are a pure function of the original files (exportStandardTags), so the importer can regenerate
// what was exported and compare it with what it reads back (AptSwfImport.h).

#pragma once

#include "Libraries/Source/Apt/AptFile.h"
#include "Libraries/Source/Apt/AptSwfFormat.h"

#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

namespace aptswf
{

struct AptMovieFile
{
	std::string path; // as stored in the archive
	std::vector<std::uint8_t> bytes;
};

// The files of one movie, in archive order.  Textures are looked up separately (they are shared across the mount and
// are not part of the APT round trip).
struct AptMovieFiles
{
	std::string name; // "MainMenu"
	std::vector<AptMovieFile> files;
	const AptMovieFile *find(const std::string &path) const; // ASCII case-insensitive, '/' and '\\' equal
};

struct AptTexture
{
	int width = 0, height = 0;
	std::vector<std::uint8_t> rgba; // top row first
};
// Loads `art/Textures/<name>` (e.g. "apt_MainMenu_1.tga"); false when it cannot.
using AptTextureLookup = std::function<bool(const std::string &name, AptTexture &out, std::string *error)>;

// Where a standard tag came from in the .apt, for the importer's edit re-encoding.
struct TagOrigin
{
	enum class Kind : std::uint8_t
	{
		Other,       // not editable in this milestone (re-encoded only through the original bytes)
		PlaceObject, // aptOffset = the frame item (type 3) record
		FrameLabel,  // aptOffset = the frame item (type 2) record
		EditText,    // aptOffset = the character record
		Button       // aptOffset = the character record
	};
	Kind kind = Kind::Other;
	std::uint32_t aptOffset = 0;
	std::uint32_t characterId = 0;
};

struct ExportStats
{
	std::size_t shapes = 0, bitmaps = 0, sprites = 0, buttons = 0, texts = 0, fonts = 0, placeholders = 0, imports = 0, exports = 0;
	std::size_t programs = 0, instructions = 0, eaOpcodes = 0, triangles = 0, lines = 0;
};

struct ExportResult
{
	std::vector<SwfTag> tags;        // the standard tags (root timeline, sprites with children)
	std::vector<TagOrigin> origins;  // one per flattened standard tag
	SwfHeader header;
	ExportStats stats;
	std::set<std::string> notes;     // what the SWF cannot express exactly (the gap list), sorted
	std::shared_ptr<AptFile> movie;  // the parsed movie
};

struct ExportOptions
{
	AptTextureLookup textures;      // may be empty: textured fills are then left out (noted)
	bool embedOriginal = true;      // write the private tags (needed for SWF -> APT)
	std::string producer = "openbfme_apt_swf 1";
};

// Parses the movie and builds the standard tags.  Deterministic: the same files give the same tags.
bool exportStandardTags(const AptMovieFiles &movie, const ExportOptions &options, ExportResult &out, std::string *error);

// The whole SWF file: standard tags + (optionally) the private tags.
bool exportSwf(const AptMovieFiles &movie, const ExportOptions &options, std::vector<std::uint8_t> &swf, ExportResult &out, std::string *error);

// Flattened view (a DefineSprite followed by its children, depth first) and the per-tag digest the manifest stores.
std::vector<const SwfTag *> flattenTags(const std::vector<SwfTag> &tags);
std::vector<SwfTag *> flattenTagsMutable(std::vector<SwfTag> &tags);
std::string tagDigest(const SwfTag &tag);

// The SWF form of single APT records, exactly as the exporter writes them (the importer compares against these).
struct Avm1Result;
struct SwfPlaceObject2;
struct SwfEditText;
struct SwfButton2;
using ProgramBytes = std::function<bool(std::uint32_t codeOffset, std::vector<std::uint8_t> &out, std::string *error)>;
bool programAvm1(const AptFile &movie, std::uint32_t codeOffset, Avm1Result &out, std::string *error);
SwfCxform aptPlaceCxform(const AptPlaceObject &p);
SwfCxform aptButtonCxform(const AptButtonRecord &r);
bool aptPlaceToSwf(const AptFile &movie, const AptPlaceObject &p, const ProgramBytes &programs, SwfPlaceObject2 &swf, std::set<std::string> &notes,
	std::string *error);
SwfEditText aptTextToSwf(std::uint32_t id, const AptTextInfo &t);
bool buttonNeedsHitShape(const AptFile &movie, const AptButtonInfo &b);
bool aptButtonToSwf(const AptFile &movie, const AptCharacter &c, std::uint32_t hitShape, const ProgramBytes &programs, SwfButton2 &swf,
	std::set<std::string> &notes, std::string *error);

// The outline loops (twips, closed: the last point repeats the first) a DefineShape3 fill gets from APT triangles (x0 y0 x1 y1
// x2 y2 in pixels): shared edges cancel, every triangle is turned clockwise on screen first.
std::vector<std::vector<std::pair<std::int32_t, std::int32_t>>> triangleOutlinesTwips(const std::vector<float> &triangles);

// Private tag records.
extern const char kPrivateMagic[8];
enum PrivateKind : std::uint8_t
{
	PRIVATE_MANIFEST = 1,
	PRIVATE_FILE = 2
};

} // namespace aptswf
