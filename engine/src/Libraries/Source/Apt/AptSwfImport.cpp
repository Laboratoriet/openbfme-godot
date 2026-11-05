// OpenBFME. GPL-3.0.
// See AptSwfImport.h.  Record layouts: AptFile.cpp (parsePlaceObject, parseText, parseButton, parseFrames).

#include "Libraries/Source/Apt/AptSwfImport.h"

#include "Libraries/Source/Apt/AptSwfAvm1.h"
#include "Libraries/Source/Apt/AptSwfTags.h"

#include <cmath>
#include <cstring>
#include <map>

namespace aptswf
{

namespace
{

struct ManifestEntry
{
	std::string digest;
	TagOrigin origin;
};

bool fail(std::string *error, const std::string &m)
{
	if (error)
	{
		*error = m;
	}
	return false;
}

// The .apt being patched.
class AptPatch
{
public:
	std::vector<std::uint8_t> &b;
	explicit AptPatch(std::vector<std::uint8_t> &bytes) : b(bytes) {}

	std::uint32_t u32(std::uint32_t at) const
	{
		return (std::uint32_t)b[at] | ((std::uint32_t)b[at + 1] << 8) | ((std::uint32_t)b[at + 2] << 16) | ((std::uint32_t)b[at + 3] << 24);
	}
	void putU32(std::uint32_t at, std::uint32_t v)
	{
		for (int i = 0; i < 4; ++i)
		{
			b[at + i] = (std::uint8_t)(v >> (8 * i));
		}
	}
	void putF32(std::uint32_t at, float v)
	{
		std::uint32_t bits;
		std::memcpy(&bits, &v, 4);
		putU32(at, bits);
	}
	// a new NUL-terminated string at the end of the file (4-byte aligned, like the file's own records); returns its offset
	std::uint32_t appendString(const std::string &s)
	{
		while (b.size() % 4)
		{
			b.push_back(0);
		}
		const std::uint32_t at = (std::uint32_t)b.size();
		b.insert(b.end(), s.begin(), s.end());
		b.push_back(0);
		return at;
	}
};

std::int32_t effScaleX(const SwfMatrix &m) { return m.hasScale ? m.scaleX : 65536; }
std::int32_t effScaleY(const SwfMatrix &m) { return m.hasScale ? m.scaleY : 65536; }
std::int32_t effRot0(const SwfMatrix &m) { return m.hasRotate ? m.rotateSkew0 : 0; }
std::int32_t effRot1(const SwfMatrix &m) { return m.hasRotate ? m.rotateSkew1 : 0; }
std::int32_t effMult(const SwfCxform &c, int k) { return c.hasMult ? c.mult[k] : 256; }
std::int32_t effAdd(const SwfCxform &c, int k) { return c.hasAdd ? c.add[k] : 0; }

std::string fmt(double v)
{
	char buf[32];
	std::snprintf(buf, sizeof(buf), "%g", v);
	return buf;
}

// Writes the matrix fields that differ between the expected and the actual SWF matrix into the record's 6 floats at `at`
// (a, b, c, d, tx, ty).
void patchMatrix(AptPatch &p, std::uint32_t at, const SwfMatrix &want, const SwfMatrix &got, const std::string &what, std::vector<std::string> &edits)
{
	const std::int32_t fixedWant[4] = { effScaleX(want), effRot0(want), effRot1(want), effScaleY(want) };
	const std::int32_t fixedGot[4] = { effScaleX(got), effRot0(got), effRot1(got), effScaleY(got) };
	static const char *names[4] = { "a", "b", "c", "d" };
	for (int k = 0; k < 4; ++k)
	{
		// tolerance: 1 / 65536, the last digit JPEXS's XML (8 decimal digits) cannot carry; a smaller edit is not detected
		if (fixedWant[k] < fixedGot[k] - 1 || fixedWant[k] > fixedGot[k] + 1)
		{
			p.putF32(at + k * 4, (float)(fixedGot[k] / 65536.0));
			edits.push_back(what + ": matrix " + names[k] + " " + fmt(fixedWant[k] / 65536.0) + " -> " + fmt(fixedGot[k] / 65536.0));
		}
	}
	if (want.translateX != got.translateX)
	{
		p.putF32(at + 16, (float)(got.translateX / 20.0));
		edits.push_back(what + ": x " + fmt(want.translateX / 20.0) + " -> " + fmt(got.translateX / 20.0));
	}
	if (want.translateY != got.translateY)
	{
		p.putF32(at + 20, (float)(got.translateY / 20.0));
		edits.push_back(what + ": y " + fmt(want.translateY / 20.0) + " -> " + fmt(got.translateY / 20.0));
	}
}

class Importer
{
public:
	ImportResult &out;
	explicit Importer(ImportResult &r) : out(r) {}

