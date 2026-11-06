// OpenBFME. GPL-3.0.
// See AptSwfRecipe.h.

#include "Libraries/Source/Apt/AptSwfRecipe.h"

#include "Libraries/Source/Apt/AptSwfTags.h"

#include <cmath>
#include <cstdlib>
#include <map>
#include <sstream>

namespace aptswf
{

namespace
{

struct Line
{
	int number = 0;
	std::string verb;
	std::map<std::string, std::string> args; // key=value; a bare word is key=""
	std::string rest;                        // everything after the verb (note / movie lines)
};

bool tokenize(const std::string &text, int number, Line &out, std::string *error)
{
	out = Line();
	out.number = number;
	std::size_t i = 0;
	auto skip = [&]() {
		while (i < text.size() && (text[i] == ' ' || text[i] == '\t'))
		{
			++i;
		}
	};
	skip();
	const std::size_t verbStart = i;
	while (i < text.size() && text[i] != ' ' && text[i] != '\t')
	{
		++i;
	}
	out.verb = text.substr(verbStart, i - verbStart);
	skip();
	out.rest = text.substr(i);
	while (!out.rest.empty() && (out.rest.back() == ' ' || out.rest.back() == '\t'))
	{
		out.rest.pop_back();
	}
	if (out.verb == "note" || out.verb == "movie" || out.verb == "openbfme-apt-recipe")
	{
		return true;
	}
	while (i < text.size())
	{
		skip();
		if (i >= text.size())
		{
			break;
		}
		std::string key;
		while (i < text.size() && text[i] != '=' && text[i] != ' ' && text[i] != '\t')
		{
			key.push_back(text[i++]);
		}
		std::string value;
		if (i < text.size() && text[i] == '=')
		{
			++i;
			if (i < text.size() && text[i] == '"')
			{
				++i;
				bool closed = false;
				while (i < text.size())
				{
					if (text[i] == '\\' && i + 1 < text.size())
					{
						value.push_back(text[i + 1]);
						i += 2;
						continue;
					}
					if (text[i] == '"')
					{
						closed = true;
						++i;
						break;
					}
					value.push_back(text[i++]);
				}
				if (!closed)
				{
					*error = "line " + std::to_string(number) + ": a quoted value is not closed";
					return false;
				}
			}
			else
			{
				while (i < text.size() && text[i] != ' ' && text[i] != '\t')
				{
					value.push_back(text[i++]);
				}
			}
		}
		if (out.args.count(key))
		{
			*error = "line " + std::to_string(number) + ": '" + key + "' is given twice";
			return false;
		}
		out.args[key] = value;
	}
	return true;
}

class Applier
{
public:
	Applier(SwfFile &swf, RecipeResult &out) : m_swf(swf), m_out(out) {}

	bool run(const std::string &text, const std::string &movieName, std::string *error)
	{
		std::istringstream in(text);
		std::string raw;
		int number = 0;
		bool header = false;
		while (std::getline(in, raw))
		{
			++number;
			if (!raw.empty() && raw.back() == '\r')
			{
				raw.pop_back();
			}
			std::size_t start = raw.find_first_not_of(" \t");
			if (start == std::string::npos || raw[start] == '#')
			{
				continue;
			}
			Line line;
			if (!tokenize(raw, number, line, error))
			{
				return false;
			}
			m_line = &line;
			if (!header)
			{
				if (line.verb != "openbfme-apt-recipe" || line.rest != "1")
				{
					return fail(error, "the first line must be 'openbfme-apt-recipe 1' (this is not a recipe, or a newer format)");
				}
				header = true;
				continue;
			}
			bool ok = true;
			if (line.verb == "movie")
			{
				m_out.movie = line.rest;
				if (lower(line.rest) != lower(movieName))
				{
					return fail(error, "the recipe is for the movie '" + line.rest + "', not '" + movieName + "'");
				}
			}
			else if (line.verb == "note")
			{
				m_out.notes.push_back(line.rest);
			}
			else if (m_out.movie.empty())
			{
				return fail(error, "the 'movie' line must come before the edits");
			}
			else if (line.verb == "expect")
			{
				ok = expect(error);
			}
			else if (line.verb == "place")
			{
				ok = place(error);
			}
			else if (line.verb == "set")
			{
				ok = set(error);
			}
			else if (line.verb == "rename")
			{
				ok = rename(error);
			}
			else if (line.verb == "delete")
			{
				ok = remove(error);
			}
			else if (line.verb == "remove")
			{
				ok = addRemove(error);
			}
			else if (line.verb == "label")
			{
				ok = label(error);
			}
			else if (line.verb == "text")
			{
				ok = textField(error);
			}
			else
			{
				return fail(error, "unknown step '" + line.verb + "'");
			}
			if (!ok)
			{
				return false;
			}
		}
		if (!header)
		{
			return fail(error, "the recipe is empty");
		}
		if (m_out.movie.empty())
		{
			return fail(error, "the recipe has no 'movie' line");
		}
		return true;
	}

private:
	static std::string lower(std::string s)
	{
		for (char &c : s)
		{
			c = (char)std::tolower((unsigned char)c);
		}
		return s;
	}

