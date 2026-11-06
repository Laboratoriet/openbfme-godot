// OpenBFME. GPL-3.0.
// See AptSwfAssemble.h.  APT layouts: AptActionDecoder.cpp (readOperand, readFunction, the alignment rule); SWF layouts: SWF 19
// chapter "Actions".

#include "Libraries/Source/Apt/AptSwfAssemble.h"

#include "Libraries/Source/Apt/AptActionDecoder.h"
#include "Libraries/Source/Apt/AptSwfAvm1.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>

namespace aptswf
{

namespace
{

bool fail(std::string *error, const std::string &m)
{
	if (error)
	{
		*error = m;
	}
	return false;
}

std::string hex2(std::uint8_t v)
{
	char b[8];
	std::snprintf(b, sizeof(b), "0x%02X", v);
	return b;
}

void put32(std::vector<std::uint8_t> &b, std::uint32_t v)
{
	for (int i = 0; i < 4; ++i)
	{
		b.push_back((std::uint8_t)(v >> (8 * i)));
	}
}

void set32(std::vector<std::uint8_t> &b, std::size_t at, std::uint32_t v)
{
	for (int i = 0; i < 4; ++i)
	{
		b[at + i] = (std::uint8_t)(v >> (8 * i));
	}
}

std::uint32_t get32(const std::vector<std::uint8_t> &b, std::size_t at)
{
	return (std::uint32_t)b[at] | ((std::uint32_t)b[at + 1] << 8) | ((std::uint32_t)b[at + 2] << 16) | ((std::uint32_t)b[at + 3] << 24);
}

// ---- AVM1, parsed ------------------------------------------------------------------------------------------------------------
struct Act
{
	std::uint8_t op = 0;
	std::vector<std::uint8_t> data; // the record's payload (opcodes >= 0x80)
	std::size_t at = 0, next = 0;   // offsets in the enclosing block
	int target = -1;                // Jump / If: the action index in the same block (== size: the block's end)
	std::vector<Act> body;          // DefineFunction / DefineFunction2
};

// one Push value
struct PushValue
{
	std::uint8_t type = 0;
	std::string text;     // string
	std::uint32_t u = 0;  // float bits, register, boolean, integer, constant index
	double d = 0;         // double
};

class Reader
{
public:
	Reader(const std::uint8_t *p, std::size_t n) : m_p(p), m_n(n) {}
	bool ok() const { return m_ok; }
	std::size_t pos() const { return m_pos; }
	bool atEnd() const { return m_pos >= m_n; }
	std::uint8_t u8() { return need(1) ? m_p[m_pos++] : 0; }
	std::uint16_t u16()
	{
		if (!need(2))
		{
			return 0;
		}
		const std::uint16_t v = (std::uint16_t)(m_p[m_pos] | (m_p[m_pos + 1] << 8));
		m_pos += 2;
		return v;
	}
	std::uint32_t u32()
	{
		if (!need(4))
		{
			return 0;
		}
		std::uint32_t v = 0;
		for (int i = 0; i < 4; ++i)
		{
			v |= (std::uint32_t)m_p[m_pos + i] << (8 * i);
		}
		m_pos += 4;
		return v;
	}
	std::string cstring()
	{
		std::string s;
		while (m_pos < m_n && m_p[m_pos])
		{
			s.push_back((char)m_p[m_pos++]);
		}
		if (m_pos >= m_n)
		{
			m_ok = false;
			return s;
		}
		++m_pos;
		return s;
	}

private:
	bool need(std::size_t k)
	{
		if (!m_ok || m_pos + k > m_n)
		{
			m_ok = false;
			return false;
		}
		return true;
	}
	const std::uint8_t *m_p;
	std::size_t m_n, m_pos = 0;
	bool m_ok = true;
};

bool parsePush(const std::vector<std::uint8_t> &data, std::vector<PushValue> &out, std::string *error)
{
	Reader r(data.data(), data.size());
	while (!r.atEnd() && r.ok())
	{
		PushValue v;
		v.type = r.u8();
		switch (v.type)
		{
			case 0: v.text = r.cstring(); break;
			case 1: v.u = r.u32(); break;
			case 2: case 3: break;
			case 4: case 5: case 8: v.u = r.u8(); break;
			case 6:
			{
				// SWF stores a double as two little-endian 32-bit words, the high word first
				const std::uint64_t hi = r.u32(), lo = r.u32();
				const std::uint64_t bits = (hi << 32) | lo;
				std::memcpy(&v.d, &bits, 8);
				break;
			}
			case 7: v.u = r.u32(); break;
			case 9: v.u = r.u16(); break;
			default:
				return fail(error, "Push value type " + std::to_string(v.type) + " is not a SWF type");
		}
		out.push_back(std::move(v));
	}
	if (!r.ok())
	{
		return fail(error, "a Push action is truncated");
	}
	return true;
}

// a block of actions: the whole program (up to and including End) or a function body (exactly `size` bytes)
bool parseBlock(const std::uint8_t *p, std::size_t size, bool program, std::vector<Act> &out, std::string *error, int depth = 0)
{
	if (depth > 64)
	{
		return fail(error, "functions nested more than 64 deep");
	}
	std::size_t pos = 0;
	std::map<std::size_t, int> indexAt;
	while (pos < size)
	{
		Act a;
		a.at = pos;
		a.op = p[pos++];
		if (a.op >= 0x80)
		{
			if (pos + 2 > size)
			{
				return fail(error, "action " + hex2(a.op) + " at " + std::to_string(a.at) + " is truncated");
			}
			const std::size_t len = p[pos] | (p[pos + 1] << 8);
			pos += 2;
			if (pos + len > size)
			{
				return fail(error, "action " + hex2(a.op) + " at " + std::to_string(a.at) + " is truncated");
			}
			a.data.assign(p + pos, p + pos + len);
			pos += len;
		}
		if (a.op == 0x9B || a.op == 0x8E)
		{
			if (a.data.size() < 2)
			{
				return fail(error, "a function header is truncated");
			}
			const std::size_t codeSize = a.data[a.data.size() - 2] | (a.data[a.data.size() - 1] << 8);
			if (pos + codeSize > size)
			{
				return fail(error, "a function body runs past its program");
			}
			if (!parseBlock(p + pos, codeSize, false, a.body, error, depth + 1))
			{
				return false;
			}
			pos += codeSize;
		}
		a.next = pos;
		indexAt[a.at] = (int)out.size();
		const bool end = a.op == 0x00;
		out.push_back(std::move(a));
		if (program && end)
		{
			break;
		}
	}
	if (program && (out.empty() || out.back().op != 0x00))
	{
		return fail(error, "the program has no End action");
	}
	const std::size_t endAt = program ? out.back().next : size;
	indexAt[endAt] = (int)out.size();
	for (Act &a : out)
	{
		if (a.op != 0x99 && a.op != 0x9D)
		{
			continue;
		}
		if (a.data.size() != 2)
		{
			return fail(error, "a branch has no 16-bit offset");
		}
		const std::int64_t target = (std::int64_t)a.next + (std::int16_t)(a.data[0] | (a.data[1] << 8));
		auto it = target < 0 ? indexAt.end() : indexAt.find((std::size_t)target);
		if (it == indexAt.end())
		{
			return fail(error, "a branch at " + std::to_string(a.at) + " targets offset " + std::to_string(target) + ", not an action");
		}
		a.target = it->second;
	}
	return true;
}

// ---- normalized lines --------------------------------------------------------------------------------------------------------
std::string valueLine(const PushValue &v, const std::vector<std::string> &pool, std::string *error, bool &ok)
{
	char b[64];
	switch (v.type)
	{
		case 0: return "push string " + v.text;
		case 1: std::snprintf(b, sizeof(b), "push float %08X", v.u); return b;
		case 2: return "push null";
		case 3: return "push undefined";
		case 4: return "push register " + std::to_string(v.u);
		case 5: return std::string("push boolean ") + (v.u ? "1" : "0");
		case 6:
		{
			const float f = (float)v.d;
			if ((double)f == v.d)
			{
				std::uint32_t bits;
				std::memcpy(&bits, &f, 4);
				std::snprintf(b, sizeof(b), "push float %08X", bits);
				return b;
			}
			if (std::floor(v.d) == v.d && v.d >= -2147483648.0 && v.d <= 2147483647.0)
			{
				return "push int " + std::to_string((std::int32_t)v.d);
			}
			// APT's numbers are float32: the nearest float, as the assembler writes it
			std::uint32_t bits;
			std::memcpy(&bits, &f, 4);
			std::snprintf(b, sizeof(b), "push float %08X", bits);
			return b;
		}
		case 7: return "push int " + std::to_string((std::int32_t)v.u);
		default:
			if (v.u >= pool.size())
			{
				ok = false;
				fail(error, "Push constant " + std::to_string(v.u) + " is beyond the constant pool");
				return std::string();
			}
			return "push string " + pool[v.u];
	}
}

bool poolOf(const Act &a, std::vector<std::string> &pool, std::string *error)
{
	Reader r(a.data.data(), a.data.size());
	const std::uint16_t n = r.u16();
	pool.clear();
	for (std::uint16_t i = 0; i < n && r.ok(); ++i)
	{
		pool.push_back(r.cstring());
	}
	return r.ok() || fail(error, "a ConstantPool is truncated");
}

bool normalize(const std::vector<Act> &acts, std::vector<std::string> pool, const std::string &indent, bool program, std::vector<std::string> &lines,
	std::string *error)
{
	// the line where each action starts (a Push of k values is k lines, a pool none, a function its header, body and end)
	std::vector<std::size_t> lineOf(acts.size() + 1, 0);
	std::vector<std::string> mine;
	std::vector<std::pair<std::size_t, int>> branches; // (line in `mine`, target action)
	for (std::size_t i = 0; i < acts.size(); ++i)
	{
		const Act &a = acts[i];
		lineOf[i] = mine.size();
		if (a.op == 0x88)
		{
			if (!poolOf(a, pool, error))
			{
				return false;
			}
			continue;
		}
		if (a.op == 0x96)
		{
			std::vector<PushValue> values;
			if (!parsePush(a.data, values, error))
			{
				return false;
			}
			for (const PushValue &v : values)
			{
				bool ok = true;
				mine.push_back(indent + valueLine(v, pool, error, ok));
				if (!ok)
				{
					return false;
				}
			}
			continue;
		}
		if (a.op == 0x99 || a.op == 0x9D)
		{
			branches.push_back({ mine.size(), a.target });
			mine.push_back(std::string());
			continue;
		}
		if (a.op == 0x9B || a.op == 0x8E)
		{
			std::string header = indent + (a.op == 0x9B ? "function" : "function2");
			std::vector<std::uint8_t> head(a.data.begin(), a.data.end() - 2); // without the code size
			for (std::uint8_t c : head)
			{
				header += " " + hex2(c);
			}
			mine.push_back(header);
			std::vector<std::string> body;
			if (!normalize(a.body, pool, indent + "  ", false, body, error))
			{
				return false;
			}
			mine.insert(mine.end(), body.begin(), body.end());
			mine.push_back(indent + "end function");
			continue;
		}
		std::string line = indent + "op " + hex2(a.op);
		for (std::uint8_t c : a.data)
		{
			line += " " + hex2(c);
		}
		mine.push_back(line);
	}
	lineOf[acts.size()] = mine.size();
	// branch targets as lines (a jump past the program's End ends it, as a jump to the End does: the assembler writes it so)
	std::size_t k = 0;
	for (std::size_t i = 0; i < acts.size(); ++i)
	{
		if (acts[i].op == 0x99 || acts[i].op == 0x9D)
		{
			std::size_t target = (std::size_t)branches[k].second;
			if (program && target == acts.size())
			{
				target = acts.size() - 1;
			}
			mine[branches[k].first] = indent + (acts[i].op == 0x99 ? "jump" : "if") + " -> line " + std::to_string(lineOf[target]);
			++k;
		}
	}
	lines.insert(lines.end(), mine.begin(), mine.end());
	return true;
}

// ---- APT emission ------------------------------------------------------------------------------------------------------------
class Emitter
{
public:
	Emitter(std::uint32_t base, AptConstWriter &consts, AssembleStats &stats) : m_base(base), m_consts(consts), m_stats(stats) {}