	bool run(const std::vector<std::uint8_t> &swfBytes, std::string *error)
	{
		SwfFile swf;
		if (!swfReadFile(swfBytes, swf, error))
		{
			return false;
		}
		std::vector<SwfTag> standard;
		std::vector<ManifestEntry> manifest;
		bool haveManifest = false;
		for (SwfTag &t : swf.tags)
		{
			if (t.code != SWF_TAG_OPENBFME_APT)
			{
				standard.push_back(std::move(t));
				continue;
			}
			SwfReader r(t.body.data(), t.body.size());
			const std::vector<std::uint8_t> magic = r.bytes(8);
			if (magic.size() != 8 || std::memcmp(magic.data(), kPrivateMagic, 8) != 0)
			{
				return fail(error, "private tag 1000 without the OBFAPT1 magic (not written by this converter)");
			}
			const std::uint8_t kind = r.u8();
			if (kind == PRIVATE_MANIFEST)
			{
				out.movieName = r.cstring();
				out.producer = r.cstring();
				const std::uint32_t n = r.u32();
				for (std::uint32_t i = 0; i < n && r.ok(); ++i)
				{
					ManifestEntry e;
					const std::vector<std::uint8_t> d = r.bytes(32);
					static const char *hex = "0123456789abcdef";
					for (std::uint8_t c : d)
					{
						e.digest.push_back(hex[c >> 4]);
						e.digest.push_back(hex[c & 15]);
					}
					e.origin.kind = (TagOrigin::Kind)r.u8();
					e.origin.aptOffset = r.u32();
					e.origin.characterId = r.u32();
					manifest.push_back(e);
				}
				haveManifest = r.ok();
			}
			else if (kind == PRIVATE_FILE)
			{
				AptMovieFile f;
				f.path = r.cstring();
				const std::uint32_t size = r.u32();
				f.bytes = r.bytes(size);
				if (!r.ok())
				{
					return fail(error, "private file record truncated");
				}
				out.files.push_back(std::move(f));
			}
			else
			{
				return fail(error, "private tag of unknown kind " + std::to_string(kind));
			}
		}
		if (!haveManifest || out.files.empty())
		{
			return fail(error, "the SWF has no OpenBFME APT data (tag 1000): it was not exported by openbfme_apt_swf, or an editor dropped the tag");
		}
		const std::vector<const SwfTag *> flat = flattenTags(standard);
		out.standardTags = flat.size();
		if (flat.size() != manifest.size())
		{
			return fail(error, "the SWF has " + std::to_string(flat.size()) + " standard tags where " + std::to_string(manifest.size()) +
				" were exported: tags were added or removed (a structural edit; needs the full APT writer, not in this milestone)");
		}
		// the export regenerated from the original files (without textures: the tag structure does not depend on them), to
		// tell an edit from an editor's re-encoding of the same content
		ExportResult expected;
		bool regenerated = false;
		std::vector<const SwfTag *> want;
		for (std::size_t i = 0; i < flat.size(); ++i)
		{
			if (tagDigest(*flat[i]) == manifest[i].digest)
			{
				continue;
			}
			if (!regenerated)
			{
				AptMovieFiles original;
				original.name = out.movieName;
				original.files = out.files;
				if (!exportStandardTags(original, ExportOptions(), expected, error))
				{
					return false;
				}
				want = flattenTags(expected.tags);
				regenerated = true;
				if (want.size() != flat.size())
				{
					return fail(error, "the regenerated export has " + std::to_string(want.size()) + " tags, the SWF " + std::to_string(flat.size()) +
						" (the SWF was made by another converter version)");
				}
				if (!movie(error))
				{
					return false;
				}
			}
			const std::string where = tagName(flat[i]->code) + " #" + std::to_string(i);
			if (flat[i]->code != want[i]->code)
			{
				return fail(error, where + ": was a " + tagName(want[i]->code) + " (a structural edit; not in this milestone)");
			}
			if (flat[i]->body == want[i]->body)
			{
				continue;
			}
			std::string why;
			const std::size_t before = out.edits.size();
			switch (flat[i]->code)
			{
				case SWF_TAG_DEFINESHAPE3:
					// an editor's re-encoding of the same drawing is not an edit
					if (!shapesEquivalent(want[i]->body, flat[i]->body, 2, &why))
					{
						return fail(error, where + " was edited (" + why + "); re-encoding shapes into .ru triangles is not supported in this milestone");
					}
					break;
				case SWF_TAG_PLACEOBJECT2:
				case SWF_TAG_DEFINEEDITTEXT:
				case SWF_TAG_DEFINEBUTTON2:
				case SWF_TAG_FRAMELABEL:
					if (!applyEdit(*flat[i], manifest[i].origin, i, error))
					{
						return false;
					}
					break;
				default:
					return fail(error, where + " was edited; re-encoding a " + tagName(flat[i]->code) +
						" into APT is not supported in this milestone (bitmaps, actions and structure need the full APT writer)");
			}
			out.editedTags += out.edits.size() > before ? 1 : 0;
		}
		if (m_aptPatched)
		{
			AptMovieFile *apt = findFile(out.movieName + ".apt");
			apt->bytes = m_apt;
		}
		return true;
	}

private:
	AptMovieFile *findFile(const std::string &name)
	{
		std::string want = name;
		for (char &c : want)
		{
			c = (char)std::tolower((unsigned char)c);
		}
		for (AptMovieFile &f : out.files)
		{
			std::string p = f.path;
			for (char &c : p)
			{
				c = (char)std::tolower((unsigned char)c);
			}
			if (p == want)
			{
				return &f;
			}
		}
		return nullptr;
	}

