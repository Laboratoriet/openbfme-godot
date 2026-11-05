// OpenBFME unit tests: the APT <-> SWF converter (docs/APT-SWF.md).  Synthetic movies only (AptTestUtil.h builds them
// byte by byte); the retail corpus round trip is the tool's `roundtrip` command, run with the user's own game files.  GPL-3.0.

#include "doctest.h"
#include "AptTestUtil.h"

#include "Libraries/Source/Apt/AptSwfAvm1.h"
#include "Libraries/Source/Apt/AptSwfExport.h"
#include "Libraries/Source/Apt/AptSwfFormat.h"
#include "Libraries/Source/Apt/AptSwfImport.h"
#include "Libraries/Source/Apt/AptSwfTags.h"

#include <string>
#include <vector>

using namespace aptswf;
using apttest::Asm;
using apttest::TestMovie;

namespace
{

std::vector<std::uint8_t> bytesOf(const std::string &s)
{
	return std::vector<std::uint8_t>(s.begin(), s.end());
}

// A small movie: a red square shape (geometry 7), a font, a text field, a button with an action, a sprite that places the
// shape with a name and a clip event, and a root timeline with a label, the sprite, the text and the button.
struct SyntheticMovie
{
	AptMovieFiles files;
	std::uint32_t textId = 0, spriteId = 0, shapeId = 0, buttonId = 0;

	SyntheticMovie()
	{
		TestMovie m(7);
		Asm click = m.program();
		click.constantPool({ "onPress", "gotoAndPlay" }).pushString("menu").pushByte(1).pushConstByte(1).opU8(APT_OP_EA_CALLNAMEDFUNCPOP, 1).op(APT_OP_END);
		const std::uint32_t clickCode = m.commit(click);
		Asm frame = m.program();
		frame.op(APT_OP_STOP).op(APT_OP_END);
		const std::uint32_t frameCode = m.commit(frame);

		m.addCharacter(0); // id 0: the movie itself
		shapeId = m.addCharacter(m.addShape(0, 0, 10, 10, 7));
		const std::uint32_t fontId = m.addCharacter(m.addFont("Arial", {}));
		textId = m.addCharacter(m.addEditText("$Hello", "vTitle", 2, 16.0f, fontId));
		buttonId = m.addCharacter(m.addButton({ { 1, shapeId }, { 8, shapeId } }, { { 0x08, 0, clickCode } }));
		TestMovie::Place inSprite;
		inSprite.flags = APT_PLACE_HASCHARACTER | APT_PLACE_HASMATRIX | APT_PLACE_HASNAME | APT_PLACE_HASCLIPACTION;
		inSprite.characterId = (std::int32_t)shapeId;
		inSprite.depth = 1;
		inSprite.translation[0] = 3.25f;
		inSprite.name = "Square";
		inSprite.events.push_back({ APT_CLIP_ENTERFRAME, 0, frameCode });
		spriteId = m.addCharacter(m.addSprite({ { m.addPlaceItem(inSprite), m.addActionItem(frameCode) }, {} }));

		TestMovie::Place p1;
		p1.flags = APT_PLACE_HASCHARACTER | APT_PLACE_HASMATRIX | APT_PLACE_HASNAME;
		p1.characterId = (std::int32_t)spriteId;
		p1.depth = 1;
		p1.matrix[0] = 0.333333f; // not exactly representable in 16.16
		p1.translation[0] = 100.1f;
		p1.translation[1] = 50;
		p1.name = "Clip";
		TestMovie::Place p2;
		p2.flags = APT_PLACE_HASCHARACTER | APT_PLACE_HASMATRIX | APT_PLACE_HASCOLORTRANSFORM;
		p2.characterId = (std::int32_t)textId;
		p2.depth = 2;
		p2.tint[3] = 128;
		TestMovie::Place p3;
		p3.flags = APT_PLACE_HASCHARACTER | APT_PLACE_HASMATRIX;
		p3.characterId = (std::int32_t)buttonId;
		p3.depth = 3;
		p3.translation[0] = 200;
		m.setRootFrames({ { m.addLabelItem("start", 0, 0), m.addPlaceItem(p1), m.addPlaceItem(p2), m.addPlaceItem(p3), m.addActionItem(frameCode) } });
		m.addExport("Square", shapeId);

		std::vector<std::uint8_t> apt, cst;
		m.build(apt, cst);
		files.name = "Test";
		files.files.push_back({ "Test.apt", apt });
		files.files.push_back({ "Test.const", cst });
		files.files.push_back({ "Test.dat", bytesOf("; image map\r\n") });
		files.files.push_back({ "Test_geometry/7.ru", bytesOf("c\r\ns s:255:0:0:255\r\nt 0:0:10:0:10:10\r\nt 0:0:10:10:0:10\r\n") });
	}
};

std::vector<std::uint8_t> exportOf(const AptMovieFiles &files, ExportResult &r)
{
	std::vector<std::uint8_t> swf;
	std::string error;
	ExportOptions options;
	REQUIRE_MESSAGE(exportSwf(files, options, swf, r, &error), error);
	return swf;
}

const AptMovieFile *fileNamed(const ImportResult &r, const std::string &path)
{
	for (const AptMovieFile &f : r.files)
	{
		if (f.path == path)
		{
			return &f;
		}
	}
	return nullptr;
}

} // namespace