	bool program(const std::vector<Act> &acts, std::string *error) { return block(acts, std::vector<std::string>(), true, error); }

	// code, then the data (4-byte aligned), with every pointer patched
	std::vector<std::uint8_t> finish()
	{
		std::vector<std::uint8_t> out = m_code;
		while ((m_base + out.size()) % 4)
		{
			out.push_back(0);
		}
		const std::uint32_t dataBase = m_base + (std::uint32_t)out.size();
		for (const auto &f : m_codePointers)
		{
			set32(out, f.first, dataBase + f.second);
		}
		std::vector<std::uint8_t> data = m_data;
		for (const auto &f : m_dataPointers)
		{
			set32(data, f.first, dataBase + f.second);
		}
		out.insert(out.end(), data.begin(), data.end());
		return out;
	}

private:
	std::uint32_t pos() const { return m_base + (std::uint32_t)m_code.size(); }

	void opcode(std::uint8_t op, bool aligned)
	{
		m_code.push_back(op);
		++m_stats.instructions;
		if (aligned)
		{
			while (pos() % 4)
			{
				m_code.push_back(0);
			}
		}
	}

	void code32(std::uint32_t v) { put32(m_code, v); }

	std::uint32_t dataString(const std::string &s)
	{
		auto it = m_strings.find(s);
		if (it != m_strings.end())
		{
			return it->second;
		}
		const std::uint32_t at = (std::uint32_t)m_data.size();
		m_data.insert(m_data.end(), s.begin(), s.end());
		m_data.push_back(0);
		m_strings[s] = at;
		return at;
	}