	// the original movie, parsed once
	bool movie(std::string *error)
	{
		if (m_movie)
		{
			return true;
		}
		AptMovieFile *apt = findFile(out.movieName + ".apt");
		AptMovieFile *cst = findFile(out.movieName + ".const");
		if (!apt || !cst)
		{
			return fail(error, "the private data lacks " + out.movieName + ".apt / .const");
		}
		AptConstFile consts;
		std::string e;
		if (!AptConstFile::parse(cst->bytes, consts, &e))
		{
			return fail(error, e);
		}
		m_movie = std::make_shared<AptFile>();
		if (!AptFile::parse(out.movieName, std::make_shared<const std::vector<std::uint8_t>>(apt->bytes), consts, *m_movie, &e))
		{
			return fail(error, e);
		}
		m_apt = apt->bytes;
		auto index = [&](const std::vector<AptFrame> &frames) {
			for (const AptFrame &f : frames)
			{
				for (const AptFrameItem &it : f.items)
				{
					m_items[it.offset] = &it;
				}
			}
		};
		index(m_movie->frames);
		for (const AptCharacter &c : m_movie->characters)
		{
			index(c.frames);
		}
		return true;
	}

	ProgramBytes programs()
	{
		return [this](std::uint32_t codeOffset, std::vector<std::uint8_t> &bytes, std::string *) {
			Avm1Result r;
			// the exporter writes an empty action list for a program the decoder refuses (AptSwfExport.cpp Exporter::actions)
			bytes = programAvm1(*m_movie, codeOffset, r, nullptr) ? std::move(r.bytes) : std::vector<std::uint8_t>{ 0x00 };
			return true;
		};
	}

