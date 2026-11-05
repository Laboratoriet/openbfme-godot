// OpenBFME. GPL-3.0.
// See AptSwfExport.h.  SWF structures: SWF 19 chapters "Shapes" (DefineShape3, StyleChangeRecord with StateNewStyles,
// StraightEdgeRecord, FILLSTYLE 0x00 / 0x41), "Bitmaps" (DefineBitsLossless2 format 5: premultiplied ARGB), "Sprites and
// Movie Clips", "Buttons" (DefineButton2, BUTTONRECORD, BUTTONCONDACTION), "Fonts and Text" (DefineFont2, DefineEditText),
// "The Display List" (PlaceObject2, CLIPACTIONS), "Control Tags".

#include "Libraries/Source/Apt/AptSwfExport.h"

#include "Libraries/Source/Apt/AptActionDecoder.h"
#include "Libraries/Source/Apt/AptSwfAvm1.h"
#include "Libraries/Source/Apt/AptSwfTags.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>

namespace aptswf
{

const char kPrivateMagic[8] = { 'O', 'B', 'F', 'A', 'P', 'T', '1', 0 };

namespace
{

std::string lowerPath(const std::string &s)
{
	std::string o = s;
	for (char &c : o)
	{
		if (c >= 'A' && c <= 'Z')
		{
			c = (char)(c - 'A' + 'a');
		}
		else if (c == '\\')
		{
			c = '/';
		}
	}
	return o;
}

std::uint8_t clampByte(float v)
{
	return (std::uint8_t)std::max(0L, std::min(255L, std::lround(v)));
}

struct Pt
{
	std::int32_t x, y;
	bool operator<(const Pt &o) const { return x != o.x ? x < o.x : y < o.y; }
	bool operator==(const Pt &o) const { return x == o.x && y == o.y; }
};

// Shape record stream writer (bit level, SWF 19 "Shape structures").
class ShapeRecords
{
public:
	SwfWriter &w;
	Pt pen{ 0, 0 };
	int fillBits = 0, lineBits = 0;
	explicit ShapeRecords(SwfWriter &writer) : w(writer) {}

	// a style change that replaces the style arrays (one fill or one line style) and selects it
	void newStyles(const std::vector<std::uint8_t> &fillArray, const std::vector<std::uint8_t> &lineArray, int nFill, int nLine)
	{
		w.ub(1, 0); // TypeFlag
		w.ub(1, 1); // StateNewStyles
		w.ub(1, 0);
		w.ub(1, 0);
		w.ub(1, 0);
		w.ub(1, 0);
		w.raw(fillArray); // aligns
		w.raw(lineArray);
		w.ub(4, (std::uint32_t)nFill);
		w.ub(4, (std::uint32_t)nLine);
		fillBits = nFill;
		lineBits = nLine;
	}

	// Selects fill style 1 and the line style explicitly every time (0 = none, written in 0 bits when the layer has no such
	// styles): a player that keeps the previous layer's selection (Ruffle 0.7.1 does) would otherwise index the new layer's
	// empty style list.
	void moveTo(Pt p, int fill1, int line)
	{
		w.ub(1, 0);
		w.ub(1, 0);                     // StateNewStyles
		w.ub(1, line >= 0 ? 1 : 0);     // StateLineStyle
		w.ub(1, fill1 >= 0 ? 1 : 0);    // StateFillStyle1
		w.ub(1, 0);                     // StateFillStyle0
		w.ub(1, 1);                     // StateMoveTo
		const int n = std::max(swfSignedBits(p.x), swfSignedBits(p.y));
		w.ub(5, (std::uint32_t)n);
		w.sb(n, p.x);
		w.sb(n, p.y);
		if (fill1 >= 0)
		{
			w.ub(fillBits, (std::uint32_t)fill1);
		}
		if (line >= 0)
		{
			w.ub(lineBits, (std::uint32_t)line);
		}
		pen = p;
	}

	void lineTo(Pt p)
	{
		const std::int32_t dx = p.x - pen.x, dy = p.y - pen.y;
		if (dx == 0 && dy == 0)
		{
			return;
		}
		w.ub(1, 1); // TypeFlag: edge
		w.ub(1, 1); // StraightFlag
		const int n = std::max(2, std::max(swfSignedBits(dx), swfSignedBits(dy)));
		w.ub(4, (std::uint32_t)(n - 2));
		if (dx != 0 && dy != 0)
		{
			w.ub(1, 1); // GeneralLineFlag
			w.sb(n, dx);
			w.sb(n, dy);
		}
		else
		{
			w.ub(1, 0);
			w.ub(1, dx == 0 ? 1 : 0); // VertLineFlag
			w.sb(n, dx == 0 ? dy : dx);
		}
		pen = p;
	}