	void dataAlign()
	{
		while (m_data.size() % 4)
		{
			m_data.push_back(0);
		}
	}

	// a u32 in the code that points at data
	void codePointer(std::uint32_t dataOffset)
	{
		m_codePointers.push_back({ m_code.size(), dataOffset });
		code32(0);
	}

	bool pushValue(const PushValue &v, const std::vector<std::string> &pool, std::string *error)
	{
		switch (v.type)
		{
			case 0:
				opcode(APT_OP_EA_PUSHSTRING, true);
				codePointer(dataString(v.text));
				return true;
			case 8:
			case 9:
				if (v.u >= pool.size())
				{
					return fail(error, "Push constant " + std::to_string(v.u) + " is beyond the constant pool");
				}
				opcode(APT_OP_EA_PUSHSTRING, true);
				codePointer(dataString(pool[v.u]));
				return true;
			case 1:
			{
				float f;
				std::memcpy(&f, &v.u, 4);
				if (!std::isfinite(f))
				{
					return fail(error, "a pushed float is not finite (APT's PushFloat refuses it)");
				}
				opcode(APT_OP_EA_PUSHFLOAT, false);
				code32(v.u);
				return true;
			}
			case 2: opcode(APT_OP_EA_PUSHNULL, false); return true;
			case 3: opcode(APT_OP_EA_PUSHUNDEFINED, false); return true;
			case 5: opcode(v.u ? APT_OP_EA_PUSHTRUE : APT_OP_EA_PUSHFALSE, false); return true;
			case 4:
			{
				// PushData of a register entry: a one-entry index table in the data
				opcode(APT_OP_PUSHDATA, true);
				code32(1);
				dataAlign();
				const std::uint32_t table = (std::uint32_t)m_data.size();
				put32(m_data, m_consts.registerEntry(v.u));
				codePointer(table);
				return true;
			}
			case 6:
			{
				const float f = (float)v.d;
				if ((double)f == v.d && std::isfinite(f))
				{
					std::uint32_t bits;
					std::memcpy(&bits, &f, 4);
					opcode(APT_OP_EA_PUSHFLOAT, false);
					code32(bits);
					return true;
				}
				if (std::floor(v.d) == v.d && v.d >= -2147483648.0 && v.d <= 2147483647.0)
				{
					PushValue i;
					i.type = 7;
					i.u = (std::uint32_t)(std::int32_t)v.d;
					return pushValue(i, pool, error);
				}
				// APT's numbers are float32 (PushFloat, .const floats): the nearest float
				if (!std::isfinite(f))
				{
					return fail(error, "a pushed number is not finite as a float32");
				}
				std::uint32_t bits;
				std::memcpy(&bits, &f, 4);
				opcode(APT_OP_EA_PUSHFLOAT, false);
				code32(bits);
				++m_stats.roundedDoubles;
				return true;
			}
			case 7:
			{
				const std::int32_t i = (std::int32_t)v.u;
				if (i == 0)
				{
					opcode(APT_OP_EA_PUSHZERO, false);
				}
				else if (i == 1)
				{
					opcode(APT_OP_EA_PUSHONE, false);
				}
				else if (i >= -128 && i <= 127)
				{
					opcode(APT_OP_EA_PUSHBYTE, false);
					m_code.push_back((std::uint8_t)(std::int8_t)i);
				}
				else if (i >= -32768 && i <= 32767)
				{
					opcode(APT_OP_EA_PUSHSHORT, false);
					m_code.push_back((std::uint8_t)(i & 0xFF));
					m_code.push_back((std::uint8_t)((i >> 8) & 0xFF));
				}
				else
				{
					opcode(APT_OP_EA_PUSHLONG, false);
					code32((std::uint32_t)i);
				}
				return true;
			}
			default:
				return fail(error, "Push value type " + std::to_string(v.type));
		}
	}