TEST_CASE("apt-swf: SWF bit fields, RECT, MATRIX and CXFORMWITHALPHA encode and decode exactly")
{
	CHECK(swfSignedBits(0) == 1);
	CHECK(swfSignedBits(-1) == 1);
	CHECK(swfSignedBits(1) == 2);
	CHECK(swfSignedBits(20480) == 16);
	CHECK(swfSignedBits(-20480) == 16);

	SwfWriter w;
	w.rect(0, 20480, 0, 15360);
	// nbits 16: 5 + 4 * 16 = 69 bits -> 9 bytes
	CHECK(w.bytes.size() == 9);
	CHECK(w.bytes[0] == 0x80); // 10000 then the first bits of 0

	SwfMatrix m = swfMatrixFromFloats(0.5f, 0.25f, -0.25f, 2.0f, 12.35f, -7.0f);
	CHECK(m.scaleX == 32768);
	CHECK(m.scaleY == 131072);
	CHECK(m.rotateSkew0 == 16384);
	CHECK(m.rotateSkew1 == -16384);
	CHECK(m.translateX == 247);
	CHECK(m.translateY == -140);
	SwfCxform c;
	c.hasMult = true;
	c.mult[3] = 128;
	c.hasAdd = true;
	c.add[0] = 255;
	SwfWriter w2;
	w2.matrix(m);
	w2.cxformWithAlpha(c);
	SwfReader r(w2.bytes.data(), w2.bytes.size());
	CHECK(r.matrix() == m);
	CHECK(r.cxformWithAlpha() == c);
	CHECK(r.ok());
}

TEST_CASE("apt-swf: zlib stored blocks round trip through the inflater, which also reads a compressed stream")
{
	std::vector<std::uint8_t> data(70000);
	for (std::size_t i = 0; i < data.size(); ++i)
	{
		data[i] = (std::uint8_t)(i * 7);
	}
	const std::vector<std::uint8_t> z = zlibStore(data.data(), data.size());
	CHECK(z.size() == data.size() + 2 + 2 * 5 + 4); // header, two stored blocks, Adler-32
	std::vector<std::uint8_t> back;
	std::string error;
	REQUIRE(zlibInflate(z.data(), z.size(), back, &error));
	CHECK(back == data);

	// zlib.compress(b'OpenBFME APT SWF ' * 8, 9) (Python 3), a fixed-Huffman stream with back references
	const std::uint8_t compressed[] = { 0x78, 0xda, 0xf3, 0x2f, 0x48, 0xcd, 0x73, 0x72, 0xf3, 0x75, 0x55, 0x70, 0x0c, 0x08, 0x51, 0x08, 0x0e,
		0x77, 0x53, 0xf0, 0x1f, 0x18, 0x01, 0x00, 0x91, 0x6a, 0x27, 0x09 };
	REQUIRE(zlibInflate(compressed, sizeof(compressed), back, &error));
	std::string text(back.begin(), back.end());
	std::string want;
	for (int i = 0; i < 8; ++i)
	{
		want += "OpenBFME APT SWF ";
	}
	CHECK(text == want);
}