	void end()
	{
		w.ub(6, 0);
		w.align();
	}
};

std::vector<std::uint8_t> styleArray(const std::vector<std::uint8_t> &oneStyle)
{
	std::vector<std::uint8_t> a;
	a.push_back(oneStyle.empty() ? 0 : 1);
	a.insert(a.end(), oneStyle.begin(), oneStyle.end());
	return a;
}

// The boundary of a set of triangles: shared edges cancel, the rest is chained into closed loops.  Every triangle is first
// turned to the same winding so the filled side of every boundary edge is the same (fill style 1 = the right of the edge in
// SWF's y-down space).
std::vector<std::vector<Pt>> triangleOutlines(const std::vector<float> &tris, std::size_t &kept)
{
	std::map<std::pair<Pt, Pt>, int> edges; // directed edge -> multiplicity
	std::vector<std::pair<Pt, Pt>> order;    // first-seen order, for determinism
	kept = 0;
	for (std::size_t i = 0; i + 5 < tris.size(); i += 6)
	{
		Pt p[3];
		for (int v = 0; v < 3; ++v)
		{
			p[v] = Pt{ swfTwips(tris[i + v * 2]), swfTwips(tris[i + v * 2 + 1]) };
		}
		const std::int64_t area = (std::int64_t)(p[1].x - p[0].x) * (p[2].y - p[0].y) - (std::int64_t)(p[2].x - p[0].x) * (p[1].y - p[0].y);
		if (area == 0)
		{
			continue; // degenerate (and invisible) at twip precision
		}
		if (area < 0)
		{
			std::swap(p[1], p[2]);
		}
		++kept;
		for (int e = 0; e < 3; ++e)
		{
			const Pt a = p[e], b = p[(e + 1) % 3];
			auto rev = edges.find({ b, a });
			if (rev != edges.end() && rev->second > 0)
			{
				--rev->second;
				continue;
			}
			if (edges[{ a, b }]++ == 0)
			{
				order.push_back({ a, b });
			}
		}
	}
	std::multimap<Pt, Pt> from;
	for (const auto &e : order)
	{
		for (int k = 0; k < edges[e]; ++k)
		{
			from.insert({ e.first, e.second });
		}
	}
	std::vector<std::vector<Pt>> loops;
	for (const auto &e : order)
	{
		auto it = from.find(e.first);
		while (it != from.end() && !(it->second == e.second))
		{
			++it;
			if (it != from.end() && !(it->first == e.first))
			{
				it = from.end();
			}
		}
		if (it == from.end())
		{
			continue; // already used
		}
		std::vector<Pt> loop{ it->first };
		Pt cur = it->second;
		from.erase(it);
		loop.push_back(cur);
		while (!(cur == loop.front()))
		{
			auto next = from.find(cur);
			if (next == from.end())
			{
				break;
			}
			cur = next->second;
			from.erase(next);
			loop.push_back(cur);
		}
		loops.push_back(std::move(loop));
	}
	return loops;
}

} // namespace

// ---- the SWF form of single APT records (shared with the importer) ------------------------------------------------------------

bool programAvm1(const AptFile &movie, std::uint32_t codeOffset, Avm1Result &out, std::string *error)
{
	std::string e;
	std::shared_ptr<const AptCodeBlock> block = movie.codeAt(codeOffset, &e);
	if (!block)
	{
		if (error)
		{
			*error = e;
		}
		return false;
	}
	if (!aptToAvm1(*block, out, &e))
	{
		if (error)
		{
			*error = movie.name + ": program at " + std::to_string(codeOffset) + ": " + e;
		}
		return false;
	}
	return true;
}

SwfCxform aptPlaceCxform(const AptPlaceObject &p)
{
	SwfCxform c;
	for (int k = 0; k < 4; ++k)
	{
		c.mult[k] = (p.tint[k] * 256 + 127) / 255; // 255 -> 256 (1.0)
		c.add[k] = p.additive[k];
		c.hasMult = c.hasMult || p.tint[k] != 255;
		c.hasAdd = c.hasAdd || p.additive[k] != 0;
	}
	return c;
}

bool aptPlaceToSwf(const AptFile &movie, const AptPlaceObject &p, const ProgramBytes &programs, SwfPlaceObject2 &swf, std::set<std::string> &notes,
	std::string *error)
{
	swf = SwfPlaceObject2();
	const bool clipActions = (p.flags & APT_PLACE_HASCLIPACTION) && movie.version >= 5;
	swf.flags = (std::uint8_t)(p.flags & (clipActions ? 0xFFu : 0x7Fu));
	if (p.depth < 0 || p.depth > 0xFFFF)
	{
		notes.insert("place objects with a depth outside 0..65535 (SWF depths are 16 bits)");
	}
	swf.depth = (std::uint16_t)std::max(0, std::min(0xFFFF, p.depth));
	swf.characterId = (std::uint16_t)p.characterId;
	swf.matrix = swfMatrixFromFloats(p.matrix[0], p.matrix[1], p.matrix[2], p.matrix[3], p.translation[0], p.translation[1]);
	swf.cxform = aptPlaceCxform(p);
	// the ratio float is the SWF ratio / 65536 (AptCharacterInst.cpp: MenuExport.apt frame 9 has 9 / 65536)
	swf.ratio = (std::uint16_t)std::max(0L, std::min(0xFFFFL, std::lround(p.ratio * 65536.0)));
	swf.name = p.name;
	swf.clipDepth = (std::uint16_t)std::max(0, std::min(0xFFFF, p.clipDepth));
	if (clipActions)
	{
		SwfWriter w;
		std::uint32_t all = 0;
		for (const AptClipEvent &e : p.clipEvents)
		{
			all |= e.mask;
		}
		w.u16(0);
		w.u32(all); // ClipEventFlags: APT's 24-bit mask is SWF's bit for bit (AptFile.h AptClipEventFlags)
		for (const AptClipEvent &e : p.clipEvents)
		{
			std::vector<std::uint8_t> code;
			if (!programs(e.codeOffset, code, error))
			{
				return false;
			}
			w.u32(e.mask);
			const bool key = (e.mask & APT_CLIP_KEYPRESS) != 0;
			w.u32((std::uint32_t)(code.size() + (key ? 1 : 0)));
			if (key)
			{
				w.u8(e.keyCode);
			}
			w.raw(code);
			if (e.mask & APT_CLIP_MOUSEWHEEL)
			{
				notes.insert("clip events with the 0x80000 bit (no SWF event)");
			}
		}
		w.u32(0);
		if (p.clipActionsNull)
		{
			notes.insert("place objects flagged with clip actions but a null list: written as an empty CLIPACTIONS");
		}
		swf.clipActions = std::move(w.bytes);
	}
	return true;
}

SwfEditText aptTextToSwf(std::uint32_t id, const AptTextInfo &t)
{
	SwfEditText s;
	s.id = (std::uint16_t)id;
	s.bounds[0] = swfTwips(t.bounds[0]);
	s.bounds[1] = swfTwips(t.bounds[2]);
	s.bounds[2] = swfTwips(t.bounds[1]);
	s.bounds[3] = swfTwips(t.bounds[3]);
	s.flags1 = 0x80 | 0x04 | 0x01; // HasText, HasTextColor, HasFont
	s.flags1 |= t.wordWrap ? 0x40 : 0;
	s.flags1 |= t.multiline ? 0x20 : 0;
	s.flags1 |= t.readOnly ? 0x08 : 0;
	s.flags2 = 0x20; // HasLayout (the alignment)
	s.fontId = (std::uint16_t)t.fontId;
	s.fontHeight = (std::uint16_t)std::max(0L, std::min(0xFFFFL, std::lround(t.fontHeight * 20.0)));
	for (int k = 0; k < 4; ++k)
	{
		s.color[k] = t.color[k];
	}
	s.align = (std::uint8_t)t.alignment; // 0 left, 1 right, 2 centre: SWF's codes
	s.variableName = t.variableName;
	s.initialText = t.initialText;
	return s;
}

bool buttonNeedsHitShape(const AptFile &movie, const AptButtonInfo &b)
{
	for (const AptButtonRecord &r : b.records)
	{
		if (r.stateMask == 8 && r.characterId < movie.characters.size() && movie.characters[r.characterId].type == APT_CHAR_SHAPE)
		{
			return true;
		}
	}
	return false;
}

SwfCxform aptButtonCxform(const AptButtonRecord &r)
{
	SwfCxform c;
	for (int k = 0; k < 4; ++k)
	{
		c.mult[k] = (std::int32_t)std::lround(r.color[k] * 256.0);
		c.hasMult = c.hasMult || c.mult[k] != 256;
	}
	return c;
}

bool aptButtonToSwf(const AptFile &movie, const AptCharacter &c, std::uint32_t hitShape, const ProgramBytes &programs, SwfButton2 &swf,
	std::set<std::string> &notes, std::string *error)
{
	const AptButtonInfo &b = *c.button;
	swf = SwfButton2();
	swf.id = (std::uint16_t)c.id;
	swf.flags = b.isMenu ? 1 : 0;
	for (const AptButtonRecord &r : b.records)
	{
		SwfButtonRecord rec;
		rec.flags = (std::uint8_t)(r.stateMask & 0x0F);
		const bool useHit = hitShape && r.stateMask == 8 && r.characterId < movie.characters.size() &&
			movie.characters[r.characterId].type == APT_CHAR_SHAPE;
		rec.characterId = (std::uint16_t)(useHit ? hitShape : r.characterId);
		rec.depth = (std::uint16_t)std::max(0, std::min(0xFFFF, r.depth));
		rec.matrix = swfMatrixFromFloats(r.matrix[0], r.matrix[1], r.matrix[2], r.matrix[3], r.translation[0], r.translation[1]);
		rec.cxform = aptButtonCxform(r);
		if (r.unknown[0] != 0 || r.unknown[1] != 0 || r.unknown[2] != 0 || r.unknown[3] != 0)
		{
			notes.insert("button records with non-zero values in the 4 floats after the colour (+52..+67, meaning unknown): not in the SWF");
		}
		swf.records.push_back(rec);
	}
	SwfWriter w;
	for (std::size_t i = 0; i < b.actions.size(); ++i)
	{
		const AptButtonAction &a = b.actions[i];
		std::vector<std::uint8_t> code;
		if (!programs(a.codeOffset, code, error))
		{
			return false;
		}
		w.u16(i + 1 < b.actions.size() ? (std::uint32_t)(4 + code.size()) : 0);
		// the first flag byte is APT's transition mask bit for bit (IdleToOverUp 0x01 .. OutDownToIdle 0x40: AptInput.cpp);
		// the second is the key code (7 bits) and OverDownToIdle
		w.u8(a.transitionMask);
		if (a.keyCode > 127)
		{
			notes.insert("button actions with a key code above 127 (SWF's CondKeyPress is 7 bits)");
		}
		if (a.transitionMask & 0x80)
		{
			notes.insert("button transition bit 0x80: written as SWF's IdleToOverDown (byte 0 bit 7); AptFile.h names it OverDownToIdle");
		}
		w.u8((std::uint32_t)((a.keyCode & 0x7F) << 1));
		w.raw(code);
	}
	swf.condActions = std::move(w.bytes);
	return true;
}

namespace
{

class Exporter
{
public:
	Exporter(const AptMovieFiles &files, const ExportOptions &options, ExportResult &out) : m_files(files), m_options(options), m_out(out) {}