	bool fail(std::string *error, const std::string &m) const
	{
		if (error)
		{
			*error = (m_line ? "line " + std::to_string(m_line->number) + " (" + m_line->verb + "): " : std::string()) + m;
		}
		return false;
	}

	// ---- arguments -------------------------------------------------------------------------------------------------------------
	bool has(const char *key) const { return m_line->args.count(key) != 0; }

	bool known(std::initializer_list<const char *> keys, std::string *error) const
	{
		for (const auto &a : m_line->args)
		{
			bool ok = false;
			for (const char *k : keys)
			{
				ok = ok || a.first == k;
			}
			if (!ok)
			{
				return fail(error, "unknown setting '" + a.first + "'");
			}
		}
		return true;
	}

	bool integer(const char *key, long &v, std::string *error) const
	{
		auto it = m_line->args.find(key);
		if (it == m_line->args.end())
		{
			return fail(error, std::string("needs ") + key + "=");
		}
		char *end = nullptr;
		v = std::strtol(it->second.c_str(), &end, 10);
		if (it->second.empty() || *end)
		{
			return fail(error, std::string(key) + "=" + it->second + " is not a whole number");
		}
		return true;
	}

	bool number(const char *key, double &v, std::string *error) const
	{
		auto it = m_line->args.find(key);
		if (it == m_line->args.end())
		{
			return fail(error, std::string("needs ") + key + "=");
		}
		char *end = nullptr;
		v = std::strtod(it->second.c_str(), &end);
		if (it->second.empty() || *end || !std::isfinite(v))
		{
			return fail(error, std::string(key) + "=" + it->second + " is not a number");
		}
		return true;
	}

	bool pair(const char *key, double &a, double &b, std::string *error) const
	{
		const std::string &s = m_line->args.at(key);
		const std::size_t comma = s.find(',');
		if (comma != std::string::npos && comma > 0 && comma + 1 < s.size())
		{
			const std::string first = s.substr(0, comma), second = s.substr(comma + 1);
			char *endA = nullptr, *endB = nullptr;
			a = std::strtod(first.c_str(), &endA);
			b = std::strtod(second.c_str(), &endB);
			if (!*endA && !*endB && std::isfinite(a) && std::isfinite(b))
			{
				return true;
			}
		}
		return fail(error, std::string(key) + "=" + s + " must be two numbers: " + key + "=a,b");
	}

	// ---- timelines ---------------------------------------------------------------------------------------------------------------
	// sprite=ID: the root's tags (0) or the sprite's children
	bool timeline(std::vector<SwfTag> *&tags, long &spriteId, std::string *error)
	{
		if (!integer("sprite", spriteId, error))
		{
			return false;
		}
		if (spriteId == 0)
		{
			tags = &m_swf.tags;
			return true;
		}
		for (SwfTag &t : m_swf.tags)
		{
			if (t.code == SWF_TAG_DEFINESPRITE && t.body.size() >= 4 && (long)(t.body[0] | (t.body[1] << 8)) == spriteId)
			{
				tags = &t.children;
				return true;
			}
		}
		return fail(error, "the movie has no sprite " + std::to_string(spriteId));
	}

	// the index in `tags` where a tag goes to end up last in frame `frame` (1-based): before that frame's ShowFrame
	bool frameEnd(std::vector<SwfTag> &tags, long frame, std::size_t &at, std::string *error) const
	{
		long f = 1;
		for (std::size_t i = 0; i < tags.size(); ++i)
		{
			if (tags[i].code == SWF_TAG_SHOWFRAME)
			{
				if (f == frame)
				{
					at = i;
					return true;
				}
				++f;
			}
		}
		return fail(error, "the timeline has " + std::to_string(f - 1) + " frames, no frame " + std::to_string(frame));
	}