	static std::string tagName(std::uint16_t code)
	{
		switch (code)
		{
			case SWF_TAG_DEFINESHAPE3: return "DefineShape3";
			case SWF_TAG_DEFINEBITSLOSSLESS2: return "DefineBitsLossless2";
			case SWF_TAG_DOACTION: return "DoAction";
			case SWF_TAG_DOINITACTION: return "DoInitAction";
			case SWF_TAG_DEFINESPRITE: return "DefineSprite";
			case SWF_TAG_DEFINEFONT2: return "DefineFont2";
			case SWF_TAG_PLACEOBJECT2: return "PlaceObject2";
			case SWF_TAG_REMOVEOBJECT2: return "RemoveObject2";
			case SWF_TAG_DEFINEEDITTEXT: return "DefineEditText";
			case SWF_TAG_DEFINEBUTTON2: return "DefineButton2";
			case SWF_TAG_FRAMELABEL: return "FrameLabel";
			case SWF_TAG_SHOWFRAME: return "ShowFrame";
			default: return "tag " + std::to_string(code);
		}
	}

	bool applyEdit(const SwfTag &tag, const TagOrigin &origin, std::size_t index, std::string *error)
	{
		const std::string where = tagName(tag.code) + " #" + std::to_string(index);
		if (!movie(error))
		{
			return false;
		}
		switch (origin.kind)
		{
			case TagOrigin::Kind::PlaceObject:
				if (tag.code == SWF_TAG_PLACEOBJECT2)
				{
					return editPlace(tag, origin, where, error);
				}
				break;
			case TagOrigin::Kind::EditText:
				if (tag.code == SWF_TAG_DEFINEEDITTEXT)
				{
					return editText(tag, origin, where, error);
				}
				break;
			case TagOrigin::Kind::Button:
				if (tag.code == SWF_TAG_DEFINEBUTTON2)
				{
					return editButton(tag, origin, where, error);
				}
				break;
			case TagOrigin::Kind::FrameLabel:
				if (tag.code == SWF_TAG_FRAMELABEL)
				{
					return editLabel(tag, origin, where, error);
				}
				break;
			default:
				break;
		}
		return fail(error, where + " was edited; re-encoding a " + tagName(tag.code) +
			" into APT is not supported in this milestone (shapes, bitmaps, actions and structure need the full APT writer)");
	}