TEST_CASE("apt-swf: EA opcodes lower to their standard AVM1 sequences, with constant pool references")
{
	TestMovie m(7);
	Asm a = m.program();
	a.constantPool({ "foo", "bar" }).pushByte(5).pushConstByte(1).opU8(APT_OP_EA_CALLNAMEDFUNCPOP, 0).op(APT_OP_END);
	const std::uint32_t code = m.commit(a);
	m.addCharacter(0);
	m.setRootFrames({ { m.addActionItem(code) } });
	AptFile file;
	std::string error;
	REQUIRE_MESSAGE(m.parse(file, &error), error);
	std::shared_ptr<const AptCodeBlock> block = file.codeAt(code, &error);
	REQUIRE_MESSAGE(block, error);
	Avm1Result r;
	REQUIRE(aptToAvm1(*block, r, &error));
	const std::vector<std::uint8_t> want = {
		0x88, 0x0A, 0x00, 0x02, 0x00, 'f', 'o', 'o', 0x00, 'b', 'a', 'r', 0x00, // ConstantPool
		0x96, 0x05, 0x00, 0x07, 0x05, 0x00, 0x00, 0x00,                         // EA_PushByte 5 -> Push int 5
		0x96, 0x02, 0x00, 0x08, 0x01,                                           // EA_PushConstantByte 1 -> Push constant8 1
		0x96, 0x02, 0x00, 0x08, 0x00, 0x3D, 0x17,                               // EA_CallNamedFuncPop 0 -> Push c0, CallFunction, Pop
		0x00 };
	CHECK(r.bytes == want);
	CHECK(r.eaOpcodes == 3);
	CHECK(r.instructions == 5);
	CHECK(r.notes.empty());
}

TEST_CASE("apt-swf: branch offsets are recomputed for the expanded code")
{
	TestMovie m(7);
	Asm a = m.program();
	a.op(APT_OP_EA_PUSHTRUE).branchIfTrue("L").pushByte(1).label("L").op(APT_OP_END);
	const std::uint32_t code = m.commit(a);
	m.addCharacter(0);
	m.setRootFrames({ { m.addActionItem(code) } });
	AptFile file;
	std::string error;
	REQUIRE_MESSAGE(m.parse(file, &error), error);
	std::shared_ptr<const AptCodeBlock> block = file.codeAt(code, &error);
	REQUIRE_MESSAGE(block, error);
	Avm1Result r;
	REQUIRE(aptToAvm1(*block, r, &error));
	const std::vector<std::uint8_t> want = {
		0x96, 0x02, 0x00, 0x05, 0x01,                   // Push true
		0x9D, 0x02, 0x00, 0x08, 0x00,                   // If +8 (over the 8-byte Push)
		0x96, 0x05, 0x00, 0x07, 0x01, 0x00, 0x00, 0x00, // Push int 1
		0x00 };
	CHECK(r.bytes == want);
}

TEST_CASE("apt-swf: two triangles of a square become one clockwise outline")
{
	const std::vector<float> tris = { 0, 0, 10, 0, 10, 10, 0, 0, 10, 10, 0, 10 };
	const auto loops = triangleOutlinesTwips(tris);
	REQUIRE(loops.size() == 1);
	const std::vector<std::pair<std::int32_t, std::int32_t>> want = { { 0, 0 }, { 200, 0 }, { 200, 200 }, { 0, 200 }, { 0, 0 } };
	CHECK(loops[0] == want);
}

