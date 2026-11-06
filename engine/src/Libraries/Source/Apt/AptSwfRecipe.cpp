// OpenBFME. GPL-3.0.
// See AptSwfRecipe.h.

#include "Libraries/Source/Apt/AptSwfRecipe.h"

#include "Libraries/Source/Apt/AptSwfTags.h"

#include <climits>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <map>
#include <sstream>
#include <tuple>

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

// ---- p-code: the text form of AVM1 the `action` step takes (JPEXS's p-code names) ----------------------------------------------
struct PcodeOp
{
	const char *name;
	std::uint8_t opcode;
};

// the single-byte actions the APT runtime has (AptActionDecoder's census), by their SWF / JPEXS names
const PcodeOp kPcodeOps[] = { { "NextFrame", 0x04 }, { "Play", 0x06 }, { "Stop", 0x07 }, { "Subtract", 0x0B }, { "Multiply", 0x0C },
	{ "Divide", 0x0D }, { "Not", 0x12 }, { "StringEquals", 0x13 }, { "Pop", 0x17 }, { "ToInteger", 0x18 }, { "GetVariable", 0x1C },
	{ "SetVariable", 0x1D }, { "StringAdd", 0x21 }, { "GetProperty", 0x22 }, { "SetProperty", 0x23 }, { "CloneSprite", 0x24 },
	{ "RemoveSprite", 0x25 }, { "Trace", 0x26 }, { "RandomNumber", 0x30 }, { "Delete", 0x3A }, { "Delete2", 0x3B }, { "DefineLocal", 0x3C },
	{ "CallFunction", 0x3D }, { "Return", 0x3E }, { "Modulo", 0x3F }, { "NewObject", 0x40 }, { "DefineLocal2", 0x41 }, { "InitArray", 0x42 },
	{ "InitObject", 0x43 }, { "TypeOf", 0x44 }, { "Add2", 0x47 }, { "Less2", 0x48 }, { "Equals2", 0x49 }, { "ToNumber", 0x4A },
	{ "ToString", 0x4B }, { "PushDuplicate", 0x4C }, { "GetMember", 0x4E }, { "SetMember", 0x4F }, { "Increment", 0x50 },
	{ "Decrement", 0x51 }, { "CallMethod", 0x52 }, { "Enumerate2", 0x55 }, { "BitAnd", 0x60 }, { "BitRShift", 0x64 }, { "Greater", 0x67 } };

struct PcodeLine
{
	int number = 0;
	std::string text; // trimmed
};

class Pcode
{
public:
	explicit Pcode(const std::vector<PcodeLine> &lines) : m_lines(lines) {}

	// the whole action list, End added
	bool program(std::vector<std::uint8_t> &out, std::string *error)
	{
		std::size_t at = 0;
		if (!block(at, false, out, error))
		{
			return false;
		}
		out.push_back(0x00);
		return true;
	}

private:
	bool fail(std::string *error, int number, const std::string &m) const
	{
		if (error)
		{
			*error = "p-code line " + std::to_string(number) + ": " + m;
		}
		return false;
	}

	static void put16(std::vector<std::uint8_t> &b, std::uint32_t v)
	{
		b.push_back((std::uint8_t)v);
		b.push_back((std::uint8_t)(v >> 8));
	}

	static void put32(std::vector<std::uint8_t> &b, std::uint32_t v)
	{
		for (int i = 0; i < 4; ++i)
		{
			b.push_back((std::uint8_t)(v >> (8 * i)));
		}
	}

	static void record(std::vector<std::uint8_t> &out, std::uint8_t op, const std::vector<std::uint8_t> &payload)
	{
		out.push_back(op);
		put16(out, (std::uint32_t)payload.size());
		out.insert(out.end(), payload.begin(), payload.end());
	}

	// "a string" with \" \\ \n escapes, starting at s[i]
	static bool quoted(const std::string &s, std::size_t &i, std::string &out)
	{
		if (i >= s.size() || s[i] != '"')
		{
			return false;
		}
		++i;
		out.clear();
		while (i < s.size() && s[i] != '"')
		{
			if (s[i] == '\\' && i + 1 < s.size())
			{
				const char c = s[i + 1];
				out.push_back(c == 'n' ? '\n' : c == 't' ? '\t' : c == 'r' ? '\r' : c);
				i += 2;
				continue;
			}
			out.push_back(s[i++]);
		}
		if (i >= s.size())
		{
			return false;
		}
		++i;
		return true;
	}

	static void skipSpaces(const std::string &s, std::size_t &i)
	{
		while (i < s.size() && (s[i] == ' ' || s[i] == '\t'))
		{
			++i;
		}
	}

	static std::string word(const std::string &s, std::size_t &i)
	{
		skipSpaces(s, i);
		std::string w;
		while (i < s.size() && s[i] != ' ' && s[i] != '\t' && s[i] != ',')
		{
			w.push_back(s[i++]);
		}
		return w;
	}