	bool run(std::string *error)
	{
		const AptMovieFile *apt = m_files.find(m_files.name + ".apt");
		const AptMovieFile *cst = m_files.find(m_files.name + ".const");
		if (!apt || !cst)
		{
			return fail(error, m_files.name + ": the movie needs " + m_files.name + ".apt and " + m_files.name + ".const");
		}
		AptConstFile consts;
		std::string e;
		if (!AptConstFile::parse(cst->bytes, consts, &e))
		{
			return fail(error, m_files.name + e);
		}
		auto movie = std::make_shared<AptFile>();
		if (!AptFile::parse(m_files.name, std::make_shared<const std::vector<std::uint8_t>>(apt->bytes), consts, *movie, &e))
		{
			return fail(error, e);
		}
		m_movie = movie;
		m_out.movie = movie;
		if (const AptMovieFile *dat = m_files.find(m_files.name + ".dat"))
		{
			if (!AptImageMap::parse(dat->bytes, m_imageMap, &e))
			{
				return fail(error, m_files.name + e);
			}
		}
		m_nextId = (std::uint32_t)movie->characters.size();
		if (m_nextId == 0)
		{
			m_nextId = 1;
		}

		// header: stage size in twips, frame rate 1000 / ms per frame as 8.8
		m_out.header.version = (std::uint8_t)movie->version;
		m_out.header.frameWidthTwips = (std::int32_t)movie->width * 20;
		m_out.header.frameHeightTwips = (std::int32_t)movie->height * 20;
		m_out.header.frameRate8_8 = (std::uint16_t)std::min<long>(0xFFFF, std::lround(1000.0 * 256.0 / movie->msPerFrame));
		m_out.header.frameCount = (std::uint16_t)std::max<std::size_t>(1, movie->frames.size());

		// imports first (they fill character slots used by the definitions)
		for (const AptImport &im : movie->imports)
		{
			SwfWriter w;
			w.cstring(im.movie + ".swf");
			w.u8(1); // reserved, must be 1
			w.u8(0);
			w.u16(1);
			w.u16(im.characterId);
			w.cstring(im.name);
			emit(m_out.tags, SWF_TAG_IMPORTASSETS2, w.bytes);
			++m_out.stats.imports;
		}

		// character definitions, dependencies first
		for (std::uint32_t id = 1; id < movie->characters.size(); ++id)
		{
			if (!define(id, 0, error))
			{
				return false;
			}
		}

		if (!movie->exports.empty())
		{
			SwfWriter w;
			w.u16((std::uint32_t)movie->exports.size());
			for (const AptExport &ex : movie->exports)
			{
				w.u16(ex.characterId);
				w.cstring(ex.name);
			}
			emit(m_out.tags, SWF_TAG_EXPORTASSETS, w.bytes);
			m_out.stats.exports = movie->exports.size();
		}

		return timeline(movie->frames, true, m_out.tags, error);
	}

private:
	static bool fail(std::string *error, const std::string &m)
	{
		if (error)
		{
			*error = m;
		}
		return false;
	}

