// OpenBFME. GPL-3.0.
//
// SWF file format primitives for the APT <-> SWF converter (tool only, not part of the game library).
//
// Reference: Adobe "SWF File Format Specification" version 19 (2013), chapters "Basic Data Types" (bit values, RECT,
// MATRIX, CXFORMWITHALPHA), "The Display List" (PlaceObject2, RemoveObject2), "Control Tags", "Actions", "Shapes",
// "Bitmaps", "Buttons", "Fonts and Text".  Everything here is little-endian; bit fields are packed most significant
// bit first and byte-aligned at the start of every structure, as the spec says.
//
// The writer produces uncompressed ("FWS") files.  The reader accepts "FWS" and "CWS" (zlib, decoded by the small
// inflate below, after Mark Adler's public-domain puff.c).  LZMA ("ZWS") files are refused with a message.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace aptswf
{

// ---- tag codes used by the converter (SWF 19, appendix "Tag codes") ----------------------------------------------------------
enum SwfTagCode : std::uint16_t
{
	SWF_TAG_END = 0,
	SWF_TAG_SHOWFRAME = 1,
	SWF_TAG_SETBACKGROUNDCOLOR = 9,
	SWF_TAG_DOACTION = 12,
	SWF_TAG_DEFINESHAPE3 = 32,
	SWF_TAG_PLACEOBJECT2 = 26,
	SWF_TAG_REMOVEOBJECT2 = 28,
	SWF_TAG_DEFINEBUTTON2 = 34,
	SWF_TAG_DEFINEBITSLOSSLESS2 = 36,
	SWF_TAG_DEFINEEDITTEXT = 37,
	SWF_TAG_DEFINESPRITE = 39,
	SWF_TAG_FRAMELABEL = 43,
	SWF_TAG_DEFINEFONT2 = 48,
	SWF_TAG_EXPORTASSETS = 56,
	SWF_TAG_DOINITACTION = 59,
	SWF_TAG_IMPORTASSETS2 = 71,
	// OpenBFME's private tag: the original APT-side data, see AptSwfExport.h.  Tag codes are 10 bits; 1000 is far above
	// every code Adobe assigned (the last is 93) and is not used by the SWF tools we checked (JPEXS, Ruffle).
	SWF_TAG_OPENBFME_APT = 1000
};

// ---- writing -----------------------------------------------------------------------------------------------------------------
class SwfWriter
{
public:
	std::vector<std::uint8_t> bytes;

	void u8(std::uint32_t v);
	void u16(std::uint32_t v);
	void u32(std::uint32_t v);
	void f32(float v);
	void cstring(const std::string &s); // bytes + NUL
	void raw(const std::vector<std::uint8_t> &b);
	void raw(const std::uint8_t *p, std::size_t n);

	// bit fields (most significant bit first); align() flushes the partial byte
	void ub(int bits, std::uint32_t v);
	void sb(int bits, std::int32_t v);
	void align();

	// SWF structures
	void rect(std::int32_t xmin, std::int32_t xmax, std::int32_t ymin, std::int32_t ymax); // twips
	void matrix(const struct SwfMatrix &m);
	void cxformWithAlpha(const struct SwfCxform &c);

private:
	std::uint32_t m_bitBuf = 0;
	int m_bitCount = 0;
};

// Bits needed to hold a signed / unsigned value in an SB / UB field.
int swfSignedBits(std::int32_t v);
int swfUnsignedBits(std::uint32_t v);

// SWF MATRIX in its stored units: scale / rotate-skew as 16.16 fixed, translation in twips.
struct SwfMatrix
{
	bool hasScale = false;
	std::int32_t scaleX = 65536, scaleY = 65536; // a, d
	bool hasRotate = false;
	std::int32_t rotateSkew0 = 0, rotateSkew1 = 0; // b, c
	std::int32_t translateX = 0, translateY = 0;
	bool operator==(const SwfMatrix &o) const;
	bool operator!=(const SwfMatrix &o) const { return !(*this == o); }
};

// CXFORMWITHALPHA: multiply terms 8.8 fixed (256 = 1.0), add terms in colour units.
struct SwfCxform
{
	bool hasMult = false, hasAdd = false;
	std::int32_t mult[4] = { 256, 256, 256, 256 }; // r g b a
	std::int32_t add[4] = { 0, 0, 0, 0 };
	bool operator==(const SwfCxform &o) const;
	bool operator!=(const SwfCxform &o) const { return !(*this == o); }
};

// Float matrix (APT order: x' = a*x + c*y + tx, y' = b*x + d*y + ty; translation in pixels) <-> SWF fixed matrix.
SwfMatrix swfMatrixFromFloats(float a, float b, float c, float d, float tx, float ty);
void swfMatrixToFloats(const SwfMatrix &m, float out[6]); // a b c d tx ty
std::int32_t swfFixed16(float v);   // round(v * 65536)
std::int32_t swfTwips(float pixels); // round(pixels * 20)

// One tag.  For a DefineSprite, `body` is only the 4-byte prefix (sprite id, frame count) and `children` its own timeline
// (End excluded); the writer appends the children and the End.
struct SwfTag
{
	std::uint16_t code = 0;
	std::vector<std::uint8_t> body;
	std::vector<SwfTag> children; // DefineSprite only
	bool forceLong = false;       // write the long header even for a short body (spec: some tags must, e.g. DefineBitsLossless)
	// converter bookkeeping, never serialised: where the exporter made the tag from (AptSwfExport.h TagOrigin)
	std::uint8_t originKind = 0;
	std::uint32_t originOffset = 0;
	std::uint32_t originId = 0;
};

// Serialises a tag (header + body; a DefineSprite's body is rebuilt from `spriteId` + children when `children` is used).
void swfWriteTag(SwfWriter &w, const SwfTag &tag);
std::vector<std::uint8_t> swfSpriteBody(std::uint16_t spriteId, std::uint16_t frameCount, const std::vector<SwfTag> &children);

struct SwfHeader
{
	std::uint8_t version = 7;
	std::int32_t frameWidthTwips = 0, frameHeightTwips = 0;
	std::uint16_t frameRate8_8 = 30 << 8;
	std::uint16_t frameCount = 1;
};

std::vector<std::uint8_t> swfWriteFile(const SwfHeader &header, const std::vector<SwfTag> &tags);

// ---- reading -----------------------------------------------------------------------------------------------------------------
class SwfReader
{
public:
	SwfReader(const std::uint8_t *data, std::size_t size) : m_data(data), m_size(size) {}
	bool ok() const { return m_ok; }
	std::size_t pos() const { return m_pos; }
	std::size_t size() const { return m_size; }
	bool atEnd() const { return m_pos >= m_size; }
	void seek(std::size_t p) { m_pos = p; m_bitCount = 0; }

	std::uint8_t u8();
	std::uint16_t u16();
	std::uint32_t u32();
	float f32();
	std::string cstring();
	std::vector<std::uint8_t> bytes(std::size_t n);
	std::uint32_t ub(int bits);
	std::int32_t sb(int bits);
	void align() { m_bitCount = 0; }

	void rect(std::int32_t out[4]); // xmin xmax ymin ymax
	SwfMatrix matrix();
	SwfCxform cxformWithAlpha();

private:
	bool need(std::size_t n);
	const std::uint8_t *m_data;
	std::size_t m_size;
	std::size_t m_pos = 0;
	bool m_ok = true;
	std::uint8_t m_bitByte = 0;
	int m_bitCount = 0;
};

struct SwfFile
{
	SwfHeader header;
	bool compressed = false;
	std::vector<SwfTag> tags; // End tag not included; DefineSprite children parsed
};

bool swfReadFile(const std::vector<std::uint8_t> &bytes, SwfFile &out, std::string *error);
// Splits a tag stream (a file body or a sprite body) into tags; stops after End.
bool swfReadTags(const std::uint8_t *data, std::size_t size, std::vector<SwfTag> &out, std::string *error);

// zlib streams (RFC 1950/1951).  The writer uses stored blocks only (no compression: the converter has no compressor
// dependency); the reader inflates any valid stream.
std::vector<std::uint8_t> zlibStore(const std::uint8_t *data, std::size_t size);
bool zlibInflate(const std::uint8_t *data, std::size_t size, std::vector<std::uint8_t> &out, std::string *error);

// SHA-256 of a byte range, lower-case hex (Common/Sha256.h).
std::string sha256Hex(const std::uint8_t *data, std::size_t size);
inline std::string sha256Hex(const std::vector<std::uint8_t> &b) { return sha256Hex(b.data(), b.size()); }

} // namespace aptswf