	bool editPlace(const SwfTag &tag, const TagOrigin &origin, const std::string &whereTag, std::string *error)
	{
		auto it = m_items.find(origin.aptOffset);
		if (it == m_items.end() || !it->second->place)
		{
			return fail(error, whereTag + ": no place object at .apt offset " + std::to_string(origin.aptOffset));
		}
		const AptPlaceObject &orig = *it->second->place;
		SwfPlaceObject2 want, got;
		if (!aptPlaceToSwf(*m_movie, orig, programs(), want, m_notes, error))
		{
			return false;
		}
		if (!decodePlaceObject2(tag.body, got))
		{
			return fail(error, whereTag + ": does not decode as a PlaceObject2");
		}
		const std::uint32_t at = origin.aptOffset;
		AptPatch p(m_apt);
		const std::string what = "place object (depth " + std::to_string(orig.depth) + (orig.name.empty() ? "" : ", '" + orig.name + "'") + ")";
		if (want.clipActions != got.clipActions)
		{
			return fail(error, whereTag + ": the clip actions changed (action edits need the AVM1 -> APT assembler, not in this milestone)");
		}
		if (want.flags != got.flags)
		{
			if ((want.flags ^ got.flags) & 0x80)
			{
				return fail(error, whereTag + ": adding or removing clip actions is not supported in this milestone");
			}
			p.putU32(at + 4, (orig.flags & ~0x7Fu) | (got.flags & 0x7Fu));
			m_aptPatched = true;
			out.edits.push_back(what + ": flags 0x" + std::to_string(want.flags) + " -> 0x" + std::to_string(got.flags));
		}
		if (want.depth != got.depth)
		{
			p.putU32(at + 8, got.depth);
			out.edits.push_back(what + ": depth " + std::to_string(want.depth) + " -> " + std::to_string(got.depth));
		}
		if ((got.flags & 0x02) && want.characterId != got.characterId)
		{
			p.putU32(at + 12, got.characterId);
			out.edits.push_back(what + ": character " + std::to_string(want.characterId) + " -> " + std::to_string(got.characterId));
		}
		if (got.flags & 0x04)
		{
			patchMatrix(p, at + 16, want.matrix, got.matrix, what, out.edits);
		}
		if (got.flags & 0x08)
		{
			for (int k = 0; k < 4; ++k)
			{
				if (effMult(want.cxform, k) != effMult(got.cxform, k))
				{
					const long tint = std::lround(effMult(got.cxform, k) * 255.0 / 256.0);
					if (tint < 0 || tint > 255)
					{
						return fail(error, whereTag + ": colour multiplier outside 0..1 (APT's tint is a byte)");
					}
					m_apt[at + 40 + k] = (std::uint8_t)tint;
					out.edits.push_back(what + ": tint[" + std::to_string(k) + "] " + std::to_string(orig.tint[k]) + " -> " + std::to_string(tint));
				}
				if (effAdd(want.cxform, k) != effAdd(got.cxform, k))
				{
					const std::int32_t add = effAdd(got.cxform, k);
					if (add < 0 || add > 255)
					{
						return fail(error, whereTag + ": colour add term outside 0..255 (APT's additive colour is a byte)");
					}
					m_apt[at + 44 + k] = (std::uint8_t)add;
					out.edits.push_back(what + ": additive[" + std::to_string(k) + "] " + std::to_string(orig.additive[k]) + " -> " + std::to_string(add));
				}
			}
		}
		if ((got.flags & 0x10) && want.ratio != got.ratio)
		{
			p.putF32(at + 48, (float)(got.ratio / 65536.0));
			out.edits.push_back(what + ": ratio " + std::to_string(want.ratio) + " -> " + std::to_string(got.ratio));
		}
		if ((got.flags & 0x20) && want.name != got.name)
		{
			p.putU32(at + 52, p.appendString(got.name));
			out.edits.push_back(what + ": name '" + want.name + "' -> '" + got.name + "'");
		}
		if ((got.flags & 0x40) && want.clipDepth != got.clipDepth)
		{
			p.putU32(at + 56, got.clipDepth);
			out.edits.push_back(what + ": clip depth " + std::to_string(want.clipDepth) + " -> " + std::to_string(got.clipDepth));
		}
		m_aptPatched = true;
		return true;
	}