	void note(const std::string &n) { m_out.notes.insert(n); }

	void emit(std::vector<SwfTag> &into, std::uint16_t code, std::vector<std::uint8_t> body, TagOrigin origin = TagOrigin())
	{
		SwfTag t;
		t.code = code;
		t.body = std::move(body);
		t.forceLong = code == SWF_TAG_DEFINEBITSLOSSLESS2;
		t.originKind = (std::uint8_t)origin.kind;
		t.originOffset = origin.aptOffset;
		t.originId = origin.characterId;
		into.push_back(std::move(t));
	}

	// ---- definitions ---------------------------------------------------------------------------------------------------
	bool define(std::uint32_t id, int depth, std::string *error)
	{
		if (m_defined.count(id) || id >= m_movie->characters.size())
		{
			return true;
		}
		if (depth > 256)
		{
			return true; // a reference cycle: the remaining order is id order
		}
		m_defined.insert(id);
		const AptCharacter &c = m_movie->characters[id];
		// dependencies first
		for (std::uint32_t dep : dependencies(c))
		{
			if (!define(dep, depth + 1, error))
			{
				return false;
			}
		}
		switch (c.type)
		{
			case APT_CHAR_NULL:
				return true; // an import slot (ImportAssets2 above)
			case APT_CHAR_SHAPE:
				return defineShape(c, error);
			case APT_CHAR_SPRITE:
			{
				SwfTag sprite;
				sprite.code = SWF_TAG_DEFINESPRITE;
				SwfWriter w;
				w.u16(id);
				w.u16((std::uint32_t)std::max<std::size_t>(1, c.frames.size()));
				sprite.body = w.bytes;
				m_out.tags.push_back(std::move(sprite));
				// the dependencies are defined, so m_out.tags does not grow while the children are written
				const std::size_t at = m_out.tags.size() - 1;
				std::vector<SwfTag> children;
				if (!timeline(c.frames, false, children, error))
				{
					return false;
				}
				m_out.tags[at].children = std::move(children);
				++m_out.stats.sprites;
				return true;
			}
			case APT_CHAR_FONT:
			{
				SwfWriter w;
				w.u16(id);
				w.u8(0x04); // WideCodes (required from SWF 6); no layout, no glyphs: a device font by name
				w.u8(1);    // language: Latin
				const std::string name = c.fontName.substr(0, 255);
				w.u8((std::uint32_t)name.size());
				w.raw((const std::uint8_t *)name.data(), name.size());
				w.u16(0);   // NumGlyphs
				emit(m_out.tags, SWF_TAG_DEFINEFONT2, w.bytes);
				++m_out.stats.fonts;
				if (!c.glyphs.empty())
				{
					note("fonts: APT font characters carry a glyph list (" + std::string("u32 per glyph") +
						") but no outlines; SWF gets a device font by name only (text renders in the player's substitute face)");
				}
				return true;
			}
			case APT_CHAR_EDITTEXT:
				return defineText(c);
			case APT_CHAR_BUTTON:
				return defineButton(c, error);
			default:
			{
				// Movie (non-root) / Sound / Image / Morph / StaticText / None / Video: no decoded layout (AptFile.h: opaque).
				// An empty one-frame sprite keeps the id placeable; the record is in the private tag.
				static const char *names[] = { "null", "shape", "edit text", "font", "button", "sprite", "sound", "image", "morph", "movie",
					"static text", "none", "video" };
				note(std::string("characters of APT type ") + std::to_string(c.type) + " (" + (c.type < 13 ? names[c.type] : "?") +
					") have no decoded layout: exported as empty placeholder sprites");
				SwfWriter w;
				w.u16(id);
				w.u16(1);
				SwfTag sprite;
				sprite.code = SWF_TAG_DEFINESPRITE;
				sprite.body = w.bytes;
				SwfTag show;
				show.code = SWF_TAG_SHOWFRAME;
				sprite.children.push_back(show);
				m_out.tags.push_back(std::move(sprite));
				++m_out.stats.placeholders;
				return true;
			}
		}
	}