	static long frameOf(const std::vector<SwfTag> &tags, std::size_t index)
	{
		long f = 1;
		for (std::size_t i = 0; i < index; ++i)
		{
			f += tags[i].code == SWF_TAG_SHOWFRAME ? 1 : 0;
		}
		return f;
	}

	// the one placing tag (with a character) that matches name= / depth= / frame= / character=; with both frame= and depth= also a Move tag
	// (a placement that only moves the instance at that depth in that frame)
	bool findPlacement(std::vector<SwfTag> &tags, std::size_t &index, SwfPlaceObject2 &p, std::string *error, const char *nameKey = "name")
	{
		if (!has(nameKey) && !has("depth"))
		{
			return fail(error, std::string("needs ") + nameKey + "= or depth= to find the placement");
		}
		long depth = -1, frame = -1, character = -1;
		if ((has("depth") && !integer("depth", depth, error)) || (has("frame") && !integer("frame", frame, error)) ||
			(has("character") && !integer("character", character, error)))
		{
			return false;
		}
		const bool moves = frame >= 0 && depth >= 0 && !has(nameKey);
		std::size_t found = 0;
		for (std::size_t i = 0; i < tags.size(); ++i)
		{
			SwfPlaceObject2 q;
			if (tags[i].code != SWF_TAG_PLACEOBJECT2 || !decodePlaceObject2(tags[i].body, q) || (!(q.flags & 0x02) && !moves))
			{
				continue;
			}
			if ((has(nameKey) && (!(q.flags & 0x20) || q.name != m_line->args.at(nameKey))) || (depth >= 0 && q.depth != depth) ||
				(character >= 0 && q.characterId != character) || (frame >= 0 && frameOf(tags, i) != frame))
			{
				continue;
			}
			if (found++ == 0)
			{
				index = i;
				p = q;
			}
		}
		if (found == 0)
		{
			return fail(error, "no placement matches (" + selector(nameKey) + ")");
		}
		if (found > 1)
		{
			return fail(error, std::to_string(found) + " placements match (" + selector(nameKey) + "): add frame= or depth= to pick one");
		}
		return true;
	}

	std::string selector(const char *nameKey) const
	{
		std::string s;
		for (const char *k : { "sprite", nameKey, "depth", "frame", "character" })
		{
			if (has(k))
			{
				s += (s.empty() ? "" : " ") + std::string(k == nameKey ? "name" : k) + "=" + m_line->args.at(k);
			}
		}
		return s;
	}

	// x= y= dx= dy= scale= on a placement's matrix
	bool position(SwfPlaceObject2 &p, std::string *error)
	{
		if (!(has("x") || has("y") || has("dx") || has("dy") || has("scale")))
		{
			return true;
		}
		if (!(p.flags & 0x04))
		{
			p.flags |= 0x04;
			p.matrix = SwfMatrix();
		}
		double v = 0;
		if (has("x"))
		{
			if (!number("x", v, error))
			{
				return false;
			}
			p.matrix.translateX = swfTwips((float)v);
		}
		if (has("y"))
		{
			if (!number("y", v, error))
			{
				return false;
			}
			p.matrix.translateY = swfTwips((float)v);
		}
		if (has("dx"))
		{
			if (!number("dx", v, error))
			{
				return false;
			}
			p.matrix.translateX += swfTwips((float)v);
		}
		if (has("dy"))
		{
			if (!number("dy", v, error))
			{
				return false;
			}
			p.matrix.translateY += swfTwips((float)v);
		}
		if (has("scale"))
		{
			double sx = 1, sy = 1;
			if (!pair("scale", sx, sy, error))
			{
				return false;
			}
			p.matrix.hasScale = true;
			p.matrix.scaleX = swfFixed16((float)sx);
			p.matrix.scaleY = swfFixed16((float)sy);
		}
		return true;
	}

	bool characterArg(std::uint16_t &id, std::string *error)
	{
		const std::string &v = m_line->args.at("character");
		auto named = m_texts.find(v);
		if (named != m_texts.end())
		{
			id = named->second;
			return true;
		}
		long n = 0;
		if (!integer("character", n, error))
		{
			return fail(error, "character=" + v + " is neither a number nor a text field this recipe made");
		}
		if (n <= 0 || n > 0xFFFF)
		{
			return fail(error, "character=" + v + " is out of range");
		}
		id = (std::uint16_t)n;
		return true;
	}

