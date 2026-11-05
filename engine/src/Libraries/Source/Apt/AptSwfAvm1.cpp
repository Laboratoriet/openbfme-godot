// OpenBFME. GPL-3.0.
// See AptSwfAvm1.h.  SWF encodings: SWF 19 chapter "Actions" (ActionPush value types, ActionConstantPool,
// ActionDefineFunction / ActionDefineFunction2, ActionJump / ActionIf offsets relative to the next action).

#include "Libraries/Source/Apt/AptSwfAvm1.h"

#include "Libraries/Source/Apt/AptFile.h"

#include <cstring>

namespace aptswf
{

namespace
{

// SWF ActionPush value types
enum : std::uint8_t
{
	PUSH_STRING = 0,
	PUSH_FLOAT = 1,
	PUSH_NULL = 2,
	PUSH_UNDEFINED = 3,
	PUSH_REGISTER = 4,
	PUSH_BOOLEAN = 5,
	PUSH_INTEGER = 7,
	PUSH_CONSTANT8 = 8,
	PUSH_CONSTANT16 = 9
};

// standard SWF opcodes the lowering emits
enum : std::uint8_t
{
	OP_END = 0x00,
	OP_POP = 0x17,
	OP_GETVARIABLE = 0x1C,
	OP_SETVARIABLE = 0x1D,
	OP_CALLFUNCTION = 0x3D,
	OP_GETMEMBER = 0x4E,
	OP_SETMEMBER = 0x4F,
	OP_CALLMETHOD = 0x52,
	OP_PUSH = 0x96
};

using Pool = std::vector<AptConstRef>;

struct Low
{
	enum class Kind
	{
		Op,
		Branch,
		Function
	};
	Kind kind = Kind::Op;
	std::uint8_t opcode = 0;
	std::vector<std::uint8_t> payload; // Op: the action's data; Function: the header up to (excluding) codeSize
	std::int32_t target = -1;          // Branch: APT instruction index
	std::vector<std::uint8_t> body;    // Function: the translated body
	std::size_t aptIndex = 0;

	std::size_t size() const
	{
		switch (kind)
		{
			case Kind::Branch:
				return 5;
			case Kind::Function:
				return 1 + 2 + payload.size() + 2 + body.size();
			default:
				return opcode >= 0x80 ? 3 + payload.size() : 1;
		}
	}
};

void put16(std::vector<std::uint8_t> &b, std::uint32_t v)
{
	b.push_back((std::uint8_t)v);
	b.push_back((std::uint8_t)(v >> 8));
}

void put32(std::vector<std::uint8_t> &b, std::uint32_t v)
{
	for (int i = 0; i < 4; ++i)
	{
		b.push_back((std::uint8_t)(v >> (8 * i)));
	}
}

void putString(std::vector<std::uint8_t> &b, const std::string &s)
{
	b.insert(b.end(), s.begin(), s.end());
	b.push_back(0);
}

class Translator
{
public:
	Avm1Result &result;
	explicit Translator(Avm1Result &r) : result(r) {}