	bool function(const Act &a, const std::vector<std::string> &pool, std::string *error)
	{
		const bool v2 = a.op == 0x8E;
		Reader r(a.data.data(), a.data.size());
		const std::string name = r.cstring();
		const std::uint16_t count = r.u16();
		std::uint8_t registers = 0, flagsA = 0, flagsB = 0;
		if (v2)
		{
			registers = r.u8();
			flagsA = r.u8();
			flagsB = r.u8();
		}
		std::vector<std::pair<std::uint32_t, std::string>> params;
		for (std::uint16_t i = 0; i < count && r.ok(); ++i)
		{
			std::uint32_t reg = v2 ? r.u8() : 0;
			params.push_back({ reg, r.cstring() });
		}
		r.u16(); // the code size (the body is parsed already)
		if (!r.ok() || !r.atEnd())
		{
			return fail(error, std::string(v2 ? "DefineFunction2" : "DefineFunction") + " '" + name + "' header does not decode");
		}
		// the parameter table: v1 a pointer per name, v2 (register, name pointer) pairs (AptActionDecoder readFunction)
		dataAlign();
		const std::uint32_t table = (std::uint32_t)m_data.size();
		for (const auto &p : params)
		{
			if (v2)
			{
				put32(m_data, p.first);
			}
			m_dataPointers.push_back({ m_data.size(), 0 });
			put32(m_data, 0);
		}
		// the names after the table (the table's slots point at them)
		std::size_t slot = 0;
		for (const auto &p : params)
		{
			const std::uint32_t nameAt = dataString(p.second);
			const std::size_t at = table + slot * (v2 ? 8 : 4) + (v2 ? 4 : 0);
			for (auto &f : m_dataPointers)
			{
				if (f.first == at)
				{
					f.second = nameAt;
				}
			}
			++slot;
		}
		opcode(a.op, true);
		codePointer(dataString(name));
		code32(count);
		if (v2)
		{
			// the register count, then the 3 flag bytes: 0, then SWF's two flag bytes (AptSwfAvm1.cpp: the bit AptFunction2Flags calls
			// PRELOAD_EXTERN is SWF's PreloadGlobal)
			m_code.push_back(registers);
			m_code.push_back(0);
			m_code.push_back(flagsA);
			m_code.push_back(flagsB);
		}
		if (count)
		{
			codePointer(table);
		}
		else
		{
			code32(0);
		}
		const std::size_t sizeAt = m_code.size();
		code32(0);
		static const std::uint8_t trailer[8] = { 0x32, 0x54, 0x76, 0x98, 0x78, 0x56, 0x34, 0x12 };
		m_code.insert(m_code.end(), trailer, trailer + 8);
		const std::uint32_t bodyStart = pos();
		if (!block(a.body, pool, false, error))
		{
			return false;
		}
		set32(m_code, sizeAt, pos() - bodyStart);
		return true;
	}