	bool editText(const SwfTag &tag, const TagOrigin &origin, const std::string &whereTag, std::string *error)
	{
		if (origin.characterId >= m_movie->characters.size() || !m_movie->characters[origin.characterId].text)
		{
			return fail(error, whereTag + ": character " + std::to_string(origin.characterId) + " is not a text field");
		}
		const AptTextInfo &orig = *m_movie->characters[origin.characterId].text;
		const SwfEditText want = aptTextToSwf(origin.characterId, orig);
		SwfEditText got;
		if (!decodeEditText(tag.body, got))
		{
			return fail(error, whereTag + ": does not decode as a DefineEditText");
		}
		if (got.id != want.id)
		{
			return fail(error, whereTag + ": the character id changed (" + std::to_string(want.id) + " -> " + std::to_string(got.id) + ")");
		}
		const std::uint32_t at = origin.aptOffset;
		AptPatch p(m_apt);
		const std::string what = "text field " + std::to_string(origin.characterId);
		// bounds: SWF xmin xmax ymin ymax -> APT x0 y0 x1 y1 at +8
		static const int aptSlot[4] = { 0, 2, 1, 3 };
		static const char *names[4] = { "xmin", "xmax", "ymin", "ymax" };
		for (int k = 0; k < 4; ++k)
		{
			if (want.bounds[k] != got.bounds[k])
			{
				p.putF32(at + 8 + aptSlot[k] * 4, (float)(got.bounds[k] / 20.0));
				out.edits.push_back(what + ": " + names[k] + " " + fmt(want.bounds[k] / 20.0) + " -> " + fmt(got.bounds[k] / 20.0));
			}
		}
		if ((got.flags1 & 0x01) && want.fontId != got.fontId)
		{
			p.putU32(at + 24, got.fontId);
			out.edits.push_back(what + ": font " + std::to_string(want.fontId) + " -> " + std::to_string(got.fontId));
		}
		if ((got.flags2 & 0x20) && want.align != got.align)
		{
			if (got.align > 2)
			{
				return fail(error, whereTag + ": alignment " + std::to_string(got.align) + " (justify) has no APT code");
			}
			p.putU32(at + 28, got.align);
			out.edits.push_back(what + ": alignment " + std::to_string(want.align) + " -> " + std::to_string(got.align));
		}
		if (got.flags1 & 0x04)
		{
			// the file holds 0xAARRGGBB: bytes B G R A (AptFile.cpp parseText)
			static const int byteOf[4] = { 34, 33, 32, 35 };
			for (int k = 0; k < 4; ++k)
			{
				if (want.color[k] != got.color[k])
				{
					m_apt[at + byteOf[k]] = got.color[k];
					out.edits.push_back(what + ": colour[" + std::to_string(k) + "] " + std::to_string(want.color[k]) + " -> " + std::to_string(got.color[k]));
				}
			}
		}
		if (want.fontHeight != got.fontHeight)
		{
			p.putF32(at + 36, (float)(got.fontHeight / 20.0));
			out.edits.push_back(what + ": font height " + fmt(want.fontHeight / 20.0) + " -> " + fmt(got.fontHeight / 20.0));
		}
		struct Flag
		{
			std::uint8_t bit;
			std::uint32_t offset;
			const char *name;
		};
		static const Flag flags[3] = { { 0x08, 40, "read-only" }, { 0x20, 44, "multiline" }, { 0x40, 48, "word wrap" } };
		for (const Flag &f : flags)
		{
			if ((want.flags1 & f.bit) != (got.flags1 & f.bit))
			{
				p.putU32(at + f.offset, (got.flags1 & f.bit) ? 1u : 0u);
				out.edits.push_back(what + ": " + f.name + ((got.flags1 & f.bit) ? " on" : " off"));
			}
		}
		if (((want.flags1 ^ got.flags1) & ~0x68u) != 0 || want.flags2 != got.flags2)
		{
			out.ignored.push_back(what + ": DefineEditText flags without an APT field changed (password, border, HTML, auto size, ...)");
		}
		if (want.variableName != got.variableName)
		{
			p.putU32(at + 56, p.appendString(got.variableName));
			out.edits.push_back(what + ": variable '" + want.variableName + "' -> '" + got.variableName + "'");
		}
		if (want.initialText != got.initialText)
		{
			p.putU32(at + 52, p.appendString(got.initialText));
			out.edits.push_back(what + ": text '" + want.initialText + "' -> '" + got.initialText + "'");
		}
		m_aptPatched = true;
		return true;
	}

