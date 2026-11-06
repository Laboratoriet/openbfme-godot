// OpenBFME unit tests: the APT <-> SWF converter (docs/APT-SWF.md).  Synthetic movies only (AptTestUtil.h builds them
// byte by byte); the retail corpus round trip is the tool's `roundtrip` command, run with the user's own game files.  GPL-3.0.

#include "doctest.h"
#include "AptTestUtil.h"

#include "Libraries/Source/Apt/AptSwfAssemble.h"
#include "Libraries/Source/Apt/AptSwfAvm1.h"
#include "Libraries/Source/Apt/AptSwfExport.h"
#include "Libraries/Source/Apt/AptSwfFormat.h"
#include "Libraries/Source/Apt/AptSwfImport.h"
#include "Libraries/Source/Apt/AptSwfRecipe.h"
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

TEST_CASE("apt-swf: DefineFunction2's SWF flag bytes are the 2nd and 3rd byte of the decoder's flags")
{
	// RotWK QuitMenu.apt's InitialSetup has the flag bytes 00 6A 01: SWF PreloadRoot, SuppressSuper / Arguments / This, PreloadGlobal
	TestMovie m(7);
	Asm a = m.program();
	a.defineFunction2("f", 3, 0x016A00, {}, [](Asm &body) { body.op(APT_OP_STOP); }).op(APT_OP_END);
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
		0x8E, 0x09, 0x00, 'f', 0x00, 0x00, 0x00, 0x03, 0x6A, 0x01, 0x01, 0x00, // name, 0 params, 3 registers, flags, body size 1
		0x07,                                                                  // Stop
		0x00 };
	CHECK(r.bytes == want);
	CHECK(r.notes.empty());
}

TEST_CASE("apt-swf: two triangles of a square become one clockwise outline")
{
	const std::vector<float> tris = { 0, 0, 10, 0, 10, 10, 0, 0, 10, 10, 0, 10 };
	const auto loops = triangleOutlinesTwips(tris);
	REQUIRE(loops.size() == 1);
	const std::vector<std::pair<std::int32_t, std::int32_t>> want = { { 0, 0 }, { 200, 0 }, { 200, 200 }, { 0, 200 }, { 0, 0 } };
	CHECK(loops[0] == want);
}

namespace
{

// The synthetic square as another encoder might write it: wider bit fields, general-line edges for straight ones, the
// selection in a record of its own. `dx` moves the second corner.
std::vector<std::uint8_t> squareReencoded(std::uint16_t id, std::int32_t dx)
{
	SwfWriter w;
	w.u16(id);
	w.rect(0, 200, 0, 200);
	w.u8(0);
	w.u8(0);
	w.ub(4, 0);
	w.ub(4, 0);
	// new styles: one solid red fill, no lines
	w.ub(6, 0x10);
	w.u8(1);
	w.u8(0x00);
	w.u8(255);
	w.u8(0);
	w.u8(0);
	w.u8(255);
	w.u8(0);
	w.ub(4, 1);
	w.ub(4, 0);
	// move to (0, 0) with 12-bit fields, then select fill style 1 without moving
	w.ub(6, 0x01);
	w.ub(5, 12);
	w.sb(12, 0);
	w.sb(12, 0);
	w.ub(6, 0x04);
	w.ub(1, 1);
	const std::int32_t pts[4][2] = { { 200 + dx, 0 }, { 200, 200 }, { 0, 200 }, { 0, 0 } };
	std::int32_t x = 0, y = 0;
	for (const auto &p : pts)
	{
		w.ub(2, 3);  // edge, straight
		w.ub(4, 12); // 14-bit deltas
		w.ub(1, 1);  // general line
		w.sb(14, p[0] - x);
		w.sb(14, p[1] - y);
		x = p[0];
		y = p[1];
	}
	w.ub(6, 0);
	w.align();
	return w.bytes;
}

} // namespace

TEST_CASE("apt-swf: a re-encoded shape is recognised as the same drawing, a moved point is not")
{
	SyntheticMovie movie;
	ExportResult r;
	exportOf(movie.files, r);
	const std::vector<std::uint8_t> &ours = r.tags[0].body;
	REQUIRE(r.tags[0].code == SWF_TAG_DEFINESHAPE3);
	const std::vector<std::uint8_t> same = squareReencoded((std::uint16_t)movie.shapeId, 0);
	CHECK(same != ours);
	std::string why;
	CHECK(shapesEquivalent(ours, same, 2, &why));
	CHECK_FALSE(shapesEquivalent(ours, squareReencoded((std::uint16_t)movie.shapeId, 20), 2, &why));
	CHECK(why == "layer 0: path 0 changed");
}