	bool pushValues(const std::string &s, std::size_t i, int number, std::vector<std::uint8_t> &payload, std::string *error) const
	{
		while (true)
		{
			skipSpaces(s, i);
			if (i >= s.size())
			{
				return payload.empty() ? fail(error, number, "Push without a value") : true;
			}
			if (s[i] == '"')
			{
				std::string str;
				if (!quoted(s, i, str))
				{
					return fail(error, number, "an unclosed string");
				}
				payload.push_back(0);
				payload.insert(payload.end(), str.begin(), str.end());
				payload.push_back(0);
			}
			else
			{
				const std::string w = word(s, i);
				if (w == "true" || w == "false")
				{
					payload.push_back(5);
					payload.push_back(w == "true" ? 1 : 0);
				}
				else if (w == "null")
				{
					payload.push_back(2);
				}
				else if (w == "undefined")
				{
					payload.push_back(3);
				}
				else if (w.rfind("register", 0) == 0 && w.size() > 8)
				{
					char *end = nullptr;
					const long r = std::strtol(w.c_str() + 8, &end, 10);
					if (*end || r < 0 || r > 255)
					{
						return fail(error, number, "'" + w + "' is not a register (register0 .. register255)");
					}
					payload.push_back(4);
					payload.push_back((std::uint8_t)r);
				}
				else
				{
					char *end = nullptr;
					const bool decimal = w.find_first_of(".eE") != std::string::npos;
					if (!decimal)
					{
						const long long v = std::strtoll(w.c_str(), &end, 10);
						if (w.empty() || *end || v < INT32_MIN || v > INT32_MAX)
						{
							return fail(error, number, "'" + w + "' is not a Push value (\"string\", an integer, a number, true, false, null, undefined, registerN)");
						}
						payload.push_back(7);
						put32(payload, (std::uint32_t)(std::int32_t)v);
					}
					else
					{
						const float f = std::strtof(w.c_str(), &end);
						if (*end || !std::isfinite(f))
						{
							return fail(error, number, "'" + w + "' is not a number");
						}
						std::uint32_t bits;
						std::memcpy(&bits, &f, 4);
						payload.push_back(1);
						put32(payload, bits);
					}
				}
			}
			skipSpaces(s, i);
			if (i < s.size())
			{
				if (s[i] != ',')
				{
					return fail(error, number, "Push values are separated by commas");
				}
				++i;
			}
		}
	}