	std::vector<std::uint32_t> dependencies(const AptCharacter &c) const
	{
		std::vector<std::uint32_t> deps;
		auto addFrames = [&](const std::vector<AptFrame> &frames) {
			for (const AptFrame &f : frames)
			{
				for (const AptFrameItem &it : f.items)
				{
					if (it.type == APT_ITEM_PLACEOBJECT && it.place && (it.place->flags & APT_PLACE_HASCHARACTER) && it.place->characterId > 0)
					{
						deps.push_back((std::uint32_t)it.place->characterId);
					}
				}
			}
		};
		if (c.type == APT_CHAR_SPRITE)
		{
			addFrames(c.frames);
		}
		else if (c.type == APT_CHAR_BUTTON && c.button)
		{
			for (const AptButtonRecord &r : c.button->records)
			{
				deps.push_back(r.characterId);
			}
		}
		else if (c.type == APT_CHAR_EDITTEXT && c.text)
		{
			deps.push_back(c.text->fontId);
		}
		return deps;
	}

	std::uint32_t allocId() { return m_nextId++; }

	// the bitmap character of a texture (made once per texture)
	bool bitmapFor(const std::string &textureName, std::uint32_t &bitmapId, int &w, int &h)
	{
		auto it = m_bitmaps.find(lowerPath(textureName));
		if (it != m_bitmaps.end())
		{
			bitmapId = it->second.id;
			w = it->second.w;
			h = it->second.h;
			return bitmapId != 0;
		}
		Bitmap &b = m_bitmaps[lowerPath(textureName)];
		// the id and the fill do not depend on whether the texture loads, so the standard tags' structure is a function of the
		// APT files alone (the importer regenerates it without textures); a texture that does not load is a 1 x 1 transparent
		// stand-in
		b.id = allocId();
		AptTexture tex;
		std::string e = "no texture source";
		if (!m_options.textures || !m_options.textures(textureName, tex, &e) || tex.width <= 0 || tex.height <= 0 || tex.width > 65535 ||
			tex.height > 65535)
		{
			if (m_options.textures)
			{
				note("textures: " + textureName + " could not be loaded (" + e + "); a 1 x 1 transparent bitmap stands in");
			}
			tex.width = tex.height = 1;
			tex.rgba.assign(4, 0);
		}
		b.w = tex.width;
		b.h = tex.height;
		std::vector<std::uint8_t> argb((std::size_t)tex.width * tex.height * 4);
		for (std::size_t p = 0; p < (std::size_t)tex.width * tex.height; ++p)
		{
			const std::uint32_t a = tex.rgba[p * 4 + 3];
			argb[p * 4] = (std::uint8_t)a;
			for (int k = 0; k < 3; ++k)
			{
				argb[p * 4 + 1 + k] = (std::uint8_t)((tex.rgba[p * 4 + k] * a + 127) / 255); // premultiplied (SWF 19: DefineBitsLossless2)
			}
		}
		SwfWriter w2;
		w2.u16(b.id);
		w2.u8(5); // 32-bit ARGB
		w2.u16((std::uint32_t)tex.width);
		w2.u16((std::uint32_t)tex.height);
		w2.raw(zlibStore(argb.data(), argb.size()));
		emit(m_out.tags, SWF_TAG_DEFINEBITSLOSSLESS2, w2.bytes);
		++m_out.stats.bitmaps;
		bitmapId = b.id;
		w = b.w;
		h = b.h;
		return true;
	}

	const AptImageMapEntry *imageEntry(std::int32_t imageId) const
	{
		for (const AptImageMapEntry &e : m_imageMap.entries)
		{
			if ((std::int32_t)e.imageId == imageId)
			{
				return &e;
			}
		}
		return nullptr;
	}

	bool loadGeometry(std::uint32_t geometryId, AptGeometry &geo, bool &found)
	{
		found = false;
		const AptMovieFile *ru = m_files.find(m_files.name + "_geometry/" + std::to_string(geometryId) + ".ru");
		if (!ru)
		{
			return true;
		}
		found = true;
		std::string e;
		if (!AptGeometry::parse(ru->bytes, geo, &e))
		{
			note("geometry " + std::to_string(geometryId) + ".ru does not parse (" + e + "): exported empty");
			found = false;
		}
		return true;
	}