	bool translate(const AptCodeBlock &block, Pool pool, std::vector<std::uint8_t> &out, std::string *error)
	{
		std::vector<Low> lows;
		for (std::size_t i = 0; i < block.instructions.size(); ++i)
		{
			const AptInstruction &ins = block.instructions[i];
			++result.instructions;
			const std::size_t before = lows.size();
			if (!lower(ins, pool, lows, error))
			{
				return false;
			}
			for (std::size_t k = before; k < lows.size(); ++k)
			{
				lows[k].aptIndex = i;
			}
		}
		// offsets: start of each APT instruction's first action (or of the next one when it emitted none)
		const std::size_t n = block.instructions.size();
		std::vector<std::size_t> startOf(n + 1, (std::size_t)-1);
		std::vector<std::size_t> lowOffset(lows.size());
		std::size_t at = 0;
		for (std::size_t k = 0; k < lows.size(); ++k)
		{
			lowOffset[k] = at;
			if (startOf[lows[k].aptIndex] == (std::size_t)-1)
			{
				startOf[lows[k].aptIndex] = at;
			}
			at += lows[k].size();
		}
		startOf[n] = at;
		for (std::size_t i = n; i-- > 0;)
		{
			if (startOf[i] == (std::size_t)-1)
			{
				startOf[i] = startOf[i + 1];
			}
		}
		for (std::size_t k = 0; k < lows.size(); ++k)
		{
			const Low &l = lows[k];
			out.push_back(l.opcode);
			if (l.kind == Low::Kind::Branch)
			{
				if (l.target < 0 || (std::size_t)l.target > n)
				{
					return fail(error, "branch without a resolved target");
				}
				const std::int64_t rel = (std::int64_t)startOf[(std::size_t)l.target] - (std::int64_t)(lowOffset[k] + 5);
				if (rel < -32768 || rel > 32767)
				{
					return fail(error, "branch offset " + std::to_string(rel) + " does not fit SWF's 16 bits");
				}
				put16(out, 2);
				put16(out, (std::uint32_t)(std::uint16_t)(std::int16_t)rel);
			}
			else if (l.kind == Low::Kind::Function)
			{
				if (l.body.size() > 0xFFFF || l.payload.size() + 2 > 0xFFFF)
				{
					return fail(error, "function body of " + std::to_string(l.body.size()) + " bytes exceeds SWF's 64 KiB");
				}
				put16(out, (std::uint32_t)(l.payload.size() + 2));
				out.insert(out.end(), l.payload.begin(), l.payload.end());
				put16(out, (std::uint32_t)l.body.size());
				out.insert(out.end(), l.body.begin(), l.body.end());
			}
			else if (l.opcode >= 0x80)
			{
				if (l.payload.size() > 0xFFFF)
				{
					return fail(error, "action payload exceeds 64 KiB");
				}
				put16(out, (std::uint32_t)l.payload.size());
				out.insert(out.end(), l.payload.begin(), l.payload.end());
			}
		}
		return true;
	}

private:
	static bool fail(std::string *error, const std::string &m)
	{
		if (error)
		{
			*error = "AVM1: " + m;
		}
		return false;
	}

	static Low op(std::uint8_t opcode)
	{
		Low l;
		l.opcode = opcode;
		return l;
	}

	// one Push action with a single value
	static Low push(std::uint8_t type, const std::vector<std::uint8_t> &value)
	{
		Low l;
		l.opcode = OP_PUSH;
		l.payload.push_back(type);
		l.payload.insert(l.payload.end(), value.begin(), value.end());
		return l;
	}

	static Low pushString(const std::string &s)
	{
		std::vector<std::uint8_t> v;
		putString(v, s);
		return push(PUSH_STRING, v);
	}

	static Low pushInt(std::int32_t i)
	{
		std::vector<std::uint8_t> v;
		put32(v, (std::uint32_t)i);
		return push(PUSH_INTEGER, v);
	}

	// encodes one .const entry as a Push value (type byte + data) into `payload`
	bool pushValue(const AptConstRef &c, const Pool &pool, std::vector<std::uint8_t> &payload)
	{
		switch (c.type)
		{
			case APT_CONST_STRING:
				payload.push_back(PUSH_STRING);
				putString(payload, c.text);
				return true;
			case APT_CONST_FLOAT:
				payload.push_back(PUSH_FLOAT);
				put32(payload, c.raw); // the same float32 bits
				return true;
			case APT_CONST_INTEGER:
				payload.push_back(PUSH_INTEGER);
				put32(payload, c.raw);
				return true;
			case APT_CONST_BOOLEAN:
				payload.push_back(PUSH_BOOLEAN);
				payload.push_back(c.raw ? 1 : 0);
				return true;
			case APT_CONST_REGISTER:
				if (c.raw > 255)
				{
					result.notes.insert("PushData register above 255 (SWF registers are a byte)");
				}
				payload.push_back(PUSH_REGISTER);
				payload.push_back((std::uint8_t)c.raw);
				return true;
			case APT_CONST_UNDEFINED:
				payload.push_back(PUSH_UNDEFINED);
				return true;
			case APT_CONST_LOOKUP:
				// BFME1's type-8 constant: an index into the active constant pool (docs/BFME1.md)
				pushPoolRef(c.raw, pool, payload);
				return true;
			default:
				// type 2 (property) and 3 (none) have no verified runtime meaning (S-013): pushed as undefined, noted
				result.notes.insert("PushData constant type " + std::to_string(c.type) + " has no known SWF value (pushed as undefined)");
				payload.push_back(PUSH_UNDEFINED);
				return true;
		}
	}