	bool block(const std::vector<Act> &acts, std::vector<std::string> pool, bool program, std::string *error)
	{
		std::vector<std::uint32_t> start(acts.size() + 1, 0);
		struct Fix
		{
			std::size_t at;     // the operand in m_code
			std::uint32_t next; // the offset after the instruction
			int target;
		};
		std::vector<Fix> fixes;
		for (std::size_t i = 0; i < acts.size(); ++i)
		{
			const Act &a = acts[i];
			start[i] = pos();
			const std::string where = "action " + hex2(a.op) + " (#" + std::to_string(i) + ")";
			switch (a.op)
			{
				case 0x88:
					if (!poolOf(a, pool, error))
					{
						return false;
					}
					break; // its strings are pushed directly
				case 0x96:
				{
					std::vector<PushValue> values;
					if (!parsePush(a.data, values, error))
					{
						return false;
					}
					for (const PushValue &v : values)
					{
						if (!pushValue(v, pool, error))
						{
							return false;
						}
					}
					break;
				}
				case 0x99:
				case 0x9D:
				{
					opcode(a.op, true);
					int target = a.target;
					// a jump past the program's End ends it, as a jump to the End does
					if (program && target == (int)acts.size())
					{
						target = (int)acts.size() - 1;
					}
					fixes.push_back({ m_code.size(), 0, target });
					code32(0);
					fixes.back().next = pos();
					break;
				}
				case 0x81: // GotoFrame: u16 -> u32
				{
					if (a.data.size() != 2)
					{
						return fail(error, where + ": GotoFrame without its frame");
					}
					opcode(a.op, true);
					code32((std::uint32_t)(a.data[0] | (a.data[1] << 8)));
					break;
				}
				case 0x87: // StoreRegister: u8 -> u32
				{
					if (a.data.size() != 1)
					{
						return fail(error, where + ": StoreRegister without its register");
					}
					opcode(a.op, true);
					code32(a.data[0]);
					break;
				}
				case 0x8C: // GotoLabel: a string pointer
				{
					Reader r(a.data.data(), a.data.size());
					const std::string label = r.cstring();
					if (!r.ok())
					{
						return fail(error, where + ": GotoLabel without its label");
					}
					opcode(a.op, true);
					codePointer(dataString(label));
					break;
				}
				case 0x83: // GetURL: two string pointers
				{
					Reader r(a.data.data(), a.data.size());
					const std::string url = r.cstring(), target = r.cstring();
					if (!r.ok())
					{
						return fail(error, where + ": GetURL without its two strings");
					}
					opcode(a.op, true);
					codePointer(dataString(url));
					codePointer(dataString(target));
					break;
				}
				case 0x9F: // GotoFrame2: the play flag as the u32
				{
					if (a.data.size() != 1 || (a.data[0] & ~1u) != 0)
					{
						return fail(error, where + ": GotoFrame2 with a scene bias has no APT form");
					}
					opcode(a.op, true);
					code32(a.data[0] & 1u);
					break;
				}
				case 0x9A: // GetURL2: no operand in APT
				{
					if (a.data.size() != 1 || a.data[0] != 0)
					{
						return fail(error, where + ": GetURL2 with flags (send variables, load a target or variables) has no APT form");
					}
					opcode(a.op, false);
					break;
				}
				case 0x9B:
				case 0x8E:
					if (!function(a, pool, error))
					{
						return false;
					}
					break;
				default:
					if (a.op >= 0x80 || !AptActionDecoder::isSupportedOpcode(a.op) || AptActionDecoder::isAlignedOpcode(a.op))
					{
						return fail(error, where + " is not an action the APT runtime has (not in its 86-opcode census)");
					}
					if (a.op >= 0x59 && a.op != 0x60 && a.op != 0x64 && a.op != 0x67)
					{
						return fail(error, where + " is an EA opcode number, not a SWF action");
					}
					opcode(a.op, false);
					break;
			}
		}
		start[acts.size()] = pos();
		for (const Fix &f : fixes)
		{
			if (f.target < 0 || (std::size_t)f.target > acts.size())
			{
				return fail(error, "a branch without a target");
			}
			set32(m_code, f.at, (std::uint32_t)((std::int64_t)start[(std::size_t)f.target] - (std::int64_t)f.next));
		}
		return true;
	}