	// the lines from `at` to the end (or to the `}` closing a function body), as AVM1
	bool block(std::size_t &at, bool function, std::vector<std::uint8_t> &out, std::string *error)
	{
		std::map<std::string, std::size_t> labels;                             // label -> offset in `out`
		std::vector<std::tuple<std::size_t, std::string, int>> branches; // (offset of the s16, label, line)
		while (at < m_lines.size())
		{
			const PcodeLine &l = m_lines[at++];
			const std::string &s = l.text;
			if (s == "}")
			{
				if (!function)
				{
					return fail(error, l.number, "a '}' without a function");
				}
				function = false;
				break;
			}
			if (s.back() == ':' && s.find(' ') == std::string::npos)
			{
				const std::string name = s.substr(0, s.size() - 1);
				if (labels.count(name))
				{
					return fail(error, l.number, "the label '" + name + "' is defined twice");
				}
				labels[name] = out.size();
				continue;
			}
			std::size_t i = 0;
			const std::string op = word(s, i);
			if (op == "Push")
			{
				std::vector<std::uint8_t> payload;
				if (!pushValues(s, i, l.number, payload, error))
				{
					return false;
				}
				record(out, 0x96, payload);
			}
			else if (op == "Jump" || op == "If")
			{
				const std::string label = word(s, i);
				out.push_back(op == "Jump" ? 0x99 : 0x9D);
				put16(out, 2);
				branches.emplace_back(out.size(), label, l.number);
				put16(out, 0);
			}
			else if (op == "GotoFrame" || op == "StoreRegister")
			{
				char *end = nullptr;
				const std::string w = word(s, i);
				const long v = std::strtol(w.c_str(), &end, 10);
				if (w.empty() || *end || v < 0 || v > (op == "GotoFrame" ? 65535 : 255))
				{
					return fail(error, l.number, op + " needs a number");
				}
				std::vector<std::uint8_t> payload;
				if (op == "GotoFrame")
				{
					put16(payload, (std::uint32_t)v);
				}
				else
				{
					payload.push_back((std::uint8_t)v);
				}
				record(out, op == "GotoFrame" ? 0x81 : 0x87, payload);
			}
			else if (op == "GotoLabel" || op == "GetURL")
			{
				std::vector<std::uint8_t> payload;
				for (int k = 0; k < (op == "GetURL" ? 2 : 1); ++k)
				{
					skipSpaces(s, i);
					std::string str;
					if (!quoted(s, i, str))
					{
						return fail(error, l.number, op + " needs " + (op == "GetURL" ? "two quoted strings" : "a quoted label"));
					}
					payload.insert(payload.end(), str.begin(), str.end());
					payload.push_back(0);
				}
				record(out, op == "GetURL" ? 0x83 : 0x8C, payload);
			}
			else if (op == "DefineFunction")
			{
				// DefineFunction "name" N "param1" ... {
				skipSpaces(s, i);
				std::string name;
				if (!quoted(s, i, name))
				{
					return fail(error, l.number, "DefineFunction \"name\" N \"param\"... {");
				}
				char *end = nullptr;
				const std::string w = word(s, i);
				const long n = std::strtol(w.c_str(), &end, 10);
				if (w.empty() || *end || n < 0 || n > 255)
				{
					return fail(error, l.number, "DefineFunction needs its parameter count");
				}
				std::vector<std::uint8_t> payload(name.begin(), name.end());
				payload.push_back(0);
				put16(payload, (std::uint32_t)n);
				for (long k = 0; k < n; ++k)
				{
					skipSpaces(s, i);
					std::string p;
					if (!quoted(s, i, p))
					{
						return fail(error, l.number, "DefineFunction has " + std::to_string(n) + " parameter names in quotes");
					}
					payload.insert(payload.end(), p.begin(), p.end());
					payload.push_back(0);
				}
				skipSpaces(s, i);
				if (i >= s.size() || s[i] != '{' || i + 1 != s.size())
				{
					return fail(error, l.number, "DefineFunction's line ends with '{' (its body follows, closed by a '}' line)");
				}
				std::vector<std::uint8_t> body;
				if (!block(at, true, body, error))
				{
					return false;
				}
				if (body.size() > 0xFFFF)
				{
					return fail(error, l.number, "a function body above 64 KiB");
				}
				put16(payload, (std::uint32_t)body.size());
				record(out, 0x9B, payload);
				out.insert(out.end(), body.begin(), body.end());
			}
			else
			{
				bool found = false;
				for (const PcodeOp &o : kPcodeOps)
				{
					if (op == o.name)
					{
						out.push_back(o.opcode);
						found = true;
					}
				}
				if (!found)
				{
					return fail(error, l.number, "'" + op + "' is not an action this p-code takes (see docs/APT-SWF.md \"Recipes\")");
				}
				std::size_t j = i;
				if (!word(s, j).empty())
				{
					return fail(error, l.number, op + " takes no operand");
				}
			}
		}
		if (function)
		{
			return fail(error, m_lines.empty() ? 0 : m_lines.back().number, "a function body without its closing '}'");
		}
		for (const auto &b : branches)
		{
			auto it = labels.find(std::get<1>(b));
			if (it == labels.end())
			{
				return fail(error, std::get<2>(b), "no label '" + std::get<1>(b) + "' in this block");
			}
			const std::int64_t rel = (std::int64_t)it->second - (std::int64_t)(std::get<0>(b) + 2);
			if (rel < -32768 || rel > 32767)
			{
				return fail(error, std::get<2>(b), "a branch beyond 32 KiB");
			}
			out[std::get<0>(b)] = (std::uint8_t)(rel & 0xFF);
			out[std::get<0>(b) + 1] = (std::uint8_t)((rel >> 8) & 0xFF);
		}
		return true;
	}

	const std::vector<PcodeLine> &m_lines;
};

class Applier
{
public:
	Applier(SwfFile &swf, RecipeResult &out) : m_swf(swf), m_out(out) {}

