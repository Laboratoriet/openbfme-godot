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
					m_manifest.push_back(e);
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
		// 1. nothing edited: every standard tag's digest matches the manifest, the original files go back as they were
		bool allMatch = flat.size() == m_manifest.size();
		for (std::size_t i = 0; allMatch && i < flat.size(); ++i)
		{
			allMatch = tagDigest(*flat[i]) == m_manifest[i].digest;
		}
		if (allMatch)
		{
			return true;
		}
		// 2. the export regenerated from the original files (without textures: the tag structure does not depend on them), to tell an
		// edit from an editor's re-encoding of the same content, and to line the edited SWF's tags up with the APT records they came from
		AptMovieFiles original;
		original.name = out.movieName;
		original.files = out.files;
		ExportResult expected;
		if (!exportStandardTags(original, ExportOptions(), expected, error))
		{
			return false;
		}
		if (flattenTags(expected.tags).size() != m_manifest.size())
		{
			return fail(error, "the regenerated export has " + std::to_string(flattenTags(expected.tags).size()) + " tags, the manifest " +
				std::to_string(m_manifest.size()) + " (the SWF was made by another converter version)");
		}
		if (!movie(error))
		{
			return false;
		}
		SwfModel want, got;
		if (!buildModel(expected.tags, want, error) || !buildModel(standard, got, error))
		{
			return false;
		}
		if (!compareGlobals(want, got, error) || !compareDefinitions(want, got, error))
		{
			return false;
		}
		for (const auto &tl : want.timelines)
		{
			auto g = got.timelines.find(tl.first);
			if (g == got.timelines.end())
			{
				return fail(error, "the timeline of " + timelineName(tl.first) + " is missing from the SWF");
			}
			if (!compareTimeline(tl.first, tl.second, g->second, error))
			{
				return false;
			}
		}
		if (!writeStructure(error))
		{
			return false;
		}
		if (m_aptPatched)
		{
			// the written .apt must parse as the game's reader parses it
			AptMovieFile *cst = findFile(out.movieName + ".const");
			AptConstFile consts;
			AptFile check;
			std::string e;
			if (!AptConstFile::parse(cst->bytes, consts, &e) ||
				!AptFile::parse(out.movieName, std::make_shared<const std::vector<std::uint8_t>>(m_apt), consts, check, &e))
			{
				return fail(error, "internal error: the edited " + out.movieName + ".apt does not parse (" + e + ")");
			}
			AptMovieFile *apt = findFile(out.movieName + ".apt");
			apt->bytes = m_apt;
		}
		return true;
	}