	// One DefineShape3 from styled geometry.  Each APT style group is a new style layer (StateNewStyles), drawn above the
	// previous ones as APT draws its groups in order.
	std::vector<std::uint8_t> shapeBody(std::uint32_t id, const AptGeometry &geo, const float aptBounds[4], bool haveBounds)
	{
		// bounds: the geometry's (with half line widths), else the character's
		std::int64_t x0 = INT32_MAX, y0 = INT32_MAX, x1 = INT32_MIN, y1 = INT32_MIN;
		auto grow = [&](float x, float y, float pad) {
			x0 = std::min<std::int64_t>(x0, swfTwips(x - pad));
			y0 = std::min<std::int64_t>(y0, swfTwips(y - pad));
			x1 = std::max<std::int64_t>(x1, swfTwips(x + pad));
			y1 = std::max<std::int64_t>(y1, swfTwips(y + pad));
		};
		for (const AptGeometryStyle &s : geo.styles)
		{
			for (std::size_t i = 0; i + 1 < s.triangles.size(); i += 2)
			{
				grow(s.triangles[i], s.triangles[i + 1], 0);
			}
			for (std::size_t i = 0; i + 1 < s.lines.size(); i += 2)
			{
				grow(s.lines[i], s.lines[i + 1], s.lineWidth * 0.5f);
			}
		}
		if (x0 > x1)
		{
			if (haveBounds)
			{
				grow(aptBounds[0], aptBounds[1], 0);
				grow(aptBounds[2], aptBounds[3], 0);
			}
			else
			{
				x0 = y0 = x1 = y1 = 0;
			}
		}
		// a degenerate shape (retail has all-zero placeholder geometry) still gets a 1-twip box: some tools refuse empty bounds
		x1 = std::max(x1, x0 + 1);
		y1 = std::max(y1, y0 + 1);
		SwfWriter w;
		w.u16(id);
		w.rect((std::int32_t)x0, (std::int32_t)x1, (std::int32_t)y0, (std::int32_t)y1);
		w.u8(0); // no fill styles before the first layer
		w.u8(0); // no line styles
		w.ub(4, 0);
		w.ub(4, 0);
		ShapeRecords rec(w);
		for (const AptGeometryStyle &s : geo.styles)
		{
			std::vector<std::uint8_t> style;
			if (s.kind == APT_STYLE_LINE)
			{
				SwfWriter sw;
				sw.u16((std::uint32_t)std::max<long>(0, std::min<long>(0xFFFF, std::lround(s.lineWidth * 20.0))));
				for (int k = 0; k < 4; ++k)
				{
					sw.u8(clampByte(s.rgba[k]));
				}
				rec.newStyles(styleArray({}), styleArray(sw.bytes), 0, 1);
				Pt pen{ INT32_MIN, INT32_MIN };
				for (std::size_t i = 0; i + 3 < s.lines.size(); i += 4)
				{
					const Pt a{ swfTwips(s.lines[i]), swfTwips(s.lines[i + 1]) };
					const Pt b{ swfTwips(s.lines[i + 2]), swfTwips(s.lines[i + 3]) };
					if (!(a == pen))
					{
						rec.moveTo(a, 0, 1);
					}
					rec.lineTo(b);
					pen = b;
					++m_out.stats.lines;
				}
				continue;
			}
			SwfWriter sw;
			if (s.kind == APT_STYLE_TEXTURED)
			{
				std::uint32_t bitmapId = 0;
				int tw = 0, th = 0;
				const AptImageMapEntry *entry = imageEntry(s.imageId);
				bool ok = false;
				if (!entry)
				{
					note("textured fills whose image id has no .dat entry are left out");
				}
				else
				{
					const std::string tex = "apt_" + m_files.name + "_" + std::to_string(entry->isRect ? entry->imageId : entry->textureId) + ".tga";
					ok = bitmapFor(tex, bitmapId, tw, th);
					if (entry->isRect)
					{
						note("image map 'N=x y w h' entries (own texture with a rectangle): the rectangle is not applied (its meaning is "
							 "unverified, S-109)");
					}
				}
				if (!ok)
				{
					continue;
				}
				if (s.rgba[0] != 255 || s.rgba[1] != 255 || s.rgba[2] != 255 || s.rgba[3] != 255)
				{
					note("textured fills with a colour other than white (a per-style tint) have no SWF form: the tint is dropped");
				}
				// APT maps shape pixels to texture pixels (AptCanvas.cpp pushVertex: u = uv0*x + uv2*y + uv4); SWF maps bitmap pixels to
				// shape twips.  So the SWF matrix is 20 * inverse(uv).
				const float *uv = s.uv;
				const double det = (double)uv[0] * uv[3] - (double)uv[1] * uv[2];
				if (std::fabs(det) < 1e-12)
				{
					note("textured fills with a singular texture matrix are left out");
					continue;
				}
				const double ia = uv[3] / det, ib = -uv[1] / det, ic = -uv[2] / det, id = uv[0] / det;
				const double itx = -(ia * uv[4] + ic * uv[5]), ity = -(ib * uv[4] + id * uv[5]);
				SwfMatrix m;
				m.hasScale = true;
				m.scaleX = (std::int32_t)std::lround(ia * 20 * 65536);
				m.scaleY = (std::int32_t)std::lround(id * 20 * 65536);
				m.rotateSkew0 = (std::int32_t)std::lround(ib * 20 * 65536);
				m.rotateSkew1 = (std::int32_t)std::lround(ic * 20 * 65536);
				m.hasRotate = m.rotateSkew0 != 0 || m.rotateSkew1 != 0;
				m.translateX = (std::int32_t)std::lround(itx * 20);
				m.translateY = (std::int32_t)std::lround(ity * 20);
				sw.u8(0x41); // clipped bitmap fill
				sw.u16(bitmapId);
				sw.matrix(m);
			}
			else
			{
				sw.u8(0x00);
				for (int k = 0; k < 4; ++k)
				{
					sw.u8(clampByte(s.rgba[k]));
				}
			}
			rec.newStyles(styleArray(sw.bytes), styleArray({}), 1, 0);
			std::size_t kept = 0;
			for (const std::vector<Pt> &loop : triangleOutlines(s.triangles, kept))
			{
				rec.moveTo(loop.front(), 1, 0);
				for (std::size_t i = 1; i < loop.size(); ++i)
				{
					rec.lineTo(loop[i]);
				}
			}
			m_out.stats.triangles += s.triangles.size() / 6;
		}
		rec.end();
		return w.bytes;
	}

	bool defineShape(const AptCharacter &c, std::string *)
	{
		AptGeometry geo;
		bool found = false;
		loadGeometry(c.geometryId, geo, found);
		if (!found)
		{
			note("shapes without a geometry file are exported empty");
		}
		// the bitmaps a shape uses are defined before it
		std::vector<SwfTag> &into = m_out.tags;
		std::vector<std::uint8_t> body = shapeBody(c.id, geo, c.bounds, true);
		emit(into, SWF_TAG_DEFINESHAPE3, std::move(body));
		++m_out.stats.shapes;
		return true;
	}

	bool defineText(const AptCharacter &c)
	{
		const AptTextInfo &t = *c.text;
		TagOrigin origin;
		origin.kind = TagOrigin::Kind::EditText;
		origin.aptOffset = c.offset;
		origin.characterId = c.id;
		emit(m_out.tags, SWF_TAG_DEFINEEDITTEXT, encodeEditText(aptTextToSwf(c.id, t)), origin);
		++m_out.stats.texts;
		for (unsigned char ch : t.initialText)
		{
			if (ch >= 0x80)
			{
				note("text fields with non-ASCII bytes: the bytes are written as they are (SWF 6+ reads UTF-8)");
				break;
			}
		}
		return true;
	}