	bool editButton(const SwfTag &tag, const TagOrigin &origin, const std::string &whereTag, std::string *error)
	{
		if (origin.characterId >= m_movie->characters.size() || !m_movie->characters[origin.characterId].button)
		{
			return fail(error, whereTag + ": character " + std::to_string(origin.characterId) + " is not a button");
		}
		const AptCharacter &c = m_movie->characters[origin.characterId];
		const AptButtonInfo &orig = *c.button;
		SwfButton2 want, got;
		if (!aptButtonToSwf(*m_movie, c, 0, programs(), want, m_notes, error))
		{
			return false;
		}
		if (!decodeButton2(tag.body, got))
		{
			return fail(error, whereTag + ": does not decode as a DefineButton2");
		}
		if (got.records.size() != want.records.size())
		{
			return fail(error, whereTag + ": button records were added or removed (structural edit, not in this milestone)");
		}
		if (got.condActions != want.condActions)
		{
			return fail(error, whereTag + ": the button actions changed (action edits need the AVM1 -> APT assembler, not in this milestone)");
		}
		AptPatch p(m_apt);
		const std::string what = "button " + std::to_string(c.id);
		if (want.flags != got.flags)
		{
			p.putU32(c.offset + 8, got.flags & 1);
			out.edits.push_back(what + ": track as menu " + std::string((got.flags & 1) ? "on" : "off"));
		}
		const std::uint32_t table = p.u32(c.offset + 48);
		for (std::size_t i = 0; i < got.records.size(); ++i)
		{
			const SwfButtonRecord &w = want.records[i], &g = got.records[i];
			const AptButtonRecord &o = orig.records[i];
			const std::uint32_t at = table + (std::uint32_t)i * 68;
			const std::string rw = what + " record " + std::to_string(i);
			if (w.flags != g.flags)
			{
				m_apt[at] = (std::uint8_t)(g.flags & 0x0F);
				out.edits.push_back(rw + ": states " + std::to_string(w.flags) + " -> " + std::to_string(g.flags));
			}
			// a hit-only shape record shows the converter's hit-mesh shape in the SWF; its character is not compared
			const bool hitMesh = o.stateMask == 8 && buttonNeedsHitShape(*m_movie, orig) && o.characterId < m_movie->characters.size() &&
				m_movie->characters[o.characterId].type == APT_CHAR_SHAPE && !orig.triangles.empty();
			if (!hitMesh && w.characterId != g.characterId)
			{
				p.putU32(at + 4, g.characterId);
				out.edits.push_back(rw + ": character " + std::to_string(w.characterId) + " -> " + std::to_string(g.characterId));
			}
			if (w.depth != g.depth)
			{
				p.putU32(at + 8, g.depth);
				out.edits.push_back(rw + ": depth " + std::to_string(w.depth) + " -> " + std::to_string(g.depth));
			}
			patchMatrix(p, at + 12, w.matrix, g.matrix, rw, out.edits);
			for (int k = 0; k < 4; ++k)
			{
				if (effMult(w.cxform, k) != effMult(g.cxform, k))
				{
					p.putF32(at + 36 + k * 4, (float)(effMult(g.cxform, k) / 256.0));
					out.edits.push_back(rw + ": colour[" + std::to_string(k) + "] -> " + fmt(effMult(g.cxform, k) / 256.0));
				}
				if (effAdd(g.cxform, k) != 0)
				{
					out.ignored.push_back(rw + ": a colour add term (APT button records have none)");
				}
			}
		}
		m_aptPatched = true;
		return true;
	}

	bool editLabel(const SwfTag &tag, const TagOrigin &origin, const std::string &whereTag, std::string *error)
	{
		auto it = m_items.find(origin.aptOffset);
		if (it == m_items.end() || it->second->type != APT_ITEM_FRAMELABEL)
		{
			return fail(error, whereTag + ": no frame label at .apt offset " + std::to_string(origin.aptOffset));
		}
		SwfReader r(tag.body.data(), tag.body.size());
		const std::string label = r.cstring();
		if (!r.ok())
		{
			return fail(error, whereTag + ": does not decode as a FrameLabel");
		}
		if (label != it->second->label)
		{
			AptPatch p(m_apt);
			p.putU32(origin.aptOffset + 4, p.appendString(label));
			out.edits.push_back("frame label '" + it->second->label + "' -> '" + label + "'");
			m_aptPatched = true;
		}
		return true;
	}

	std::shared_ptr<AptFile> m_movie;
	std::map<std::uint32_t, const AptFrameItem *> m_items;
	std::vector<std::uint8_t> m_apt;
	bool m_aptPatched = false;
	std::set<std::string> m_notes;
};

} // namespace

bool importSwf(const std::vector<std::uint8_t> &swfBytes, ImportResult &out, std::string *error)
{
	out = ImportResult();
	Importer im(out);
	return im.run(swfBytes, error);
}

} // namespace aptswf