TEST_CASE("apt-swf: the standard tags' structure does not depend on whether the textures load")
{
	SyntheticMovie movie;
	// a textured style whose image id 3 the image map sends to texture 1
	movie.files.files[2].bytes = bytesOf("3->1\r\n");
	movie.files.files[3].bytes = bytesOf("c\r\ns tc:255:255:255:255:3:1:0:0:1:0:0\r\nt 0:0:10:0:10:10\r\n");
	ExportOptions with;
	with.textures = [](const std::string &name, AptTexture &out, std::string *) {
		CHECK(name == "apt_Test_1.tga");
		out.width = 2;
		out.height = 1;
		out.rgba = { 255, 0, 0, 255, 0, 0, 255, 128 };
		return true;
	};
	ExportResult a, b;
	std::string error;
	REQUIRE_MESSAGE(exportStandardTags(movie.files, with, a, &error), error);
	REQUIRE_MESSAGE(exportStandardTags(movie.files, ExportOptions(), b, &error), error);
	const std::vector<const SwfTag *> fa = flattenTags(a.tags), fb = flattenTags(b.tags);
	REQUIRE(fa.size() == fb.size());
	std::size_t differing = 0;
	for (std::size_t i = 0; i < fa.size(); ++i)
	{
		CHECK(fa[i]->code == fb[i]->code);
		differing += fa[i]->body != fb[i]->body ? 1 : 0;
	}
	CHECK(differing == 1); // the bitmap's pixels only
	REQUIRE(fa[0]->code == SWF_TAG_DEFINEBITSLOSSLESS2);
	// 2 x 1 premultiplied ARGB: (255, 255, 0, 0) and (128, 0, 0, 128)
	std::vector<std::uint8_t> pixels;
	REQUIRE(zlibInflate(fa[0]->body.data() + 7, fa[0]->body.size() - 7, pixels, &error));
	const std::vector<std::uint8_t> want = { 255, 255, 0, 0, 128, 0, 0, 128 };
	CHECK(pixels == want);
}