	// ---- steps -------------------------------------------------------------------------------------------------------------------
	bool expect(std::string *error)
	{
		if (!known({ "sprite", "name", "depth", "frame", "character" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0;
		std::size_t index = 0;
		SwfPlaceObject2 p;
		if (!timeline(tags, sprite, error))
		{
			return false;
		}
		if (!findPlacement(*tags, index, p, error))
		{
			return fail(error, "this copy of the movie is not the one the recipe was written for: " + error->substr(error->find(": ") + 2));
		}
		m_out.log.push_back("checked: sprite " + std::to_string(sprite) + " has " + selector("name"));
		return true;
	}

	bool place(std::string *error)
	{
		if (!known({ "sprite", "frame", "depth", "character", "name", "like", "x", "y", "dx", "dy", "scale", "move" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0, frame = 0, depth = 0;
		if (!timeline(tags, sprite, error) || !integer("frame", frame, error) || !integer("depth", depth, error))
		{
			return false;
		}
		if (depth <= 0 || depth > 0xFFFF)
		{
			return fail(error, "depth=" + std::to_string(depth) + " is out of range (1..65535)");
		}
		SwfPlaceObject2 p;
		if (has("like"))
		{
			std::size_t index = 0;
			// the template: by name only (its own frame and depth do not matter)
			Line copy = *m_line;
			Line like;
			like.number = copy.number;
			like.verb = copy.verb;
			like.args["like"] = copy.args["like"];
			m_line = &like;
			const bool found = findPlacement(*tags, index, p, error, "like");
			m_line = &copy;
			if (!found)
			{
				return false;
			}
			// the template's matrix, colour, ratio and clip depth; never its clip actions, its Move flag or its name
			p.flags &= (std::uint8_t)~(0x80 | 0x01 | 0x20);
			p.clipActions.clear();
			p.name.clear();
			return placeRest(tags, sprite, frame, depth, p, error, copy);
		}
		p.flags = 0; // the character flag comes with character=
		Line copy = *m_line;
		return placeRest(tags, sprite, frame, depth, p, error, copy);
	}

	bool placeRest(std::vector<SwfTag> *tags, long sprite, long frame, long depth, SwfPlaceObject2 &p, std::string *error, Line &line)
	{
		m_line = &line;
		p.depth = (std::uint16_t)depth;
		if (has("character"))
		{
			if (!characterArg(p.characterId, error))
			{
				return false;
			}
			p.flags |= 0x02;
		}
		else if (!has("like") && !has("move"))
		{
			return fail(error, "needs character= (or like= to copy an existing placement, or move to move the instance at that depth)");
		}
		if (has("move"))
		{
			p.flags |= 0x01;
		}
		if (has("name"))
		{
			p.flags |= 0x20;
			p.name = m_line->args.at("name");
		}
		if (!position(p, error))
		{
			return false;
		}
		// the depth must be free in that frame
		std::size_t at = 0;
		if (!frameEnd(*tags, frame, at, error))
		{
			return false;
		}
		for (std::size_t i = 0; i < at; ++i)
		{
			SwfPlaceObject2 q;
			if (!has("move") && tags->at(i).code == SWF_TAG_PLACEOBJECT2 && decodePlaceObject2(tags->at(i).body, q) && q.depth == depth &&
				(q.flags & 0x02) && frameOf(*tags, i) == frame)
			{
				return fail(error, "depth " + std::to_string(depth) + " is already used in frame " + std::to_string(frame) + " of sprite " +
					std::to_string(sprite) + " (pick a free depth)");
			}
		}
		SwfTag t;
		t.code = SWF_TAG_PLACEOBJECT2;
		t.body = encodePlaceObject2(p);
		tags->insert(tags->begin() + (std::ptrdiff_t)at, t);
		float m[6];
		swfMatrixToFloats(p.matrix, m);
		char buf[96];
		std::snprintf(buf, sizeof(buf), " at (%g, %g)", m[4], m[5]);
		m_out.log.push_back(std::string((p.flags & 0x01) ? "moved" : "placed") + ((p.flags & 0x02) ? " character " + std::to_string(p.characterId) : std::string()) + " in sprite " + std::to_string(sprite) + " frame " +
			std::to_string(frame) + " depth " + std::to_string(depth) + ((p.flags & 0x20) ? " as '" + p.name + "'" : std::string()) + buf);
		return true;
	}

	bool set(std::string *error)
	{
		if (!known({ "sprite", "name", "depth", "frame", "character", "x", "y", "dx", "dy", "scale", "to-depth", "to-character" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0;
		std::size_t index = 0;
		SwfPlaceObject2 p;
		if (!timeline(tags, sprite, error) || !findPlacement(*tags, index, p, error) || !position(p, error))
		{
			return false;
		}
		long v = 0;
		if (has("to-depth"))
		{
			if (!integer("to-depth", v, error))
			{
				return false;
			}
			p.depth = (std::uint16_t)v;
		}
		if (has("to-character"))
		{
			if (!integer("to-character", v, error))
			{
				return false;
			}
			p.characterId = (std::uint16_t)v;
		}
		(*tags)[index].body = encodePlaceObject2(p);
		m_out.log.push_back("changed the placement " + selector("name") + " in sprite " + std::to_string(sprite));
		return true;
	}

	bool rename(std::string *error)
	{
		if (!known({ "sprite", "name", "depth", "frame", "character", "to" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0;
		std::size_t index = 0;
		SwfPlaceObject2 p;
		if (!has("to"))
		{
			return fail(error, "needs to=NEWNAME");
		}
		if (!timeline(tags, sprite, error) || !findPlacement(*tags, index, p, error))
		{
			return false;
		}
		const std::string old = p.name;
		p.flags |= 0x20;
		p.name = m_line->args.at("to");
		(*tags)[index].body = encodePlaceObject2(p);
		m_out.log.push_back("renamed '" + old + "' to '" + p.name + "' in sprite " + std::to_string(sprite));
		return true;
	}

	bool remove(std::string *error)
	{
		if (!known({ "sprite", "name", "depth", "frame", "character" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0;
		std::size_t index = 0;
		SwfPlaceObject2 p;
		if (!timeline(tags, sprite, error) || !findPlacement(*tags, index, p, error))
		{
			return false;
		}
		tags->erase(tags->begin() + (std::ptrdiff_t)index);
		m_out.log.push_back("took the placement " + selector("name") + " out of sprite " + std::to_string(sprite));
		return true;
	}

	bool addRemove(std::string *error)
	{
		if (!known({ "sprite", "frame", "depth" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0, frame = 0, depth = 0;
		std::size_t at = 0;
		if (!timeline(tags, sprite, error) || !integer("frame", frame, error) || !integer("depth", depth, error) || !frameEnd(*tags, frame, at, error))
		{
			return false;
		}
		SwfWriter w;
		w.u16((std::uint32_t)depth);
		SwfTag t;
		t.code = SWF_TAG_REMOVEOBJECT2;
		t.body = w.bytes;
		tags->insert(tags->begin() + (std::ptrdiff_t)at, t);
		m_out.log.push_back("removes depth " + std::to_string(depth) + " in sprite " + std::to_string(sprite) + " frame " + std::to_string(frame));
		return true;
	}

	bool label(std::string *error)
	{
		if (!known({ "sprite", "frame", "name" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0, frame = 0;
		std::size_t at = 0;
		if (!has("name"))
		{
			return fail(error, "needs name=");
		}
		if (!timeline(tags, sprite, error) || !integer("frame", frame, error) || !frameEnd(*tags, frame, at, error))
		{
			return false;
		}
		SwfWriter w;
		w.cstring(m_line->args.at("name"));
		SwfTag t;
		t.code = SWF_TAG_FRAMELABEL;
		t.body = w.bytes;
		tags->insert(tags->begin() + (std::ptrdiff_t)at, t);
		m_out.log.push_back("labelled sprite " + std::to_string(sprite) + " frame " + std::to_string(frame) + " '" + m_line->args.at("name") + "'");
		return true;
	}

	bool textField(std::string *error)
	{
		if (!known({ "id", "font", "bounds", "height", "color", "align", "text", "var", "readonly", "multiline", "wordwrap" }, error))
		{
			return false;
		}
		if (!has("id") || m_line->args.at("id").empty())
		{
			return fail(error, "needs id=NAME (the name `place ... character=NAME` uses)");
		}
		const std::string id = m_line->args.at("id");
		if (m_texts.count(id))
		{
			return fail(error, "a text field called '" + id + "' was already made");
		}
		long font = 0;
		double height = 0, x0 = 0, y0 = 0, x1 = 0, y1 = 0;
		if (!integer("font", font, error) || !number("height", height, error))
		{
			return false;
		}
		if (!has("bounds"))
		{
			return fail(error, "needs bounds=x0,y0,x1,y1");
		}
		{
			std::istringstream b(m_line->args.at("bounds"));
			char c1 = 0, c2 = 0, c3 = 0;
			if (!(b >> x0 >> c1 >> y0 >> c2 >> x1 >> c3 >> y1) || c1 != ',' || c2 != ',' || c3 != ',')
			{
				return fail(error, "bounds=" + m_line->args.at("bounds") + " must be x0,y0,x1,y1");
			}
		}
		SwfEditText t;
		std::uint32_t maxId = 0;
		for (const SwfTag &tag : m_swf.tags)
		{
			if (tag.code != SWF_TAG_OPENBFME_APT && tag.code != SWF_TAG_SHOWFRAME && tag.body.size() >= 2 && tag.code != SWF_TAG_PLACEOBJECT2 &&
				tag.code != SWF_TAG_REMOVEOBJECT2 && tag.code != SWF_TAG_DOACTION && tag.code != SWF_TAG_FRAMELABEL && tag.code != SWF_TAG_EXPORTASSETS &&
				tag.code != SWF_TAG_IMPORTASSETS2 && tag.code != SWF_TAG_SETBACKGROUNDCOLOR && tag.code != SWF_TAG_DOINITACTION)
			{
				maxId = std::max<std::uint32_t>(maxId, (std::uint32_t)(tag.body[0] | (tag.body[1] << 8)));
			}
		}
		t.id = (std::uint16_t)(maxId + 1);
		t.bounds[0] = swfTwips((float)x0);
		t.bounds[1] = swfTwips((float)x1);
		t.bounds[2] = swfTwips((float)y0);
		t.bounds[3] = swfTwips((float)y1);
		t.flags1 = 0x01 | 0x04 | 0x80;
		t.flags1 |= has("readonly") ? 0x08 : 0;
		t.flags1 |= has("multiline") ? 0x20 : 0;
		t.flags1 |= has("wordwrap") ? 0x40 : 0;
		t.flags2 = 0x20;
		t.fontId = (std::uint16_t)font;
		t.fontHeight = (std::uint16_t)swfTwips((float)height);
		const std::string color = has("color") ? m_line->args.at("color") : "FFFFFFFF";
		if (color.size() != 8 || color.find_first_not_of("0123456789abcdefABCDEF") != std::string::npos)
		{
			return fail(error, "color=" + color + " must be 8 hex digits RRGGBBAA");
		}
		for (int k = 0; k < 4; ++k)
		{
			t.color[k] = (std::uint8_t)std::strtoul(color.substr((std::size_t)k * 2, 2).c_str(), nullptr, 16);
		}
		const std::string align = has("align") ? m_line->args.at("align") : "left";
		t.align = align == "left" ? 0 : align == "right" ? 1 : align == "center" ? 2 : 255;
		if (t.align == 255)
		{
			return fail(error, "align=" + align + " must be left, right or center");
		}
		t.initialText = has("text") ? m_line->args.at("text") : std::string();
		t.variableName = has("var") ? m_line->args.at("var") : std::string();
		SwfTag tag;
		tag.code = SWF_TAG_DEFINEEDITTEXT;
		tag.body = encodeEditText(t);
		// before the root timeline's first frame item, after the other definitions
		std::size_t at = 0;
		while (at < m_swf.tags.size() && (m_swf.tags[at].code == SWF_TAG_OPENBFME_APT || !(m_swf.tags[at].code == SWF_TAG_PLACEOBJECT2 ||
			m_swf.tags[at].code == SWF_TAG_SHOWFRAME || m_swf.tags[at].code == SWF_TAG_DOACTION || m_swf.tags[at].code == SWF_TAG_FRAMELABEL ||
			m_swf.tags[at].code == SWF_TAG_EXPORTASSETS || m_swf.tags[at].code == SWF_TAG_REMOVEOBJECT2 || m_swf.tags[at].code == SWF_TAG_DOINITACTION ||
			m_swf.tags[at].code == SWF_TAG_SETBACKGROUNDCOLOR)))
		{
			++at;
		}
		m_swf.tags.insert(m_swf.tags.begin() + (std::ptrdiff_t)at, tag);
		m_texts[id] = t.id;
		m_out.log.push_back("made text field '" + id + "' (SWF character " + std::to_string(t.id) + ")");
		return true;
	}

	SwfFile &m_swf;
	RecipeResult &m_out;
	const Line *m_line = nullptr;
	std::map<std::string, std::uint16_t> m_texts;
};

} // namespace

bool applyRecipe(const std::string &text, SwfFile &swf, const std::string &movieName, RecipeResult &out, std::string *error)
{
	out = RecipeResult();
	Applier a(swf, out);
	return a.run(text, movieName, error);
}

} // namespace aptswf