	bool defineButton(const AptCharacter &c, std::string *error)
	{
		const AptButtonInfo &b = *c.button;
		// the hit mesh: APT tests Hit records against the button's own triangles (AptButtonInst::hitTest, RW 0x00AFA420); SWF
		// tests the record's character.  A shape made from the mesh replaces the character of hit-only shape records.
		std::uint32_t hitShape = 0;
		if (buttonNeedsHitShape(*m_movie, b) && !b.triangles.empty())
		{
			AptGeometry geo;
			AptGeometryStyle s;
			s.kind = APT_STYLE_SOLID;
			s.rgba[0] = s.rgba[1] = s.rgba[2] = 0;
			s.rgba[3] = 255;
			for (std::size_t i = 0; i + 2 < b.triangles.size(); i += 3)
			{
				for (int k = 0; k < 3; ++k)
				{
					s.triangles.push_back(b.vertices[b.triangles[i + k] * 2]);
					s.triangles.push_back(b.vertices[b.triangles[i + k] * 2 + 1]);
				}
			}
			geo.styles.push_back(s);
			hitShape = allocId();
			emit(m_out.tags, SWF_TAG_DEFINESHAPE3, shapeBody(hitShape, geo, b.bounds, true));
		}
		SwfButton2 swf;
		if (!aptButtonToSwf(*m_movie, c, hitShape, programs(), swf, m_out.notes, error))
		{
			return false;
		}
		TagOrigin origin;
		origin.kind = TagOrigin::Kind::Button;
		origin.aptOffset = c.offset;
		origin.characterId = c.id;
		emit(m_out.tags, SWF_TAG_DEFINEBUTTON2, encodeButton2(swf), origin);
		++m_out.stats.buttons;
		return true;
	}

	// ---- timelines -----------------------------------------------------------------------------------------------------
	ProgramBytes programs()
	{
		return [this](std::uint32_t codeOffset, std::vector<std::uint8_t> &out, std::string *error) { return actions(codeOffset, out, error); };
	}

	bool actions(std::uint32_t codeOffset, std::vector<std::uint8_t> &out, std::string *error)
	{
		auto it = m_programs.find(codeOffset);
		if (it != m_programs.end())
		{
			out = it->second;
			return true;
		}
		Avm1Result r;
		std::string e;
		if (!programAvm1(*m_movie, codeOffset, r, &e))
		{
			// a program the engine's decoder refuses (an opcode outside its RotWK census): an empty action list in the SWF,
			// the original bytes stay in the private tag
			const std::size_t op = e.find("opcode 0x");
			note("actions: programs the engine's decoder refuses are written as empty action lists (" +
				(op == std::string::npos ? e : e.substr(op, 11) + " is outside its RotWK census") + ")");
			r = Avm1Result();
			r.bytes = { 0x00 };
		}
		(void)error;
		for (const std::string &n : r.notes)
		{
			note("actions: " + n);
		}
		++m_out.stats.programs;
		m_out.stats.instructions += r.instructions;
		m_out.stats.eaOpcodes += r.eaOpcodes;
		m_programs[codeOffset] = r.bytes;
		out = std::move(r.bytes);
		return true;
	}

	bool timeline(const std::vector<AptFrame> &frames, bool root, std::vector<SwfTag> &into, std::string *error)
	{
		for (const AptFrame &f : frames)
		{
			for (const AptFrameItem &it : f.items)
			{
				switch (it.type)
				{
					case APT_ITEM_PLACEOBJECT:
					{
						std::vector<std::uint8_t> body;
						if (!placeObjectBody(*it.place, body, error))
						{
							return false;
						}
						TagOrigin o;
						o.kind = TagOrigin::Kind::PlaceObject;
						o.aptOffset = it.offset;
						emit(into, SWF_TAG_PLACEOBJECT2, std::move(body), o);
						break;
					}
					case APT_ITEM_REMOVEOBJECT:
					{
						SwfWriter w;
						w.u16((std::uint32_t)std::max(0, std::min(0xFFFF, it.removeDepth)));
						emit(into, SWF_TAG_REMOVEOBJECT2, w.bytes);
						break;
					}
					case APT_ITEM_ACTION:
					{
						std::vector<std::uint8_t> code;
						if (!actions(it.codeOffset, code, error))
						{
							return false;
						}
						emit(into, SWF_TAG_DOACTION, std::move(code));
						break;
					}
					case APT_ITEM_INITACTION:
					{
						std::vector<std::uint8_t> code;
						if (!actions(it.codeOffset, code, error))
						{
							return false;
						}
						if (!root)
						{
							note("init actions inside a sprite timeline (SWF allows DoInitAction on the root only): written as DoAction");
							emit(into, SWF_TAG_DOACTION, std::move(code));
							break;
						}
						SwfWriter w;
						w.u16(it.spriteId);
						w.raw(code);
						emit(into, SWF_TAG_DOINITACTION, w.bytes);
						break;
					}
					case APT_ITEM_FRAMELABEL:
					{
						SwfWriter w;
						w.cstring(it.label);
						TagOrigin o;
						o.kind = TagOrigin::Kind::FrameLabel;
						o.aptOffset = it.offset;
						emit(into, SWF_TAG_FRAMELABEL, w.bytes, o);
						if (it.labelFlags != 0)
						{
							note("frame labels carry EA fields (flags, frame id) that SWF has no place for (kept in the private tag)");
						}
						break;
					}
					case APT_ITEM_BACKGROUNDCOLOR:
					{
						SwfWriter w;
						w.u8(it.color[0]);
						w.u8(it.color[1]);
						w.u8(it.color[2]);
						emit(into, SWF_TAG_SETBACKGROUNDCOLOR, w.bytes);
						if (!root)
						{
							note("background colour items inside sprites (SWF reads SetBackgroundColor on the root only)");
						}
						break;
					}
					default:
						break;
				}
			}
			SwfTag show;
			show.code = SWF_TAG_SHOWFRAME;
			emitTag(into, std::move(show));
		}
		if (frames.empty())
		{
			SwfTag show;
			show.code = SWF_TAG_SHOWFRAME;
			emitTag(into, std::move(show));
		}
		return true;
	}