TEST_CASE("apt-swf: a synthetic movie exports to the expected standard tags")
{
	SyntheticMovie movie;
	ExportResult r;
	const std::vector<std::uint8_t> swf = exportOf(movie.files, r);
	CHECK(swf[0] == 'F');
	CHECK(swf[3] == 7);
	CHECK(r.header.frameWidthTwips == 1024 * 20);
	CHECK(r.header.frameRate8_8 == 7758); // 1000 / 33 ms * 256
	std::vector<std::uint16_t> codes;
	for (const SwfTag &t : r.tags)
	{
		codes.push_back(t.code);
	}
	// shape 1, font 2, text 3, button 4 (its hit shape 6 first), sprite 5, exports, then frame 1
	const std::vector<std::uint16_t> want = { SWF_TAG_DEFINESHAPE3, SWF_TAG_DEFINEFONT2, SWF_TAG_DEFINEEDITTEXT, SWF_TAG_DEFINESHAPE3,
		SWF_TAG_DEFINEBUTTON2, SWF_TAG_DEFINESPRITE, SWF_TAG_EXPORTASSETS, SWF_TAG_FRAMELABEL, SWF_TAG_PLACEOBJECT2, SWF_TAG_PLACEOBJECT2,
		SWF_TAG_PLACEOBJECT2, SWF_TAG_DOACTION, SWF_TAG_SHOWFRAME };
	CHECK(codes == want);
	SwfEditText text;
	REQUIRE(decodeEditText(r.tags[2].body, text));
	CHECK(text.id == movie.textId);
	CHECK(text.initialText == "$Hello");
	CHECK(text.variableName == "vTitle");
	CHECK(text.fontHeight == 320);
	CHECK(text.align == 2);
	CHECK(text.bounds[1] == 2000);
	SwfButton2 button;
	REQUIRE(decodeButton2(r.tags[4].body, button));
	REQUIRE(button.records.size() == 2);
	CHECK(button.records[1].flags == 8);
	CHECK(button.records[1].characterId == 6); // the hit mesh shape
	// size 0 (last) + 2 flag bytes + the program: ConstantPool 25, Push "menu" 9, Push 1 8, Push c1 5, Push c1 / CallFunction / Pop 7, End 1
	CHECK(button.condActions.size() == 59);
	CHECK(button.condActions[2] == 0x08); // OverDownToOverUp
	const SwfTag &sprite = r.tags[5];
	REQUIRE(sprite.children.size() == 4); // PlaceObject2, DoAction, ShowFrame, ShowFrame
	SwfPlaceObject2 inner;
	REQUIRE(decodePlaceObject2(sprite.children[0].body, inner));
	CHECK(inner.name == "Square");
	CHECK(inner.matrix.translateX == 65);
	// reserved 2 + all-events 4 + (event flags 4 + size 4 + Stop End 2) + end flag 4
	CHECK(inner.clipActions.size() == 20);
	CHECK(r.stats.eaOpcodes == 4);
	CHECK(r.stats.programs == 2);
}

TEST_CASE("apt-swf: SWF -> APT of an unedited export gives back every file byte for byte")
{
	SyntheticMovie movie;
	ExportResult r;
	const std::vector<std::uint8_t> swf = exportOf(movie.files, r);
	ImportResult back;
	std::string error;
	REQUIRE_MESSAGE(importSwf(swf, back, &error), error);
	CHECK(back.movieName == "Test");
	CHECK(back.editedTags == 0);
	REQUIRE(back.files.size() == movie.files.files.size());
	for (std::size_t i = 0; i < back.files.size(); ++i)
	{
		CHECK(back.files[i].path == movie.files.files[i].path);
		CHECK(back.files[i].bytes == movie.files.files[i].bytes);
	}
	// re-saving the SWF with its standard tags re-encoded (as an editor does) changes nothing either
	SwfFile parsed;
	REQUIRE(swfReadFile(swf, parsed, &error));
	CHECK(swfWriteFile(parsed.header, parsed.tags) == swf);
}