	bool run(const std::string &text, const std::string &movieName, std::string *error)
	{
		std::istringstream in(text);
		std::vector<std::string> all;
		for (std::string l; std::getline(in, l);)
		{
			if (!l.empty() && l.back() == '\r')
			{
				l.pop_back();
			}
			all.push_back(l);
		}
		bool header = false;
		for (std::size_t li = 0; li < all.size(); ++li)
		{
			const std::string &raw = all[li];
			const int number = (int)li + 1;
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
			else if (line.verb == "action")
			{
				// the p-code lines up to `end`
				std::vector<PcodeLine> code;
				bool closed = false;
				while (++li < all.size())
				{
					std::string t = all[li];
					const std::size_t a = t.find_first_not_of(" \t");
					t = a == std::string::npos ? std::string() : t.substr(a, t.find_last_not_of(" \t") - a + 1);
					if (t == "end")
					{
						closed = true;
						break;
					}
					if (!t.empty() && t[0] != ';' && t[0] != '#')
					{
						code.push_back({ (int)li + 1, t });
					}
				}
				if (!closed)
				{
					return fail(error, "an action without its 'end' line");
				}
				ok = action(code, error);
			}
			else if (line.verb == "value")
			{
				ok = value(error);
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

	// action sprite=S frame=F, then p-code lines, then `end`: a new DoAction at the end of that frame
	bool action(const std::vector<PcodeLine> &code, std::string *error)
	{
		if (!known({ "sprite", "frame" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0, frame = 0;
		std::size_t at = 0;
		if (!timeline(tags, sprite, error) || !integer("frame", frame, error) || !frameEnd(*tags, frame, at, error))
		{
			return false;
		}
		SwfTag t;
		t.code = SWF_TAG_DOACTION;
		Pcode pc(code);
		std::string e;
		if (!pc.program(t.body, &e))
		{
			return fail(error, e);
		}
		tags->insert(tags->begin() + (std::ptrdiff_t)at, t);
		m_out.log.push_back("added a frame action (" + std::to_string(code.size()) + " p-code lines, " + std::to_string(t.body.size()) +
			" AVM1 bytes) to sprite " + std::to_string(sprite) + " frame " + std::to_string(frame));
		return true;
	}

	// value sprite=S frame=F action=N old=V new=W [count=C]: the integer V pushed in the frame's N-th action list becomes W (every
	// one of them; there must be exactly C, default 1)
	bool value(std::string *error)
	{
		if (!known({ "sprite", "frame", "action", "old", "new", "count" }, error))
		{
			return false;
		}
		std::vector<SwfTag> *tags = nullptr;
		long sprite = 0, frame = 0, index = 0, oldValue = 0, newValue = 0, count = 1;
		if (!timeline(tags, sprite, error) || !integer("frame", frame, error) || !integer("action", index, error) || !integer("old", oldValue, error) ||
			!integer("new", newValue, error) || (has("count") && !integer("count", count, error)))
		{
			return false;
		}
		SwfTag *target = nullptr;
		long seen = 0;
		for (std::size_t i = 0; i < tags->size(); ++i)
		{
			if ((*tags)[i].code == SWF_TAG_DOACTION && frameOf(*tags, i) == frame && ++seen == index)
			{
				target = &(*tags)[i];
			}
		}
		if (!target)
		{
			return fail(error, "frame " + std::to_string(frame) + " of sprite " + std::to_string(sprite) + " has " + std::to_string(seen) +
				" action list(s), no number " + std::to_string(index));
		}
		// every Push record of the list (function bodies are records in the same stream); integers are type 7 (4 bytes)
		std::vector<std::uint8_t> &b = target->body;
		std::vector<std::size_t> hits;
		std::size_t pos = 0;
		while (pos < b.size() && b[pos] != 0x00)
		{
			const std::uint8_t op = b[pos++];
			if (op < 0x80)
			{
				continue;
			}
			if (pos + 2 > b.size())
			{
				return fail(error, "the action list is truncated");
			}
			const std::size_t len = b[pos] | (b[pos + 1] << 8);
			pos += 2;
			const std::size_t end = pos + len;
			if (end > b.size())
			{
				return fail(error, "the action list is truncated");
			}
			if (op == 0x96)
			{
				std::size_t v = pos;
				while (v < end)
				{
					const std::uint8_t type = b[v++];
					if (type == 7 && v + 4 <= end)
					{
						const std::int32_t x = (std::int32_t)((std::uint32_t)b[v] | ((std::uint32_t)b[v + 1] << 8) | ((std::uint32_t)b[v + 2] << 16) |
							((std::uint32_t)b[v + 3] << 24));
						if (x == oldValue)
						{
							hits.push_back(v);
						}
					}
					static const int sizes[10] = { -1, 4, 0, 0, 1, 1, 8, 4, 1, 2 };
					if (type == 0)
					{
						while (v < end && b[v])
						{
							++v;
						}
						++v;
					}
					else if (type < 10)
					{
						v += (std::size_t)sizes[type];
					}
					else
					{
						return fail(error, "a Push value of an unknown type");
					}
				}
			}
			pos = end;
		}
		if ((long)hits.size() != count)
		{
			return fail(error, "the action list pushes the integer " + std::to_string(oldValue) + " " + std::to_string(hits.size()) + " time(s), not " +
				std::to_string(count) + " (this is not the script the recipe was written for, or give count=)");
		}
		for (std::size_t v : hits)
		{
			for (int k = 0; k < 4; ++k)
			{
				b[v + k] = (std::uint8_t)((std::uint32_t)newValue >> (8 * k));
			}
		}
		m_out.log.push_back("sprite " + std::to_string(sprite) + " frame " + std::to_string(frame) + " action list " + std::to_string(index) +
			": the integer " + std::to_string(oldValue) + " -> " + std::to_string(newValue) + " (" + std::to_string(hits.size()) + "x)");
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