private:
	// ---- the SWF's structure: definitions by character id, timelines by sprite id (0 = the root), frame by frame ----
	struct Entry
	{
		const SwfTag *tag = nullptr;
		std::size_t flat = 0; // index in the flattened tag list (for the regenerated export: the manifest index)
	};
	struct Timeline
	{
		std::vector<std::vector<Entry>> frames; // the items of each frame (ShowFrame not included)
		std::size_t trailing = 0;               // items after the last ShowFrame
	};
	struct SwfModel
	{
		std::vector<Entry> globals;              // ImportAssets2 / ExportAssets, in order
		std::map<std::uint32_t, Entry> defs;     // character id -> its definition
		std::vector<std::uint32_t> defOrder;     // ids in file order
		std::map<std::uint32_t, Timeline> timelines;
	};

	static bool isControl(std::uint16_t code)
	{
		return code == SWF_TAG_PLACEOBJECT2 || code == SWF_TAG_REMOVEOBJECT2 || code == SWF_TAG_DOACTION || code == SWF_TAG_DOINITACTION ||
			code == SWF_TAG_FRAMELABEL || code == SWF_TAG_SETBACKGROUNDCOLOR || code == SWF_TAG_SHOWFRAME;
	}

	// tags whose body starts with the character id they define (SWF 19's Define* tags)
	static bool definesCharacter(std::uint16_t code)
	{
		switch (code)
		{
			case 2: case 6: case 7: case 10: case 11: case 14: case 20: case 21: case 22: case 32: case 33: case 34: case 35: case 36:
			case 37: case 39: case 46: case 48: case 60: case 75: case 83: case 84: case 90:
				return true;
			default:
				return false;
		}
	}

	// tags an editor may add that carry nothing for the movie (file attributes, metadata, debugger and product info)
	static bool isEditorOnly(std::uint16_t code) { return code == 69 || code == 77 || code == 41 || code == 58 || code == 63 || code == 64 || code == 24; }

	bool buildModel(const std::vector<SwfTag> &tags, SwfModel &m, std::string *error)
	{
		std::size_t flat = 0;
		Timeline &root = m.timelines[0];
		root.frames.emplace_back();
		for (const SwfTag &t : tags)
		{
			const std::size_t at = flat++;
			if (isControl(t.code))
			{
				if (t.code == SWF_TAG_SHOWFRAME)
				{
					root.frames.emplace_back();
				}
				else
				{
					root.frames.back().push_back({ &t, at });
				}
			}
			else if (t.code == SWF_TAG_IMPORTASSETS2 || t.code == SWF_TAG_EXPORTASSETS)
			{
				m.globals.push_back({ &t, at });
			}
			else if (definesCharacter(t.code) && t.body.size() >= 2)
			{
				const std::uint32_t id = (std::uint32_t)t.body[0] | ((std::uint32_t)t.body[1] << 8);
				if (m.defs.count(id))
				{
					return fail(error, tagName(t.code) + " #" + std::to_string(at) + " defines character " + std::to_string(id) + " a second time");
				}
				m.defs[id] = { &t, at };
				m.defOrder.push_back(id);
				if (t.code == SWF_TAG_DEFINESPRITE)
				{
					Timeline &tl = m.timelines[id];
					tl.frames.emplace_back();
					for (const SwfTag &c : t.children)
					{
						const std::size_t cat = flat++;
						if (c.code == SWF_TAG_SHOWFRAME)
						{
							tl.frames.emplace_back();
						}
						else if (isControl(c.code))
						{
							tl.frames.back().push_back({ &c, cat });
						}
						else if (!isEditorOnly(c.code))
						{
							return fail(error, tagName(c.code) + " #" + std::to_string(cat) + " inside sprite " + std::to_string(id) +
								" is not a timeline tag the APT format has");
						}
					}
					tl.trailing = tl.frames.back().size();
					tl.frames.pop_back();
				}
				else
				{
					flat += t.children.size();
				}
			}
			else if (isEditorOnly(t.code))
			{
				out.ignored.push_back(tagName(t.code) + " #" + std::to_string(at) + ": an editor's tag with no APT counterpart (left out)");
			}
			else
			{
				return fail(error, tagName(t.code) + " #" + std::to_string(at) + " has no APT counterpart (not written by this converter)");
			}
		}
		root.trailing = root.frames.back().size();
		root.frames.pop_back();
		return true;
	}

	// unedited: the digest the manifest stores, or the body the regenerated export has (an editor's identical re-encoding)
	bool sameAsExported(const Entry &w, const SwfTag &g) const
	{
		return g.code == w.tag->code && (g.body == w.tag->body || tagDigest(g) == m_manifest[w.flat].digest);
	}

	std::string timelineName(std::uint32_t id) const { return id == 0 ? std::string("the root timeline") : "sprite " + std::to_string(id); }

	bool compareGlobals(const SwfModel &want, const SwfModel &got, std::string *error)
	{
		bool same = want.globals.size() == got.globals.size();
		for (std::size_t i = 0; same && i < want.globals.size(); ++i)
		{
			same = sameAsExported(want.globals[i], *got.globals[i].tag);
		}
		if (!same)
		{
			return fail(error, "the movie's ImportAssets2 / ExportAssets changed: imports and exports are not re-encoded into APT (not supported)");
		}
		return true;
	}

	bool compareDefinitions(const SwfModel &want, const SwfModel &got, std::string *error)
	{
		for (std::uint32_t id : want.defOrder)
		{
			const Entry &w = want.defs.at(id);
			auto it = got.defs.find(id);
			if (it == got.defs.end())
			{
				return fail(error, tagName(w.tag->code) + " of character " + std::to_string(id) +
					" was removed: removing characters is not supported (take its placements out instead)");
			}
			const Entry &g = it->second;
			const std::string where = tagName(g.tag->code) + " #" + std::to_string(g.flat);
			if (g.tag->code != w.tag->code)
			{
				return fail(error, where + ": character " + std::to_string(id) + " was a " + tagName(w.tag->code) +
					" (changing a character's kind is not supported)");
			}
			if (sameAsExported(w, *g.tag))
			{
				continue;
			}
			std::string why;
			const std::size_t before = out.edits.size();
			switch (g.tag->code)
			{
				case SWF_TAG_DEFINESPRITE:
					// the 4-byte header: id and frame count (the children are compared as a timeline)
					if (g.tag->body != w.tag->body)
					{
						return fail(error, where + ": the frame count of sprite " + std::to_string(id) +
							" changed: adding or removing frames is not supported (a structural edit beyond frame items)");
					}
					break;
				case SWF_TAG_DEFINESHAPE3:
					// an editor's re-encoding of the same drawing is not an edit
					if (!shapesEquivalent(w.tag->body, g.tag->body, 2, &why))
					{
						return fail(error, where + " was edited (" + why + "); re-encoding shapes into .ru triangles is not supported yet");
					}
					break;
				case SWF_TAG_DEFINEEDITTEXT:
				case SWF_TAG_DEFINEBUTTON2:
					if (!applyEdit(*g.tag, m_manifest[w.flat].origin, g.flat, error))
					{
						return false;
					}
					break;
				default:
					return fail(error, where + " was edited; re-encoding a " + tagName(g.tag->code) +
						" into APT is not supported yet (bitmaps and fonts need the full APT writer)");
			}
			out.editedTags += out.edits.size() > before ? 1 : 0;
		}
		// characters the SWF adds: new text fields become new APT characters (ids after the movie's last one)
		std::uint32_t next = (std::uint32_t)m_movie->characters.size();
		for (std::uint32_t id : got.defOrder)
		{
			if (want.defs.count(id))
			{
				continue;
			}
			const Entry &g = got.defs.at(id);
			const std::string where = tagName(g.tag->code) + " #" + std::to_string(g.flat);
			if (g.tag->code != SWF_TAG_DEFINEEDITTEXT)
			{
				return fail(error, where + ": a new character " + std::to_string(id) + " (" + tagName(g.tag->code) +
					"): only new text fields (DefineEditText) can be added; new shapes, sprites, buttons and bitmaps need the full APT writer");
			}
			m_newCharacterIds[id] = next++;
			m_newCharacters.push_back(&g);
		}
		for (const Entry *g : m_newCharacters)
		{
			if (!newText(*g, error))
			{
				return false;
			}
		}
		return true;
	}

	// The APT character a placement in the SWF names: an APT character id, or a text field the SWF adds.
	bool aptCharacter(std::uint32_t swfId, const std::string &where, std::uint32_t &aptId, std::string *error) const
	{
		auto n = m_newCharacterIds.find(swfId);
		if (n != m_newCharacterIds.end())
		{
			aptId = n->second;
			return true;
		}
		if (swfId == 0 || swfId >= m_movie->characters.size())
		{
			return fail(error, where + ": character " + std::to_string(swfId) +
				" is not an APT character (the converter made it: a bitmap or a button's hit shape)");
		}
		aptId = swfId;
		return true;
	}

	static std::uint16_t depthOf(const SwfTag &t)
	{
		if (t.code == SWF_TAG_PLACEOBJECT2 && t.body.size() >= 3)
		{
			return (std::uint16_t)(t.body[1] | (t.body[2] << 8));
		}
		if (t.code == SWF_TAG_REMOVEOBJECT2 && t.body.size() >= 2)
		{
			return (std::uint16_t)(t.body[0] | (t.body[1] << 8));
		}
		return 0;
	}

	// Lines up the frame items of one timeline (the regenerated export's against the SWF's), applies the edits of paired items, and
	// records the frames whose item list changed (items added, removed or reordered).
	bool compareTimeline(std::uint32_t id, const Timeline &want, const Timeline &got, std::string *error)
	{
		const std::string name = timelineName(id);
		if (want.frames.size() != got.frames.size())
		{
			return fail(error, name + " has " + std::to_string(got.frames.size()) + " frames where the movie has " + std::to_string(want.frames.size()) +
				": frames were added or removed (a structural edit not supported: frame items can be added and removed, frames cannot)");
		}
		if (got.trailing != 0)
		{
			return fail(error, name + ": " + std::to_string(got.trailing) + " tag(s) after the last ShowFrame (every item must be in a frame)");
		}
		const std::vector<AptFrame> *aptFrames = nullptr;
		if (id == 0)
		{
			aptFrames = &m_movie->frames;
		}
		else if (id < m_movie->characters.size() && m_movie->characters[id].type == APT_CHAR_SPRITE)
		{
			aptFrames = &m_movie->characters[id].frames;
		}
		for (std::size_t f = 0; f < want.frames.size(); ++f)
		{
			const std::vector<Entry> &E = want.frames[f];
			const std::vector<Entry> &G = got.frames[f];
			// anchors: the longest common subsequence of unedited items
			const std::size_t n = E.size(), m = G.size();
			std::vector<std::vector<std::uint16_t>> lcs(n + 1, std::vector<std::uint16_t>(m + 1, 0));
			for (std::size_t i = n; i-- > 0;)
			{
				for (std::size_t j = m; j-- > 0;)
				{
					lcs[i][j] = sameAsExported(E[i], *G[j].tag) ? (std::uint16_t)(lcs[i + 1][j + 1] + 1) : std::max(lcs[i + 1][j], lcs[i][j + 1]);
				}
			}
			std::vector<int> pairOf(m, -1); // G index -> E index
			std::vector<bool> exact(m, false);
			std::vector<std::pair<std::size_t, std::size_t>> anchors;
			for (std::size_t i = 0, j = 0; i < n && j < m;)
			{
				if (sameAsExported(E[i], *G[j].tag))
				{
					anchors.push_back({ i, j });
					pairOf[j] = (int)i;
					exact[j] = true;
					++i;
					++j;
				}
				else if (lcs[i + 1][j] >= lcs[i][j + 1])
				{
					++i;
				}
				else
				{
					++j;
				}
			}
			anchors.push_back({ n, m });
			// between anchors, an edited item is paired with the exported item of the same kind (same depth first for placements)
			std::vector<bool> eUsed(n, false);
			for (const auto &a : anchors)
			{
				if (a.first < n)
				{
					eUsed[a.first] = true;
				}
			}
			std::size_t ei = 0, gj = 0;
			for (const auto &a : anchors)
			{
				for (int pass = 0; pass < 2; ++pass)
				{
					for (std::size_t j = gj; j < a.second; ++j)
					{
						if (pairOf[j] >= 0)
						{
							continue;
						}
						for (std::size_t i = ei; i < a.first; ++i)
						{
							if (eUsed[i] || E[i].tag->code != G[j].tag->code)
							{
								continue;
							}
							const bool depthMatters = G[j].tag->code == SWF_TAG_PLACEOBJECT2 || G[j].tag->code == SWF_TAG_REMOVEOBJECT2;
							if (pass == 0 && depthMatters && depthOf(*E[i].tag) != depthOf(*G[j].tag))
							{
								continue;
							}
							eUsed[i] = true;
							pairOf[j] = (int)i;
							break;
						}
					}
				}
				ei = a.first + 1;
				gj = a.second + 1;
			}
			// edits of paired items, in place in their records
			for (std::size_t j = 0; j < m; ++j)
			{
				if (pairOf[j] < 0 || exact[j])
				{
					continue;
				}
				const Entry &w = E[(std::size_t)pairOf[j]];
				const std::size_t before = out.edits.size();
				if (!aptFrames || f >= aptFrames->size())
				{
					return fail(error, name + " frame " + std::to_string(f + 1) + ": no APT frame behind it");
				}
				if (!editItem(*G[j].tag, m_manifest[w.flat].origin, (*aptFrames)[f].items[(std::size_t)pairOf[j]], G[j].flat, error))
				{
					return false;
				}
				out.editedTags += out.edits.size() > before ? 1 : 0;
			}
			// the frame's item list changed: items added, removed or put in another order
			bool structural = false;
			int last = -1;
			for (std::size_t j = 0; j < m; ++j)
			{
				structural = structural || pairOf[j] < 0 || pairOf[j] < last;
				last = std::max(last, pairOf[j]);
			}
			for (std::size_t i = 0; i < n; ++i)
			{
				structural = structural || !eUsed[i];
			}
			if (!structural)
			{
				continue;
			}
			if (!aptFrames || f >= aptFrames->size())
			{
				return fail(error, name + " frame " + std::to_string(f + 1) + ": items were added to " +
					(aptFrames ? "a sprite with no APT frames" : "a placeholder for an APT character the converter cannot show (image, morph, ...)") +
					" (not supported)");
			}
			const std::string at = name + " frame " + std::to_string(f + 1);
			std::vector<std::uint32_t> items;
			for (std::size_t j = 0; j < m; ++j)
			{
				if (pairOf[j] >= 0)
				{
					items.push_back((*aptFrames)[f].items[(std::size_t)pairOf[j]].offset);
					continue;
				}
				std::uint32_t record = 0;
				if (!newItem(*G[j].tag, G[j].flat, (std::uint32_t)f, at, record, error))
				{
					return false;
				}
				items.push_back(record);
			}
			for (std::size_t i = 0; i < n; ++i)
			{
				if (!eUsed[i])
				{
					out.edits.push_back(at + ": removed " + describeItem((*aptFrames)[f].items[i]));
				}
			}
			m_frameItems[id][(std::uint32_t)f] = std::move(items);
			++out.editedTags;
		}
		return true;
	}

	static std::string describeItem(const AptFrameItem &it)
	{
		switch (it.type)
		{
			case APT_ITEM_PLACEOBJECT:
				return "place object (depth " + std::to_string(it.place->depth) + (it.place->name.empty() ? "" : ", '" + it.place->name + "'") + ")";
			case APT_ITEM_REMOVEOBJECT: return "remove object (depth " + std::to_string(it.removeDepth) + ")";
			case APT_ITEM_FRAMELABEL: return "frame label '" + it.label + "'";
			case APT_ITEM_ACTION: return "frame action";
			case APT_ITEM_INITACTION: return "init action";
			case APT_ITEM_BACKGROUNDCOLOR: return "background colour";
			default: return "item of type " + std::to_string(it.type);
		}
	}

	// an edited frame item, written into its record
	bool editItem(const SwfTag &tag, const TagOrigin &origin, const AptFrameItem &item, std::size_t index, std::string *error)
	{
		const std::string where = tagName(tag.code) + " #" + std::to_string(index);
		AptPatch p(m_apt);
		switch (tag.code)
		{
			case SWF_TAG_PLACEOBJECT2:
			case SWF_TAG_FRAMELABEL:
				return applyEdit(tag, origin, index, error);
			case SWF_TAG_REMOVEOBJECT2:
			{
				const std::uint16_t depth = depthOf(tag);
				if ((std::int32_t)depth != item.removeDepth)
				{
					p.putU32(item.offset + 4, depth);
					out.edits.push_back("remove object: depth " + std::to_string(item.removeDepth) + " -> " + std::to_string(depth));
					m_aptPatched = true;
				}
				return true;
			}
			case SWF_TAG_SETBACKGROUNDCOLOR:
				if (tag.body.size() < 3)
				{
					return fail(error, where + ": does not decode as a SetBackgroundColor");
				}
				for (int k = 0; k < 3; ++k)
				{
					m_apt[item.offset + 4 + k] = tag.body[k];
				}
				out.edits.push_back("background colour -> " + std::to_string(tag.body[0]) + " " + std::to_string(tag.body[1]) + " " + std::to_string(tag.body[2]));
				m_aptPatched = true;
				return true;
			default:
				return fail(error, where + " was edited; re-encoding a " + tagName(tag.code) +
					" into APT is not supported yet (action edits need the AVM1 -> APT assembler)");
		}
	}

	// a record appended to the .apt (4-byte aligned, like the file's own records); returns its offset
	std::uint32_t appendRecord(const SwfWriter &w)
	{
		while (m_apt.size() % 4)
		{
			m_apt.push_back(0);
		}
		const std::uint32_t at = (std::uint32_t)m_apt.size();
		m_apt.insert(m_apt.end(), w.bytes.begin(), w.bytes.end());
		m_aptPatched = true;
		return at;
	}

	// A frame item the SWF adds, as a new APT record.  Field values where SWF has none follow the retail records (RotWK 2.01's 47 822
	// place objects: character -1, identity matrix, tint FF FF FF FF, additive 0, ratio 0, name 0, clip depth -1, clip actions 0; its
	// 1 799 frame labels: flags 0x70000 and the frame's index; background colours: alpha FF).
	bool newItem(const SwfTag &tag, std::size_t index, std::uint32_t frame, const std::string &at, std::uint32_t &record, std::string *error)
	{
		const std::string where = tagName(tag.code) + " #" + std::to_string(index);
		switch (tag.code)
		{
			case SWF_TAG_PLACEOBJECT2:
			{
				SwfPlaceObject2 p;
				if (!decodePlaceObject2(tag.body, p))
				{
					return fail(error, where + ": does not decode as a PlaceObject2");
				}
				if (p.flags & 0x80)
				{
					return fail(error, where + ": a new placement with clip actions (onClipEvent code) needs the AVM1 -> APT assembler (not supported yet)");
				}
				std::uint32_t character = 0xFFFFFFFFu;
				if (p.flags & 0x02)
				{
					if (!aptCharacter(p.characterId, where, character, error))
					{
						return false;
					}
				}
				float m[6] = { 1, 0, 0, 1, 0, 0 };
				if (p.flags & 0x04)
				{
					swfMatrixToFloats(p.matrix, m);
				}
				std::uint8_t tint[4] = { 255, 255, 255, 255 }, add[4] = { 0, 0, 0, 0 };
				if (p.flags & 0x08)
				{
					for (int k = 0; k < 4; ++k)
					{
						const long t = std::lround(effMult(p.cxform, k) * 255.0 / 256.0);
						const std::int32_t a = effAdd(p.cxform, k);
						if (t < 0 || t > 255 || a < 0 || a > 255)
						{
							return fail(error, where + ": a colour transform outside APT's bytes (multiplier 0..1, add 0..255)");
						}
						tint[k] = (std::uint8_t)t;
						add[k] = (std::uint8_t)a;
					}
				}
				std::uint32_t name = 0;
				if (p.flags & 0x20)
				{
					AptPatch patch(m_apt);
					name = patch.appendString(p.name);
				}
				SwfWriter w;
				w.u32(APT_ITEM_PLACEOBJECT);
				w.u32(p.flags & 0x7Fu);
				w.u32(p.depth);
				w.u32(character);
				for (float v : m)
				{
					w.f32(v);
				}
				for (int k = 0; k < 4; ++k)
				{
					w.u8(tint[k]);
				}
				for (int k = 0; k < 4; ++k)
				{
					w.u8(add[k]);
				}
				w.f32((p.flags & 0x10) ? (float)(p.ratio / 65536.0) : 0.0f);
				w.u32(name);
				w.u32((p.flags & 0x40) ? (std::uint32_t)p.clipDepth : 0xFFFFFFFFu);
				w.u32(0); // clip actions
				record = appendRecord(w);
				out.edits.push_back(at + ": new place object (depth " + std::to_string(p.depth) +
					((p.flags & 0x02) ? ", character " + std::to_string(character) : std::string()) +
					((p.flags & 0x20) ? ", '" + p.name + "'" : std::string()) + ((p.flags & 0x04) ? ", at (" + fmt(m[4]) + ", " + fmt(m[5]) + ")" : std::string()) +
					")");
				return true;
			}
			case SWF_TAG_REMOVEOBJECT2:
			{
				SwfWriter w;
				w.u32(APT_ITEM_REMOVEOBJECT);
				w.u32(depthOf(tag));
				record = appendRecord(w);
				out.edits.push_back(at + ": new remove object (depth " + std::to_string(depthOf(tag)) + ")");
				return true;
			}
			case SWF_TAG_FRAMELABEL:
			{
				SwfReader r(tag.body.data(), tag.body.size());
				const std::string label = r.cstring();
				if (!r.ok())
				{
					return fail(error, where + ": does not decode as a FrameLabel");
				}
				AptPatch patch(m_apt);
				const std::uint32_t name = patch.appendString(label);
				SwfWriter w;
				w.u32(APT_ITEM_FRAMELABEL);
				w.u32(name);
				w.u32(0x70000); // every retail label's flags
				w.u32(frame);   // every retail label's frame id is its frame's index
				record = appendRecord(w);
				out.edits.push_back(at + ": new frame label '" + label + "'");
				return true;
			}
			case SWF_TAG_SETBACKGROUNDCOLOR:
			{
				if (tag.body.size() < 3)
				{
					return fail(error, where + ": does not decode as a SetBackgroundColor");
				}
				SwfWriter w;
				w.u32(APT_ITEM_BACKGROUNDCOLOR);
				w.u8(tag.body[0]);
				w.u8(tag.body[1]);
				w.u8(tag.body[2]);
				w.u8(255);
				record = appendRecord(w);
				out.edits.push_back(at + ": new background colour");
				return true;
			}
			default:
				return fail(error, where + " was added: a new " + tagName(tag.code) +
					" needs the AVM1 -> APT assembler (not supported yet); placements, removals, frame labels and text fields can be added");
		}
	}

	// A text field the SWF adds, as a new APT edit-text character (AptFile.cpp parseText's layout).
	bool newText(const Entry &g, std::string *error)
	{
		const std::string where = tagName(g.tag->code) + " #" + std::to_string(g.flat);
		SwfEditText t;
		if (!decodeEditText(g.tag->body, t))
		{
			return fail(error, where + ": does not decode as a DefineEditText");
		}
		if (!(t.flags1 & 0x01) || t.fontId >= m_movie->characters.size() || m_movie->characters[t.fontId].type != APT_CHAR_FONT)
		{
			return fail(error, where + ": a new text field needs one of the movie's fonts (an APT font character); " +
				((t.flags1 & 0x01) ? "character " + std::to_string(t.fontId) + " is not one" : std::string("it has none")));
		}
		const std::uint32_t align = (t.flags2 & 0x20) ? t.align : 0;
		if (align > 2)
		{
			return fail(error, where + ": alignment " + std::to_string(align) + " (justify) has no APT code");
		}
		std::uint8_t rgba[4] = { 255, 255, 255, 255 };
		if (t.flags1 & 0x04)
		{
			std::memcpy(rgba, t.color, 4);
		}
		AptPatch patch(m_apt);
		const std::uint32_t text = patch.appendString((t.flags1 & 0x80) ? t.initialText : std::string());
		const std::uint32_t variable = patch.appendString(t.variableName);
		SwfWriter w;
		w.u32(APT_CHAR_EDITTEXT);
		w.u32(0x09876543); // the character signature
		w.f32((float)(t.bounds[0] / 20.0)); // x0 y0 x1 y1 = SWF xmin ymin xmax ymax
		w.f32((float)(t.bounds[2] / 20.0));
		w.f32((float)(t.bounds[1] / 20.0));
		w.f32((float)(t.bounds[3] / 20.0));
		w.u32(t.fontId);
		w.u32(align);
		w.u8(rgba[2]); // the dword 0xAARRGGBB: bytes B G R A
		w.u8(rgba[1]);
		w.u8(rgba[0]);
		w.u8(rgba[3]);
		w.f32((float)(t.fontHeight / 20.0));
		w.u32((t.flags1 & 0x08) ? 1 : 0);
		w.u32((t.flags1 & 0x20) ? 1 : 0);
		w.u32((t.flags1 & 0x40) ? 1 : 0);
		w.u32(text);
		w.u32(variable);
		const std::uint32_t swfId = t.id;
		m_newCharacterRecords.push_back(appendRecord(w));
		out.edits.push_back("new text field " + std::to_string(swfId) + " -> APT character " + std::to_string(m_newCharacterIds.at(swfId)) + " ('" +
			((t.flags1 & 0x80) ? t.initialText : std::string()) + "', variable '" + t.variableName + "')");
		++out.editedTags;
		return true;
	}

	// The new item lists and characters, linked in: every changed timeline gets a new frame table (a copy of the old one with the
	// changed frames' item lists replaced), the movie a new character table when characters were added.  Only appended data is new;
	// the old tables stay in the file unreferenced (other records may share them).
	bool writeStructure(std::string *error)
	{
		AptPatch p(m_apt);
		const std::uint32_t movieRecord = m_movie->consts.aptDataEntryOffset + 8;
		for (const auto &tl : m_frameItems)
		{
			const std::uint32_t header = tl.first == 0 ? movieRecord : m_movie->characters[tl.first].offset + 8;
			const std::uint32_t count = p.u32(header);
			const std::uint32_t table = p.u32(header + 4);
			std::vector<std::uint32_t> lists(count);
			for (const auto &f : tl.second)
			{
				if (f.first >= count)
				{
					return fail(error, "internal error: frame " + std::to_string(f.first + 1) + " beyond " + timelineName(tl.first) + "'s frame table");
				}
				SwfWriter w;
				for (std::uint32_t item : f.second)
				{
					w.u32(item);
				}
				lists[f.first] = f.second.empty() ? 0 : appendRecord(w);
			}
			SwfWriter frames;
			for (std::uint32_t f = 0; f < count; ++f)
			{
				auto changed = tl.second.find(f);
				if (changed != tl.second.end())
				{
					frames.u32((std::uint32_t)changed->second.size());
					frames.u32(lists[f]);
				}
				else
				{
					frames.u32(p.u32(table + f * 8));
					frames.u32(p.u32(table + f * 8 + 4));
				}
			}
			p.putU32(header + 4, appendRecord(frames));
		}
		if (!m_newCharacterRecords.empty())
		{
			const std::uint32_t count = p.u32(movieRecord + 12);
			const std::uint32_t table = p.u32(movieRecord + 16);
			SwfWriter chars;
			for (std::uint32_t i = 0; i < count; ++i)
			{
				chars.u32(p.u32(table + i * 4));
			}
			for (std::uint32_t record : m_newCharacterRecords)
			{
				chars.u32(record);
			}
			const std::uint32_t at = appendRecord(chars);
			p.putU32(movieRecord + 12, count + (std::uint32_t)m_newCharacterRecords.size());
			p.putU32(movieRecord + 16, at);
		}
		return true;
	}

	std::vector<ManifestEntry> m_manifest;
	std::map<std::uint32_t, std::uint32_t> m_newCharacterIds; // SWF id -> APT id of the characters the SWF adds
	std::vector<const Entry *> m_newCharacters;
	std::vector<std::uint32_t> m_newCharacterRecords;         // their records, in APT id order
	std::map<std::uint32_t, std::map<std::uint32_t, std::vector<std::uint32_t>>> m_frameItems; // timeline -> frame -> item records

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
			std::uint32_t character = 0;
			if (!aptCharacter(got.characterId, whereTag, character, error))
			{
				return false;
			}
			p.putU32(at + 12, character);
			out.edits.push_back(what + ": character " + std::to_string(want.characterId) + " -> " + std::to_string(character));
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