	void emitTag(std::vector<SwfTag> &into, SwfTag t)
	{
		into.push_back(std::move(t));
	}

	bool placeObjectBody(const AptPlaceObject &p, std::vector<std::uint8_t> &out, std::string *error)
	{
		SwfPlaceObject2 swf;
		if (!aptPlaceToSwf(*m_movie, p, programs(), swf, m_out.notes, error))
		{
			return false;
		}
		out = encodePlaceObject2(swf);
		return true;
	}

private:
	struct Bitmap
	{
		std::uint32_t id = 0;
		int w = 0, h = 0;
	};

private:
	const AptMovieFiles &m_files;
	const ExportOptions &m_options;
	ExportResult &m_out;
	std::shared_ptr<AptFile> m_movie;
	AptImageMap m_imageMap;
	std::set<std::uint32_t> m_defined;
	std::map<std::string, Bitmap> m_bitmaps;
	std::map<std::uint32_t, std::vector<std::uint8_t>> m_programs;
	std::uint32_t m_nextId = 1;
};

} // namespace

const AptMovieFile *AptMovieFiles::find(const std::string &path) const
{
	const std::string want = lowerPath(path);
	for (const AptMovieFile &f : files)
	{
		if (lowerPath(f.path) == want)
		{
			return &f;
		}
	}
	return nullptr;
}

std::vector<std::vector<std::pair<std::int32_t, std::int32_t>>> triangleOutlinesTwips(const std::vector<float> &triangles)
{
	std::size_t kept = 0;
	std::vector<std::vector<std::pair<std::int32_t, std::int32_t>>> out;
	for (const std::vector<Pt> &loop : triangleOutlines(triangles, kept))
	{
		out.emplace_back();
		for (const Pt &p : loop)
		{
			out.back().push_back({ p.x, p.y });
		}
	}
	return out;
}

std::vector<const SwfTag *> flattenTags(const std::vector<SwfTag> &tags)
{
	std::vector<const SwfTag *> out;
	for (const SwfTag &t : tags)
	{
		out.push_back(&t);
		for (const SwfTag &c : t.children)
		{
			out.push_back(&c);
		}
	}
	return out;
}

std::vector<SwfTag *> flattenTagsMutable(std::vector<SwfTag> &tags)
{
	std::vector<SwfTag *> out;
	for (SwfTag &t : tags)
	{
		out.push_back(&t);
		for (SwfTag &c : t.children)
		{
			out.push_back(&c);
		}
	}
	return out;
}

std::string tagDigest(const SwfTag &tag)
{
	std::vector<std::uint8_t> b;
	b.push_back((std::uint8_t)tag.code);
	b.push_back((std::uint8_t)(tag.code >> 8));
	b.insert(b.end(), tag.body.begin(), tag.body.end());
	return sha256Hex(b);
}

bool exportStandardTags(const AptMovieFiles &movie, const ExportOptions &options, ExportResult &out, std::string *error)
{
	out = ExportResult();
	Exporter ex(movie, options, out);
	if (!ex.run(error))
	{
		return false;
	}
	for (const SwfTag *t : flattenTags(out.tags))
	{
		TagOrigin o;
		o.kind = (TagOrigin::Kind)t->originKind;
		o.aptOffset = t->originOffset;
		o.characterId = t->originId;
		out.origins.push_back(o);
	}
	return true;
}

bool exportSwf(const AptMovieFiles &movie, const ExportOptions &options, std::vector<std::uint8_t> &swf, ExportResult &out, std::string *error)
{
	if (!exportStandardTags(movie, options, out, error))
	{
		return false;
	}
	std::vector<SwfTag> all;
	if (options.embedOriginal)
	{
		// the manifest: movie name, producer, the digest of every standard tag in the flattened order
		SwfWriter m;
		m.raw((const std::uint8_t *)kPrivateMagic, 8);
		m.u8(PRIVATE_MANIFEST);
		m.cstring(movie.name);
		m.cstring(options.producer);
		const std::vector<const SwfTag *> flat = flattenTags(out.tags);
		m.u32((std::uint32_t)flat.size());
		for (const SwfTag *t : flat)
		{
			const std::string hex = tagDigest(*t);
			for (std::size_t i = 0; i + 1 < hex.size(); i += 2)
			{
				m.u8((std::uint32_t)std::stoul(hex.substr(i, 2), nullptr, 16));
			}
			m.u8(t->originKind);
			m.u32(t->originOffset);
			m.u32(t->originId);
		}
		SwfTag manifest;
		manifest.code = SWF_TAG_OPENBFME_APT;
		manifest.body = m.bytes;
		manifest.forceLong = true;
		all.push_back(std::move(manifest));
		// the original files, in archive order
		for (const AptMovieFile &f : movie.files)
		{
			SwfWriter w;
			w.raw((const std::uint8_t *)kPrivateMagic, 8);
			w.u8(PRIVATE_FILE);
			w.cstring(f.path);
			w.u32((std::uint32_t)f.bytes.size());
			w.raw(f.bytes);
			SwfTag t;
			t.code = SWF_TAG_OPENBFME_APT;
			t.body = w.bytes;
			t.forceLong = true;
			all.push_back(std::move(t));
		}
	}
	all.insert(all.end(), out.tags.begin(), out.tags.end());
	swf = swfWriteFile(out.header, all);
	return true;
}

} // namespace aptswf