TEST_CASE("apt-swf: a synthetic movie exports to the expected standard tags")
{
	SyntheticMovie movie;
	ExportResult r;
	const std::vector<std::uint8_t> swf = exportOf(movie.files, r);
	CHECK(swf[0] == 'F');
	CHECK(swf[3] == 6); // SWF 6: case-insensitive names, as EA's runtime
	CHECK(r.notes.count("Apt version 7 movies are written as SWF 6 (case-insensitive names, as EA's runtime); SWF 7's conversion rules "
						"(undefined to string / number) then differ in a SWF player") == 1);
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
	SUBCASE("a clip action")
	{
		for (SwfTag *t : flattenTagsMutable(parsed.tags))
		{
			SwfPlaceObject2 po;
			if (t->code == SWF_TAG_PLACEOBJECT2 && decodePlaceObject2(t->body, po) && po.name == "Square")
			{
				po.clipActions[14] = 0x06; // Play instead of Stop
				t->body = encodePlaceObject2(po);
				break;
			}
		}
		ImportResult back;
		CHECK_FALSE(importSwf(swfWriteFile(parsed.header, parsed.tags), back, &error));
		CHECK(error.find("PlaceObject2 #") == 0);
		CHECK(error.find("the clip actions changed (clip action programs are not re-assembled yet; frame actions are)") != std::string::npos);
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

namespace
{

// The edited SWF: `parsed` with its tags written back.  The root timeline's one frame ends with the last top-level tag (ShowFrame).
struct EditedSwf
{
	SwfFile parsed;
	SyntheticMovie movie;

	EditedSwf()
	{
		ExportResult r;
		const std::vector<std::uint8_t> swf = exportOf(movie.files, r);
		std::string error;
		REQUIRE(swfReadFile(swf, parsed, &error));
		REQUIRE(parsed.tags.back().code == SWF_TAG_SHOWFRAME);
	}

	// inserts a tag at the end of the root's frame 1 (before its ShowFrame)
	void addToRoot(std::uint16_t code, std::vector<std::uint8_t> body)
	{
		SwfTag t;
		t.code = code;
		t.body = std::move(body);
		parsed.tags.insert(parsed.tags.end() - 1, t);
	}

	SwfTag *sprite(std::uint32_t id)
	{
		for (SwfTag &t : parsed.tags)
		{
			if (t.code == SWF_TAG_DEFINESPRITE && t.body[0] == id)
			{
				return &t;
			}
		}
		return nullptr;
	}

	bool import(ImportResult &back, std::string &error) { return importSwf(swfWriteFile(parsed.header, parsed.tags), back, &error); }
};

AptFile parsedApt(const ImportResult &back)
{
	std::string error;
	AptConstFile consts;
	REQUIRE(AptConstFile::parse(fileNamed(back, "Test.const")->bytes, consts, &error));
	AptFile apt;
	REQUIRE_MESSAGE(AptFile::parse("Test", std::make_shared<const std::vector<std::uint8_t>>(fileNamed(back, "Test.apt")->bytes), consts, apt, &error), error);
	return apt;
}

// The edited movie exported again and imported unedited: the same files (the edit is a stable APT movie, not a one-off).
void checkStableAfterEdit(const ImportResult &back)
{
	AptMovieFiles again;
	again.name = "Test";
	again.files = back.files;
	std::vector<std::uint8_t> swf2;
	ExportResult r2;
	std::string error;
	REQUIRE_MESSAGE(exportSwf(again, ExportOptions(), swf2, r2, &error), error);
	ImportResult back2;
	REQUIRE_MESSAGE(importSwf(swf2, back2, &error), error);
	CHECK(back2.editedTags == 0);
	CHECK(fileNamed(back2, "Test.apt")->bytes == fileNamed(back, "Test.apt")->bytes);
}

std::size_t firstTagIndex(const std::vector<SwfTag> &tags, std::uint16_t code)
{
	for (std::size_t i = 0; i < tags.size(); ++i)
	{
		if (tags[i].code == code)
		{
			return i;
		}
	}
	return tags.size();
}

} // namespace

TEST_CASE("apt-swf: a new PlaceObject2 of an existing character becomes a new APT place-object record")
{
	EditedSwf e;
	SwfPlaceObject2 p;
	p.flags = 0x02 | 0x04 | 0x08 | 0x20; // character, matrix, colour, name
	p.depth = 7;
	p.characterId = (std::uint16_t)e.movie.spriteId;
	p.matrix = swfMatrixFromFloats(0.5f, 0, 0, 2.0f, 40.0f, -12.5f);
	p.cxform.hasMult = true;
	p.cxform.mult[3] = 128; // alpha 0.5
	p.name = "Copy";
	e.addToRoot(SWF_TAG_PLACEOBJECT2, encodePlaceObject2(p));
	// and one inside the sprite, after its own placement (a second copy of the shape)
	SwfPlaceObject2 q;
	q.flags = 0x02 | 0x04;
	q.depth = 2;
	q.characterId = (std::uint16_t)e.movie.shapeId;
	q.matrix = swfMatrixFromFloats(1, 0, 0, 1, 20.0f, 0);
	SwfTag *sprite = e.sprite(e.movie.spriteId);
	REQUIRE(sprite);
	SwfTag t;
	t.code = SWF_TAG_PLACEOBJECT2;
	t.body = encodePlaceObject2(q);
	sprite->children.insert(sprite->children.begin() + 1, t);

	ImportResult back;
	std::string error;
	REQUIRE_MESSAGE(e.import(back, error), error);
	REQUIRE(back.edits.size() == 2);
	CHECK(back.edits[0] == "the root timeline frame 1: new place object (depth 7, character 5, 'Copy', at (40, -12.5))");
	CHECK(back.edits[1] == "sprite 5 frame 1: new place object (depth 2, character 1, at (20, 0))");
	CHECK(fileNamed(back, "Test.const")->bytes == e.movie.files.files[1].bytes);
	CHECK(fileNamed(back, "Test_geometry/7.ru")->bytes == e.movie.files.files[3].bytes);
	const AptFile apt = parsedApt(back);
	REQUIRE(apt.frames[0].items.size() == 6);
	const AptPlaceObject &added = *apt.frames[0].items[5].place;
	CHECK(added.flags == (APT_PLACE_HASCHARACTER | APT_PLACE_HASMATRIX | APT_PLACE_HASCOLORTRANSFORM | APT_PLACE_HASNAME));
	CHECK(added.depth == 7);
	CHECK(added.characterId == (std::int32_t)e.movie.spriteId);
	CHECK(added.matrix[0] == 0.5f);
	CHECK(added.matrix[3] == 2.0f);
	CHECK(added.translation[0] == 40.0f);
	CHECK(added.translation[1] == -12.5f);
	CHECK(added.tint[3] == 128);
	CHECK(added.tint[0] == 255);
	CHECK(added.name == "Copy");
	CHECK(added.clipDepth == -1);
	// the frame's other items are the original records, in their order
	CHECK(apt.frames[0].items[0].label == "start");
	CHECK(apt.frames[0].items[1].place->name == "Clip");
	CHECK(apt.frames[0].items[1].place->matrix[0] == 0.333333f);
	const AptFrame &spriteFrame = apt.characters[e.movie.spriteId].frames[0];
	REQUIRE(spriteFrame.items.size() == 3);
	CHECK(spriteFrame.items[0].place->name == "Square");
	CHECK(spriteFrame.items[1].place->characterId == (std::int32_t)e.movie.shapeId);
	CHECK(spriteFrame.items[1].place->translation[0] == 20.0f);
	CHECK(spriteFrame.items[2].type == APT_ITEM_ACTION);
	checkStableAfterEdit(back);
}

TEST_CASE("apt-swf: RemoveObject2 added and a placement taken out of a frame")
{
	EditedSwf e;
	SwfWriter w;
	w.u16(3);
	e.addToRoot(SWF_TAG_REMOVEOBJECT2, w.bytes);
	// take the text field's placement (depth 2) out of the root frame
	for (auto it = e.parsed.tags.begin(); it != e.parsed.tags.end(); ++it)
	{
		SwfPlaceObject2 p;
		if (it->code == SWF_TAG_PLACEOBJECT2 && decodePlaceObject2(it->body, p) && p.depth == 2)
		{
			e.parsed.tags.erase(it);
			break;
		}
	}
	ImportResult back;
	std::string error;
	REQUIRE_MESSAGE(e.import(back, error), error);
	REQUIRE(back.edits.size() == 2);
	CHECK(back.edits[0] == "the root timeline frame 1: new remove object (depth 3)");
	CHECK(back.edits[1] == "the root timeline frame 1: removed place object (depth 2)");
	const AptFile apt = parsedApt(back);
	REQUIRE(apt.frames[0].items.size() == 5);
	CHECK(apt.frames[0].items[0].type == APT_ITEM_FRAMELABEL);
	CHECK(apt.frames[0].items[1].place->depth == 1);
	CHECK(apt.frames[0].items[2].place->depth == 3);
	CHECK(apt.frames[0].items[3].type == APT_ITEM_ACTION);
	CHECK(apt.frames[0].items[4].type == APT_ITEM_REMOVEOBJECT);
	CHECK(apt.frames[0].items[4].removeDepth == 3);
	checkStableAfterEdit(back);
}

TEST_CASE("apt-swf: a new frame label gets the retail label fields")
{
	EditedSwf e;
	SwfWriter w;
	w.cstring("_open");
	e.addToRoot(SWF_TAG_FRAMELABEL, w.bytes);
	ImportResult back;
	std::string error;
	REQUIRE_MESSAGE(e.import(back, error), error);
	REQUIRE(back.edits.size() == 1);
	CHECK(back.edits[0] == "the root timeline frame 1: new frame label '_open'");
	const AptFile apt = parsedApt(back);
	REQUIRE(apt.frames[0].items.size() == 6);
	CHECK(apt.frames[0].items[5].label == "_open");
	CHECK(apt.frames[0].items[5].labelFlags == 0x70000);
	CHECK(apt.frames[0].items[5].labelFrameId == 0);
	checkStableAfterEdit(back);
}

TEST_CASE("apt-swf: a new DefineEditText becomes a new APT text character, placed by its SWF id")
{
	EditedSwf e;
	SwfEditText t;
	t.id = 40; // an editor's new id, above the converter's own (the hit shape is 6)
	t.bounds[0] = 0;
	t.bounds[1] = 2000;
	t.bounds[2] = 20;
	t.bounds[3] = 400;
	t.flags1 = 0x80 | 0x08 | 0x04 | 0x01; // text, read-only, colour, font
	t.flags2 = 0x20;                       // layout
	t.fontId = 2;
	t.fontHeight = 240;
	t.color[0] = 200;
	t.color[1] = 100;
	t.color[2] = 50;
	t.color[3] = 255;
	t.align = 1;
	t.variableName = "FactionName_7";
	t.initialText = "$Stats:FactionName_7";
	SwfTag def;
	def.code = SWF_TAG_DEFINEEDITTEXT;
	def.body = encodeEditText(t);
	e.parsed.tags.insert(e.parsed.tags.begin() + (std::ptrdiff_t)firstTagIndex(e.parsed.tags, SWF_TAG_EXPORTASSETS), def);
	SwfPlaceObject2 p;
	p.flags = 0x02 | 0x04 | 0x20;
	p.depth = 9;
	p.characterId = 40;
	p.matrix = swfMatrixFromFloats(1, 0, 0, 1, 10, 20);
	p.name = "Name7";
	e.addToRoot(SWF_TAG_PLACEOBJECT2, encodePlaceObject2(p));
	ImportResult back;
	std::string error;
	REQUIRE_MESSAGE(e.import(back, error), error);
	REQUIRE(back.edits.size() == 2);
	CHECK(back.edits[0] == "new text field 40 -> APT character 6 ('$Stats:FactionName_7', variable 'FactionName_7')");
	CHECK(back.edits[1] == "the root timeline frame 1: new place object (depth 9, character 6, 'Name7', at (10, 20))");
	const AptFile apt = parsedApt(back);
	REQUIRE(apt.characters.size() == 7);
	REQUIRE(apt.characters[6].text);
	const AptTextInfo &text = *apt.characters[6].text;
	CHECK(text.initialText == "$Stats:FactionName_7");
	CHECK(text.variableName == "FactionName_7");
	CHECK(text.fontId == 2);
	CHECK(text.fontHeight == 12.0f);
	CHECK(text.alignment == 1);
	CHECK(text.readOnly);
	CHECK_FALSE(text.multiline);
	CHECK(text.color[0] == 200);
	CHECK(text.color[2] == 50);
	CHECK(text.bounds[0] == 0.0f);
	CHECK(text.bounds[1] == 1.0f);
	CHECK(text.bounds[2] == 100.0f);
	CHECK(text.bounds[3] == 20.0f);
	CHECK(apt.frames[0].items[5].place->characterId == 6);
	checkStableAfterEdit(back);
}

TEST_CASE("apt-swf: structural edits still beyond the importer are refused, naming the tag")
{
	EditedSwf e;
	std::string error;
	ImportResult back;
	SUBCASE("a new DoAction with an action the APT runtime does not have (With)")
	{
		e.addToRoot(SWF_TAG_DOACTION, { 0x94, 0x02, 0x00, 0x00, 0x00, 0x00 });
		CHECK_FALSE(e.import(back, error));
		CHECK(error.find("DoAction #") == 0);
		CHECK(error.find("action 0x94 (#0) is not an action the APT runtime has") != std::string::npos);
	}
	SUBCASE("a new shape")
	{
		SwfTag shape = e.parsed.tags[firstTagIndex(e.parsed.tags, SWF_TAG_DEFINESHAPE3)];
		shape.body[0] = 50;
		e.parsed.tags.insert(e.parsed.tags.begin() + (std::ptrdiff_t)firstTagIndex(e.parsed.tags, SWF_TAG_EXPORTASSETS), shape);
		CHECK_FALSE(e.import(back, error));
		CHECK(error.find("a new character 50 (DefineShape3): only new text fields (DefineEditText) can be added") != std::string::npos);
	}
	SUBCASE("a new frame")
	{
		SwfTag show;
		show.code = SWF_TAG_SHOWFRAME;
		e.parsed.tags.push_back(show);
		CHECK_FALSE(e.import(back, error));
		CHECK(error == "the root timeline has 2 frames where the movie has 1: frames were added or removed (a structural edit not supported: frame "
					   "items can be added and removed, frames cannot)");
	}
	SUBCASE("a placement of a character the converter made")
	{
		SwfPlaceObject2 p;
		p.flags = 0x02;
		p.depth = 20;
		p.characterId = 6; // the button's hit shape
		e.addToRoot(SWF_TAG_PLACEOBJECT2, encodePlaceObject2(p));
		CHECK_FALSE(e.import(back, error));
		CHECK(error.find("character 6 is not an APT character") != std::string::npos);
	}
	SUBCASE("a new placement with clip actions")
	{
		SwfPlaceObject2 p;
		p.flags = 0x80 | 0x02;
		p.depth = 20;
		p.characterId = (std::uint16_t)e.movie.spriteId;
		p.clipActions = { 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 0x07, 0x00, 0, 0, 0, 0 };
		e.addToRoot(SWF_TAG_PLACEOBJECT2, encodePlaceObject2(p));
		CHECK_FALSE(e.import(back, error));
		CHECK(error.find("a new placement with clip actions") != std::string::npos);
	}
}

TEST_CASE("apt-swf: a recipe's steps go through the SWF into the .apt")
{
	EditedSwf e;
	const std::string recipe = "openbfme-apt-recipe 1\n"
							   "# a comment\n"
							   "movie Test\n"
							   "note three more clips\n"
							   "expect sprite=0 name=Clip character=5\n"
							   "place sprite=0 frame=1 depth=10 character=5 name=Clip2 like=Clip x=200 y=60.5\n"
							   "set sprite=0 name=Clip dx=-10 scale=0.5,0.5\n"
							   "rename sprite=5 name=Square to=\"Square One\"\n"
							   "delete sprite=0 depth=2\n"
							   "remove sprite=0 frame=1 depth=3\n"
							   "label sprite=5 frame=1 name=_ten\n"
							   "text id=Name7 font=2 bounds=0,0,100,20 height=12 color=FF000080 align=center text=\"$Stats:FactionName_7\" var=v7 readonly\n"
							   "place sprite=0 frame=1 depth=11 character=Name7 name=N7 x=5 y=6\n";
	RecipeResult rr;
	std::string error;
	REQUIRE_MESSAGE(applyRecipe(recipe, e.parsed, "Test", rr, &error), error);
	CHECK(rr.movie == "Test");
	REQUIRE(rr.notes.size() == 1);
	CHECK(rr.notes[0] == "three more clips");
	REQUIRE(rr.log.size() == 9);
	CHECK(rr.log[1] == "placed character 5 in sprite 0 frame 1 depth 10 as 'Clip2' at (200, 60.5)");
	ImportResult back;
	REQUIRE_MESSAGE(e.import(back, error), error);
	const AptFile apt = parsedApt(back);
	REQUIRE(apt.characters.size() == 7); // the text field is character 6
	CHECK(apt.characters[6].text->initialText == "$Stats:FactionName_7");
	CHECK(apt.characters[6].text->variableName == "v7");
	CHECK(apt.characters[6].text->alignment == 2);
	CHECK(apt.characters[6].text->color[0] == 255);
	CHECK(apt.characters[6].text->color[3] == 128);
	const std::vector<AptFrameItem> &root = apt.frames[0].items;
	// label, Clip (moved, scaled), button (depth 3), action, then Clip2, the removal and the text's placement; the text field's placement is gone
	REQUIRE(root.size() == 7);
	CHECK(root[1].place->name == "Clip");
	CHECK(root[1].place->matrix[0] == 0.5f);
	CHECK(root[1].place->translation[0] == 90.1f);
	CHECK(root[1].place->translation[1] == 50.0f);
	CHECK(root[2].place->depth == 3);
	CHECK(root[4].place->name == "Clip2");
	CHECK(root[4].place->matrix[0] == (float)(21845 / 65536.0)); // the template's scale (0.333333 as SWF's 16.16 holds it)
	CHECK(root[4].place->translation[0] == 200.0f);
	CHECK(root[4].place->translation[1] == 60.5f);
	CHECK(root[5].type == APT_ITEM_REMOVEOBJECT);
	CHECK(root[5].removeDepth == 3);
	CHECK(root[6].place->characterId == 6);
	CHECK(root[6].place->name == "N7");
	const std::vector<AptFrameItem> &sprite = apt.characters[e.movie.spriteId].frames[0].items;
	REQUIRE(sprite.size() == 3);
	CHECK(sprite[0].place->name == "Square One");
	CHECK(sprite[2].label == "_ten");
	checkStableAfterEdit(back);
}

TEST_CASE("apt-swf: a recipe stops at the first line that does not fit the movie")
{
	EditedSwf e;
	RecipeResult rr;
	std::string error;
	CHECK_FALSE(applyRecipe("movie Test\n", e.parsed, "Test", rr, &error));
	CHECK(error == "line 1 (movie): the first line must be 'openbfme-apt-recipe 1' (this is not a recipe, or a newer format)");
	CHECK_FALSE(applyRecipe("openbfme-apt-recipe 1\nmovie Stats\n", e.parsed, "Test", rr, &error));
	CHECK(error == "line 2 (movie): the recipe is for the movie 'Stats', not 'Test'");
	CHECK_FALSE(applyRecipe("openbfme-apt-recipe 1\nmovie Test\nexpect sprite=0 name=Nope\n", e.parsed, "Test", rr, &error));
	CHECK(error == "line 3 (expect): this copy of the movie is not the one the recipe was written for: no placement matches (sprite=0 name=Nope)");
	CHECK_FALSE(applyRecipe("openbfme-apt-recipe 1\nmovie Test\nplace sprite=0 frame=1 depth=1 character=5\n", e.parsed, "Test", rr, &error));
	CHECK(error == "line 3 (place): depth 1 is already used in frame 1 of sprite 0 (pick a free depth)");
	CHECK_FALSE(applyRecipe("openbfme-apt-recipe 1\nmovie Test\nset sprite=0 name=Clip colour=red\n", e.parsed, "Test", rr, &error));
	CHECK(error == "line 3 (set): unknown setting 'colour'");
	CHECK_FALSE(applyRecipe("openbfme-apt-recipe 1\nmovie Test\nplace sprite=9 frame=1 depth=4 character=5\n", e.parsed, "Test", rr, &error));
	CHECK(error == "line 3 (place): the movie has no sprite 9");
	CHECK_FALSE(applyRecipe("openbfme-apt-recipe 1\nmovie Test\nlabel sprite=0 frame=2 name=x\n", e.parsed, "Test", rr, &error));
	CHECK(error == "line 3 (label): the timeline has 1 frames, no frame 2");
}

TEST_CASE("apt-swf: an edited DoAction is assembled back into APT and the frame item points at it")
{
	EditedSwf e;
	std::uint32_t before = 0;
	{
		const AptFile original = [&] {
			ImportResult unedited;
			std::string error;
			REQUIRE(e.import(unedited, error));
			return parsedApt(unedited);
		}();
		before = original.frames[0].items[4].codeOffset;
	}
	// the root's frame action is `Stop`; make it `Play`
	for (SwfTag &t : e.parsed.tags)
	{
		if (t.code == SWF_TAG_DOACTION)
		{
			REQUIRE(t.body == std::vector<std::uint8_t>({ 0x07, 0x00 }));
			t.body = { 0x06, 0x00 };
		}
	}
	ImportResult back;
	std::string error;
	REQUIRE_MESSAGE(e.import(back, error), error);
	REQUIRE(back.edits.size() == 1);
	const AptFile apt = parsedApt(back);
	const AptFrameItem &item = apt.frames[0].items[4];
	CHECK(item.codeOffset != before);
	CHECK(back.edits[0].find(": actions re-assembled at .apt offset " + std::to_string(item.codeOffset) + " (was " + std::to_string(before) + ")") !=
		std::string::npos);
	std::shared_ptr<const AptCodeBlock> block = apt.codeAt(item.codeOffset, &error);
	REQUIRE_MESSAGE(block, error);
	REQUIRE(block->instructions.size() == 2);
	CHECK(block->instructions[0].opcode == APT_OP_PLAY);
	CHECK(block->instructions[1].opcode == APT_OP_END);
	// the sprite's frame action shared the same program and is untouched
	CHECK(apt.characters[e.movie.spriteId].frames[0].items[1].codeOffset == before);
	checkStableAfterEdit(back);
}

TEST_CASE("apt-swf: AVM1 -> APT: pushes, a branch, a function and a register push assemble to the runtime's forms")
{
	// x = 300; if (!(x < 5)) { y = true; } f = function (a) { return a; }; push register 1; End
	const std::string recipe = "openbfme-apt-recipe 1\n"
							   "movie Test\n"
							   "action sprite=0 frame=1\n"
							   "  Push \"x\", 300\n"
							   "  SetVariable\n"
							   "  Push \"x\"\n"
							   "  GetVariable\n"
							   "  Push 5\n"
							   "  Less2\n"
							   "  If skip\n"
							   "  Push \"y\", true\n"
							   "  SetVariable\n"
							   "  skip:\n"
							   "  Push \"f\"\n"
							   "  DefineFunction \"\" 1 \"a\" {\n"
							   "    Push \"a\"\n"
							   "    GetVariable\n"
							   "    Return\n"
							   "  }\n"
							   "  SetVariable\n"
							   "  Push register1, 2.5, -70000, null, undefined, false\n"
							   "  Pop\n"
							   "end\n"
							   "value sprite=0 frame=1 action=2 old=300 new=7\n";
	EditedSwf e;
	RecipeResult rr;
	std::string error;
	REQUIRE_MESSAGE(applyRecipe(recipe, e.parsed, "Test", rr, &error), error);
	CHECK(rr.log[1] == "sprite 0 frame 1 action list 2: the integer 300 -> 7 (1x)");
	ImportResult back;
	REQUIRE_MESSAGE(e.import(back, error), error);
	REQUIRE(back.edits.size() == 2);
	CHECK(back.edits[1] == "Test.const: 1 register entries added");
	const AptFile apt = parsedApt(back);
	AptConstFile originalConsts;
	REQUIRE(AptConstFile::parse(e.movie.files.files[1].bytes, originalConsts, &error));
	REQUIRE(apt.consts.entries.size() == originalConsts.entries.size() + 1);
	CHECK(apt.consts.entries.back().type == APT_CONST_REGISTER);
	CHECK(apt.consts.entries.back().raw == 1);
	REQUIRE(apt.frames[0].items.size() == 6);
	std::shared_ptr<const AptCodeBlock> block = apt.codeAt(apt.frames[0].items[5].codeOffset, &error);
	REQUIRE_MESSAGE(block, error);
	std::vector<std::uint8_t> ops;
	for (const AptInstruction &i : block->instructions)
	{
		ops.push_back(i.opcode);
	}
	const std::vector<std::uint8_t> want = { APT_OP_EA_PUSHSTRING, APT_OP_EA_PUSHBYTE, APT_OP_SETVARIABLE, APT_OP_EA_PUSHSTRING, APT_OP_GETVARIABLE,
		APT_OP_EA_PUSHBYTE, APT_OP_LESS2, APT_OP_BRANCHIFTRUE, APT_OP_EA_PUSHSTRING, APT_OP_EA_PUSHTRUE, APT_OP_SETVARIABLE, APT_OP_EA_PUSHSTRING,
		APT_OP_DEFINEFUNCTION, APT_OP_SETVARIABLE, APT_OP_PUSHDATA, APT_OP_EA_PUSHFLOAT, APT_OP_EA_PUSHLONG, APT_OP_EA_PUSHNULL,
		APT_OP_EA_PUSHUNDEFINED, APT_OP_EA_PUSHFALSE, APT_OP_POP, APT_OP_END };
	CHECK(ops == want);
	CHECK(block->instructions[1].intOperand == 7);
	CHECK(block->instructions[7].branchTarget == 11); // over `y = true`, to Push "f"
	CHECK(block->instructions[12].function->params.size() == 1);
	CHECK(block->instructions[12].function->params[0].name == "a");
	CHECK(block->instructions[12].function->body->instructions.size() == 3);
	CHECK(block->instructions[14].constants[0].type == APT_CONST_REGISTER);
	CHECK(block->instructions[15].floatOperand == 2.5f);
	CHECK(block->instructions[16].intOperand == -70000);
	checkStableAfterEdit(back);
}

TEST_CASE("apt-swf: two encodings of the same AVM1 normalize to the same lines")
{
	// ConstantPool "a" + Push constant8 0 / Push "a" inline; one Push of two values / two Pushes; a double 2.0 / a float 2.0
	const std::vector<std::uint8_t> pooled = { 0x88, 0x04, 0x00, 0x01, 0x00, 'a', 0x00, 0x96, 0x0B, 0x00, 0x08, 0x00, 0x06, 0x00, 0x00, 0x00, 0x40,
		0x00, 0x00, 0x00, 0x00, 0x1D, 0x00 };
	const std::vector<std::uint8_t> inlined = { 0x96, 0x03, 0x00, 0x00, 'a', 0x00, 0x96, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 0x1D, 0x00 };
	std::vector<std::string> a, b;
	std::string error;
	REQUIRE_MESSAGE(avm1Normalized(pooled, a, &error), error);
	REQUIRE_MESSAGE(avm1Normalized(inlined, b, &error), error);
	CHECK(a == b);
	const std::vector<std::string> want = { "push string a", "push float 40000000", "op 0x1D", "op 0x00" };
	CHECK(a == want);
}