TEST_CASE("apt-swf: a text and a placement edited in the SWF are re-encoded into the .apt records")
{
	SyntheticMovie movie;
	ExportResult r;
	const std::vector<std::uint8_t> swf = exportOf(movie.files, r);
	SwfFile parsed;
	std::string error;
	REQUIRE(swfReadFile(swf, parsed, &error));
	for (SwfTag *t : flattenTagsMutable(parsed.tags))
	{
		SwfEditText et;
		if (t->code == SWF_TAG_DEFINEEDITTEXT && decodeEditText(t->body, et))
		{
			et.initialText = "Edited in SWF";
			t->body = encodeEditText(et);
		}
		SwfPlaceObject2 po;
		if (t->code == SWF_TAG_PLACEOBJECT2 && decodePlaceObject2(t->body, po) && po.name == "Clip")
		{
			po.matrix.translateY += 200; // 10 pixels down
			t->body = encodePlaceObject2(po);
		}
	}
	ImportResult back;
	REQUIRE_MESSAGE(importSwf(swfWriteFile(parsed.header, parsed.tags), back, &error), error);
	CHECK(back.editedTags == 2);
	REQUIRE(back.edits.size() == 2);
	CHECK(back.edits[0] == "text field 3: text '$Hello' -> 'Edited in SWF'");
	CHECK(back.edits[1] == "place object (depth 1, 'Clip'): y 50 -> 60");
	// the other files are untouched; the .apt parses with the new values and keeps the unedited float bits
	CHECK(fileNamed(back, "Test.const")->bytes == movie.files.files[1].bytes);
	CHECK(fileNamed(back, "Test_geometry/7.ru")->bytes == movie.files.files[3].bytes);
	AptConstFile consts;
	REQUIRE(AptConstFile::parse(fileNamed(back, "Test.const")->bytes, consts, &error));
	AptFile edited;
	REQUIRE_MESSAGE(AptFile::parse("Test", std::make_shared<const std::vector<std::uint8_t>>(fileNamed(back, "Test.apt")->bytes), consts, edited, &error), error);
	CHECK(edited.characters[movie.textId].text->initialText == "Edited in SWF");
	const AptPlaceObject &clip = *edited.frames[0].items[1].place;
	CHECK(clip.translation[1] == 60.0f);
	CHECK(clip.translation[0] == 100.1f);  // unedited: the original float, not 2002 twips / 20
	CHECK(clip.matrix[0] == 0.333333f);    // unedited: the original float, not its 16.16 value
	// the edited .apt round-trips through the converter again
	std::vector<std::uint8_t> swf2;
	ExportResult r2;
	AptMovieFiles again;
	again.name = "Test";
	again.files = back.files;
	REQUIRE_MESSAGE(exportSwf(again, ExportOptions(), swf2, r2, &error), error);
	ImportResult back2;
	REQUIRE_MESSAGE(importSwf(swf2, back2, &error), error);
	CHECK(fileNamed(back2, "Test.apt")->bytes == fileNamed(back, "Test.apt")->bytes);
}

TEST_CASE("apt-swf: edits the milestone cannot re-encode are refused with the tag named")
{
	SyntheticMovie movie;
	ExportResult r;
	const std::vector<std::uint8_t> swf = exportOf(movie.files, r);
	SwfFile parsed;
	std::string error;
	REQUIRE(swfReadFile(swf, parsed, &error));
	SUBCASE("an action")
	{
		for (SwfTag *t : flattenTagsMutable(parsed.tags))
		{
			if (t->code == SWF_TAG_DOACTION)
			{
				t->body.insert(t->body.begin(), 0x06); // Play before Stop
				break;
			}
		}
		ImportResult back;
		CHECK_FALSE(importSwf(swfWriteFile(parsed.header, parsed.tags), back, &error));
		CHECK(error.find("DoAction #") == 0);
		CHECK(error.find("not supported in this milestone") != std::string::npos);
	}
	SUBCASE("a removed tag")
	{
		parsed.tags.pop_back();
		ImportResult back;
		CHECK_FALSE(importSwf(swfWriteFile(parsed.header, parsed.tags), back, &error));
		CHECK(error.find("structural edit") != std::string::npos);
	}
	SUBCASE("a SWF without the private tags")
	{
		std::vector<SwfTag> standard;
		for (SwfTag &t : parsed.tags)
		{
			if (t.code != SWF_TAG_OPENBFME_APT)
			{
				standard.push_back(t);
			}
		}
		ImportResult back;
		CHECK_FALSE(importSwf(swfWriteFile(parsed.header, standard), back, &error));
		CHECK(error.find("has no OpenBFME APT data") != std::string::npos);
	}
}