	std::uint32_t m_base;
	AptConstWriter &m_consts;
	AssembleStats &m_stats;
	std::vector<std::uint8_t> m_code, m_data;
	std::vector<std::pair<std::size_t, std::uint32_t>> m_codePointers; // (offset in code, data offset)
	std::vector<std::pair<std::size_t, std::uint32_t>> m_dataPointers; // (offset in data, data offset)
	std::map<std::string, std::uint32_t> m_strings;
};

} // namespace

// ---- the .const writer -------------------------------------------------------------------------------------------------------
bool AptConstWriter::load(const std::vector<std::uint8_t> &bytes, std::string *error)
{
	m_original = bytes;
	m_added.clear();
	if (!AptConstFile::parse(bytes, m_parsed, error))
	{
		return false;
	}
	// the layout the writer relies on: the records right after the 32-byte header, the strings after the records
	const std::uint32_t recordsEnd = 32 + 8 * (std::uint32_t)m_parsed.entries.size();
	for (const AptConstEntry &e : m_parsed.entries)
	{
		if (e.type == APT_CONST_STRING && e.raw < recordsEnd)
		{
			return fail(error, ".const: a string inside the record table (a layout the writer does not handle)");
		}
	}
	return true;
}

std::uint32_t AptConstWriter::registerEntry(std::uint32_t reg)
{
	for (std::size_t i = 0; i < m_parsed.entries.size(); ++i)
	{
		if (m_parsed.entries[i].type == APT_CONST_REGISTER && m_parsed.entries[i].raw == reg)
		{
			return (std::uint32_t)i;
		}
	}
	for (std::size_t i = 0; i < m_added.size(); ++i)
	{
		if (m_added[i].first == APT_CONST_REGISTER && m_added[i].second == reg)
		{
			return (std::uint32_t)(m_parsed.entries.size() + i);
		}
	}
	m_added.push_back({ APT_CONST_REGISTER, reg });
	return (std::uint32_t)(m_parsed.entries.size() + m_added.size() - 1);
}

std::vector<std::uint8_t> AptConstWriter::bytes() const
{
	if (m_added.empty())
	{
		return m_original;
	}
	const std::uint32_t n = (std::uint32_t)m_parsed.entries.size();
	const std::uint32_t shift = 8 * (std::uint32_t)m_added.size();
	std::vector<std::uint8_t> out(m_original.begin(), m_original.begin() + 32);
	set32(out, 24, n + (std::uint32_t)m_added.size());
	for (std::uint32_t i = 0; i < n; ++i)
	{
		const std::uint32_t type = get32(m_original, 32 + i * 8);
		const std::uint32_t raw = get32(m_original, 36 + i * 8);
		put32(out, type);
		put32(out, type == APT_CONST_STRING ? raw + shift : raw);
	}
	for (const auto &a : m_added)
	{
		put32(out, a.first);
		put32(out, a.second);
	}
	out.insert(out.end(), m_original.begin() + 32 + 8 * n, m_original.end());
	return out;
}

// ---- entry points ------------------------------------------------------------------------------------------------------------
bool assembleAvm1(const std::vector<std::uint8_t> &avm1, std::vector<std::uint8_t> &apt, AptConstWriter &consts, std::uint32_t &offset,
	AssembleStats &stats, std::string *error)
{
	std::vector<Act> acts;
	if (!parseBlock(avm1.data(), avm1.size(), true, acts, error))
	{
		return false;
	}
	while (apt.size() % 4)
	{
		apt.push_back(0);
	}
	offset = (std::uint32_t)apt.size();
	Emitter e(offset, consts, stats);
	if (!e.program(acts, error))
	{
		return false;
	}
	const std::vector<std::uint8_t> bytes = e.finish();
	apt.insert(apt.end(), bytes.begin(), bytes.end());
	stats.bytes += bytes.size();
	return true;
}

bool assembleChecked(const std::vector<std::uint8_t> &avm1, const std::string &movieName, std::uint32_t version, std::vector<std::uint8_t> &apt,
	AptConstWriter &consts, std::uint32_t &offset, AssembleStats &stats, std::string *error)
{
	std::string e;
	if (!assembleAvm1(avm1, apt, consts, offset, stats, &e))
	{
		return fail(error, e);
	}
	AptFile check;
	check.name = movieName;
	check.version = version;
	if (!AptConstFile::parse(consts.bytes(), check.consts, &e))
	{
		return fail(error, "internal error: the .const does not parse after the assembly (" + e + ")");
	}
	check.data = std::make_shared<const std::vector<std::uint8_t>>(apt);
	std::shared_ptr<const AptCodeBlock> block;
	Avm1Result back;
	if (!AptActionDecoder::decodeProgram(check, offset, block, &e) || !aptToAvm1(*block, back, &e))
	{
		return fail(error, "internal error: the assembled program does not decode (" + e + ")");
	}
	std::vector<std::string> want, got;
	if (!avm1Normalized(avm1, want, &e) || !avm1Normalized(back.bytes, got, &e))
	{
		return fail(error, e);
	}
	if (want != got)
	{
		std::size_t i = 0;
		while (i < want.size() && i < got.size() && want[i] == got[i])
		{
			++i;
		}
		return fail(error, "internal error: the assembled program differs from the SWF's at line " + std::to_string(i) + " ('" +
			(i < want.size() ? want[i] : std::string("end")) + "' / '" + (i < got.size() ? got[i] : std::string("end")) + "')");
	}
	return true;
}

bool avm1Normalized(const std::vector<std::uint8_t> &avm1, std::vector<std::string> &lines, std::string *error)
{
	std::vector<Act> acts;
	lines.clear();
	return parseBlock(avm1.data(), avm1.size(), true, acts, error) && normalize(acts, std::vector<std::string>(), "", true, lines, error);
}

} // namespace aptswf