	// a constant-pool reference: constant8 / constant16 for a string entry, the value inline otherwise
	void pushPoolRef(std::uint32_t index, const Pool &pool, std::vector<std::uint8_t> &payload)
	{
		if (index < pool.size() && pool[index].type != APT_CONST_STRING)
		{
			result.notes.insert("constant pool entry of a non-string type referenced by index (pushed inline)");
			pushValue(pool[index], Pool(), payload);
			return;
		}
		if (index >= pool.size())
		{
			result.notes.insert("constant pool index beyond the active pool (kept as a SWF constant reference)");
		}
		if (index < 256)
		{
			payload.push_back(PUSH_CONSTANT8);
			payload.push_back((std::uint8_t)index);
		}
		else
		{
			payload.push_back(PUSH_CONSTANT16);
			put16(payload, index);
		}
	}

	Low pushPool(std::uint32_t index, const Pool &pool)
	{
		Low l;
		l.opcode = OP_PUSH;
		pushPoolRef(index, pool, l.payload);
		return l;
	}

	bool lower(const AptInstruction &ins, Pool &pool, std::vector<Low> &lows, std::string *error)
	{
		const std::uint8_t o = ins.opcode;
		auto ea = [&]() { ++result.eaOpcodes; };
		switch (o)
		{
			// ---- EA opcodes: the standard sequence the interpreter runs -----------------------------------------------
			case APT_OP_EA_PUSHZERO:
				ea();
				lows.push_back(pushInt(0));
				return true;
			case APT_OP_EA_PUSHONE:
				ea();
				lows.push_back(pushInt(1));
				return true;
			case APT_OP_EA_PUSHTRUE:
			case APT_OP_EA_PUSHFALSE:
				ea();
				lows.push_back(push(PUSH_BOOLEAN, { (std::uint8_t)(o == APT_OP_EA_PUSHTRUE ? 1 : 0) }));
				return true;
			case APT_OP_EA_PUSHNULL:
				ea();
				lows.push_back(push(PUSH_NULL, {}));
				return true;
			case APT_OP_EA_PUSHUNDEFINED:
				ea();
				lows.push_back(push(PUSH_UNDEFINED, {}));
				return true;
			case APT_OP_EA_PUSHTHISVAR:
				ea();
				lows.push_back(pushString("this"));
				lows.push_back(op(OP_GETVARIABLE));
				return true;
			case APT_OP_EA_PUSHGLOBALVAR:
				ea();
				lows.push_back(pushString("_global"));
				lows.push_back(op(OP_GETVARIABLE));
				return true;
			case APT_OP_EA_ZEROVAR:
				ea();
				lows.push_back(pushInt(0));
				lows.push_back(op(OP_SETVARIABLE));
				return true;
			case APT_OP_EA_CALLFUNCPOP:
				ea();
				lows.push_back(op(OP_CALLFUNCTION));
				lows.push_back(op(OP_POP));
				return true;
			case APT_OP_EA_CALLMETHODPOP:
				ea();
				lows.push_back(op(OP_CALLMETHOD));
				lows.push_back(op(OP_POP));
				return true;
			case APT_OP_EA_CALLMETHOD:
				ea();
				lows.push_back(op(OP_CALLMETHOD));
				lows.push_back(op(OP_SETVARIABLE));
				return true;
			case APT_OP_EA_PUSHSTRING:
				ea();
				lows.push_back(pushString(ins.text));
				return true;
			case APT_OP_EA_PUSHCONSTANTBYTE:
				ea();
				lows.push_back(pushPool((std::uint32_t)ins.intOperand, pool));
				return true;
			case APT_OP_EA_GETSTRINGVAR:
			case APT_OP_EA_SETSTRINGVAR:
				ea();
				lows.push_back(pushString(ins.text));
				lows.push_back(op(o == APT_OP_EA_GETSTRINGVAR ? OP_GETVARIABLE : OP_SETVARIABLE));
				return true;
			case APT_OP_EA_GETSTRINGMEMBER:
			case APT_OP_EA_SETSTRINGMEMBER:
				ea();
				lows.push_back(pushString(ins.text));
				lows.push_back(op(o == APT_OP_EA_GETSTRINGMEMBER ? OP_GETMEMBER : OP_SETMEMBER));
				return true;
			case APT_OP_EA_PUSHVALUEOFVAR:
				ea();
				lows.push_back(pushPool((std::uint32_t)ins.intOperand, pool));
				lows.push_back(op(OP_GETVARIABLE));
				return true;
			case APT_OP_EA_GETNAMEDMEMBER:
				ea();
				lows.push_back(pushPool((std::uint32_t)ins.intOperand, pool));
				lows.push_back(op(OP_GETMEMBER));
				return true;
			case APT_OP_EA_CALLNAMEDFUNCPOP:
			case APT_OP_EA_CALLNAMEDFUNC:
				ea();
				lows.push_back(pushPool((std::uint32_t)ins.intOperand, pool));
				lows.push_back(op(OP_CALLFUNCTION));
				lows.push_back(op(o == APT_OP_EA_CALLNAMEDFUNCPOP ? OP_POP : OP_SETVARIABLE));
				return true;
			case APT_OP_EA_CALLNAMEDMETHODPOP:
			case APT_OP_EA_CALLNAMEDMETHOD:
				ea();
				lows.push_back(pushPool((std::uint32_t)ins.intOperand, pool));
				lows.push_back(op(OP_CALLMETHOD));
				lows.push_back(op(o == APT_OP_EA_CALLNAMEDMETHODPOP ? OP_POP : OP_SETVARIABLE));
				return true;
			case APT_OP_EA_PUSHFLOAT:
			{
				ea();
				std::uint32_t bits;
				std::memcpy(&bits, &ins.floatOperand, 4);
				std::vector<std::uint8_t> v;
				put32(v, bits);
				lows.push_back(push(PUSH_FLOAT, v));
				return true;
			}
			case APT_OP_EA_PUSHBYTE:
			case APT_OP_EA_PUSHSHORT:
			case APT_OP_EA_PUSHLONG:
				ea();
				lows.push_back(pushInt(ins.intOperand));
				return true;

			// ---- standard actions with APT operand layouts ----------------------------------------------------------
			case APT_OP_PUSHDATA:
			{
				Low l;
				l.opcode = OP_PUSH;
				for (const AptConstRef &c : ins.constants)
				{
					pushValue(c, pool, l.payload);
				}
				if (ins.constants.empty())
				{
					result.notes.insert("empty PushData (no SWF Push without values; emitted as an empty Push)");
				}
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_CONSTANTPOOL:
			{
				pool = ins.constants;
				Low l;
				l.opcode = APT_OP_CONSTANTPOOL;
				put16(l.payload, (std::uint32_t)pool.size());
				for (const AptConstRef &c : pool)
				{
					// a non-string pool entry keeps its slot as "" in SWF's string pool; its uses push the value inline
					putString(l.payload, c.type == APT_CONST_STRING ? c.text : std::string());
				}
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_GOTOFRAME:
			{
				Low l = op(APT_OP_GOTOFRAME);
				if (ins.intOperand < 0 || ins.intOperand > 0xFFFF)
				{
					result.notes.insert("GotoFrame frame above 65535");
				}
				put16(l.payload, (std::uint32_t)ins.intOperand);
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_GOTOFRAME2:
			{
				// RW / BFME1 Rva008CAC20GotoFrame2: the u32 operand is the play flag
				if ((ins.intOperand & ~1) != 0)
				{
					result.notes.insert("GotoFrame2 operand bits other than play (no SWF scene bias form)");
				}
				Low l = op(APT_OP_GOTOFRAME2);
				l.payload.push_back((std::uint8_t)(ins.intOperand & 1));
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_GOTOLABEL:
			{
				Low l = op(APT_OP_GOTOLABEL);
				putString(l.payload, ins.text);
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_GETURL:
			{
				Low l = op(APT_OP_GETURL);
				putString(l.payload, ins.text);
				putString(l.payload, ins.text2);
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_GETURL2:
			{
				// APT's GetURL2 has no operand; SWF's needs its flags byte (0: no variables sent, no target sprite, no load)
				Low l = op(APT_OP_GETURL2);
				l.payload.push_back(0);
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_SETREGISTER:
			{
				if (ins.intOperand < 0 || ins.intOperand > 255)
				{
					result.notes.insert("StoreRegister register above 255");
				}
				Low l = op(APT_OP_SETREGISTER);
				l.payload.push_back((std::uint8_t)ins.intOperand);
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_BRANCHALWAYS:
			case APT_OP_BRANCHIFTRUE:
			{
				Low l;
				l.kind = Low::Kind::Branch;
				l.opcode = o;
				l.target = ins.branchTarget;
				lows.push_back(std::move(l));
				return true;
			}
			case APT_OP_DEFINEFUNCTION:
			case APT_OP_DEFINEFUNCTION2:
			{
				const AptFunctionDef &fn = *ins.function;
				Low l;
				l.kind = Low::Kind::Function;
				l.opcode = o;
				putString(l.payload, fn.name);
				put16(l.payload, (std::uint32_t)fn.params.size());
				if (fn.isV2)
				{
					if (fn.registerCount > 255)
					{
						result.notes.insert("DefineFunction2 register count above 255");
					}
					l.payload.push_back((std::uint8_t)fn.registerCount);
					// SWF's two flag bytes, read most significant bit first: PreloadParent .. PreloadThis, then 7 reserved bits and
					// PreloadGlobal.  The decoder's 24-bit `flags` is the 3 bytes after the register count; the SWF bytes are its
					// second and third byte, so SWF's PreloadGlobal is what AptFunction2Flags calls PRELOAD_EXTERN (0x10000).
					// Evidence: RotWK QuitMenu.apt InitialSetup (flags 0x016A00) reads register 2 as _global (`if (extern.InGame)
					// { r2.InGame = true; ... }`, with _root in register 1); LibreSAGE/AptTools writes the same two bytes.
					l.payload.push_back((std::uint8_t)((fn.flags >> 8) & 0xFF));
					l.payload.push_back((std::uint8_t)((fn.flags >> 16) & 0xFF));
					if (fn.flags & 0xFF)
					{
						result.notes.insert("DefineFunction2 with a non-zero byte before SWF's two flag bytes (AptFunction2Flags' PRELOAD_GLOBAL bit): not in the SWF");
					}
					for (const AptFunctionParam &p : fn.params)
					{
						l.payload.push_back((std::uint8_t)(p.reg > 0 ? p.reg : 0));
						putString(l.payload, p.name);
					}
				}
				else
				{
					for (const AptFunctionParam &p : fn.params)
					{
						putString(l.payload, p.name);
					}
				}
				if (fn.body && !translate(*fn.body, pool, l.body, error))
				{
					return false;
				}
				lows.push_back(std::move(l));
				return true;
			}
			default:
				if (o >= 0x80)
				{
					// every APT opcode >= 0x80 with an operand is handled above; one reaching here has an unknown layout
					return fail(error, "opcode 0x" + std::to_string(o) + " has no SWF encoding");
				}
				lows.push_back(op(o));
				return true;
		}
	}
};

} // namespace

bool aptToAvm1(const AptCodeBlock &block, Avm1Result &out, std::string *error)
{
	out = Avm1Result();
	Translator t(out);
	return t.translate(block, Pool(), out.bytes, error);
}

} // namespace aptswf
