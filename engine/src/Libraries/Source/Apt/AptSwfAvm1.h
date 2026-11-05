// OpenBFME. GPL-3.0.
//
// APT action programs -> standard SWF AVM1 bytecode (the APT -> SWF converter, tool only).
//
// APT keeps the SWF opcode numbers for the standard actions but stores operands differently (4-byte aligned, pointers
// into the .apt, PushData / ConstantPool entries as indices into the .const table) and adds EA opcodes.  Each EA opcode
// is the composition of standard actions that the interpreter runs for it (AptActionInterpreter.cpp, which cites the
// RotWK handlers), so it lowers to that sequence:
//
//   0x59 EA_PushZero / 0x5A EA_PushOne     Push int 0 / 1
//   0x73 / 0x74 EA_PushTrue / False        Push true / false
//   0x75 EA_PushNull / 0x76 Undefined      Push null / undefined (the EA runtime pushes undefined for both)
//   0x70 EA_PushThisVar                    Push "this", GetVariable
//   0x71 EA_PushGlobalVar                  Push "_global", GetVariable
//   0x72 EA_ZeroVar                        Push 0, SetVariable
//   0x5B EA_CallFuncPop                    CallFunction, Pop
//   0x5D EA_CallMethodPop                  CallMethod, Pop
//   0x5E EA_CallMethod (set-var form)      CallMethod, SetVariable
//   0xA1 EA_PushString s                   Push s
//   0xA2 EA_PushConstantByte i             Push constant(i)      (constant16 above 255; an inline value for a non-string pool entry)
//   0xA4 / 0xA6 EA_Get/SetStringVar s      Push s, GetVariable / SetVariable
//   0xA5 / 0xA7 EA_Get/SetStringMember s   Push s, GetMember / SetMember
//   0xAE EA_PushValueOfVar i               Push constant(i), GetVariable
//   0xAF EA_GetNamedMember i               Push constant(i), GetMember
//   0xB0 / 0xB1 EA_CallNamedFunc(Pop) i    Push constant(i), CallFunction, Pop / SetVariable
//   0xB2 / 0xB3 EA_CallNamedMethod(Pop) i  Push constant(i), CallMethod, Pop / SetVariable
//   0xB4 EA_PushFloat / 0xB5..0xB7 Push*   Push float / int
//
// Standard actions are re-encoded in SWF form: PushData's .const entries become typed Push values, ConstantPool's become
// a string pool, branch offsets are recomputed after the expansion, GotoFrame2's u32 becomes the play-flag byte, GetURL2
// gets the zero flags byte SWF requires, DefineFunction(2) headers are rebuilt with u16 body sizes.  What has no SWF
// form is reported in `notes` (e.g. DefineFunction2's EA PreloadExtern flag) and the original bytes stay in the private
// tag, so nothing is lost for the round trip.

#pragma once

#include "Libraries/Source/Apt/AptActionDecoder.h"

#include <cstdint>
#include <set>
#include <string>
#include <vector>

namespace aptswf
{

struct Avm1Result
{
	std::vector<std::uint8_t> bytes;
	std::set<std::string> notes;  // things that have no exact SWF form (sorted, no repeats)
	std::size_t eaOpcodes = 0;     // EA opcodes expanded
	std::size_t instructions = 0;  // APT instructions translated (function bodies included)
};

// Translates a decoded APT program.  Fails (false + *error) only when the result cannot be expressed at all in SWF
// (e.g. a function body above 64 KiB).
bool aptToAvm1(const AptCodeBlock &block, Avm1Result &out, std::string *error);

} // namespace aptswf
