// OpenBFME. GPL-3.0.
//
// SWF AVM1 -> APT action programs (the APT <-> SWF converter's assembler, tool only; docs/APT-SWF.md "Actions back to APT").
//
// The inverse of AptSwfAvm1.h for the actions the APT runtime knows (AptActionDecoder's 86 opcodes).  A program is appended to
// the .apt in APT's own layout: the aligned opcodes (>= 0x80 with an operand) start their operand on a 4-byte boundary, strings
// and tables live after the code and are reached by pointer, branch offsets are 32-bit and relative to the next instruction,
// DefineFunction(2) headers carry the body size and EA's 8-byte trailer.  Values are pushed with EA's push opcodes, the forms
// the RotWK compiler emits everywhere:
//
//   Push string / constant8 / constant16   EA_PushString (0xA1) of the string (a constant is resolved from the active pool)
//   Push int                               EA_PushZero / PushOne / PushByte / PushShort / PushLong
//   Push float / double                    EA_PushFloat (0xB4); an integer double as an int; another double as its nearest
//                                          float32 (APT's numbers are float32), counted
//   Push true / false / null / undefined   EA_PushTrue / PushFalse / PushNull / PushUndefined
//   Push register                          PushData of a .const register entry (an existing one, else a new one)
//   ConstantPool                           nothing: its strings are pushed directly
//   GotoFrame2 / GetURL2                   the play flag as the u32 operand / no operand (as AptSwfAvm1.h maps them); GetURL2's
//                                          send method (GET / POST) is dropped: the game sends no variables
//
// What APT has no form for is refused, naming the action: opcodes outside the runtime's census (e.g. With, Try, SetTarget),
// GotoFrame2's scene bias, GetURL2 loading variables or into a sprite path.

#pragma once

#include "Libraries/Source/Apt/AptFile.h"

#include <cstdint>
#include <string>
#include <vector>

namespace aptswf
{

// The .const table of the movie being written, with the entries the assembler adds (register entries).  New entries go after the
// old ones, so every existing index stays; the string area moves by 8 bytes per new entry and its pointers with it.
class AptConstWriter
{
public:
	bool load(const std::vector<std::uint8_t> &bytes, std::string *error);
	std::uint32_t registerEntry(std::uint32_t reg); // the index of a register entry for `reg` (an existing one first)
	bool changed() const { return !m_added.empty(); }
	std::vector<std::uint8_t> bytes() const;       // the .const with the added entries
	std::size_t added() const { return m_added.size(); }

private:
	std::vector<std::uint8_t> m_original;
	AptConstFile m_parsed;
	std::vector<std::pair<std::uint32_t, std::uint32_t>> m_added; // (type, raw)
};

struct AssembleStats
{
	std::size_t instructions = 0; // APT instructions written (function bodies included)
	std::size_t bytes = 0;        // code + data appended
	std::size_t roundedDoubles = 0; // pushed doubles that are neither a float nor an integer: written as the nearest float32
};

// Appends the AVM1 program `avm1` (actions up to and including End; a DoAction body) to `apt` as an APT program and returns its
// offset in `offset`.  `version` is the movie's Apt version (for the decoder that checks the result).
bool assembleAvm1(const std::vector<std::uint8_t> &avm1, std::vector<std::uint8_t> &apt, AptConstWriter &consts, std::uint32_t &offset,
	AssembleStats &stats, std::string *error);

// assembleAvm1, then the check the importer relies on: the new program decoded with the game's decoder (AptActionDecoder) and
// converted back to AVM1 (AptSwfAvm1.h) must do the same actions as `avm1` (avm1Normalized); else an error naming the first
// differing action.  `movieName` / `version` are the movie's (for the decoder).
bool assembleChecked(const std::vector<std::uint8_t> &avm1, const std::string &movieName, std::uint32_t version, std::vector<std::uint8_t> &apt,
	AptConstWriter &consts, std::uint32_t &offset, AssembleStats &stats, std::string *error);

// The program as a flat, comparable list: one line per action with every Push split into single values, constant references
// resolved to their strings, doubles that are floats written as floats, ConstantPool left out, branch targets as indices and
// function bodies inline.  Two programs that do the same thing in different encodings (a pool or inline strings, one Push or
// several) give the same lines; the importer checks an assembled program this way after decoding it back.
bool avm1Normalized(const std::vector<std::uint8_t> &avm1, std::vector<std::string> &lines, std::string *error);

} // namespace aptswf
