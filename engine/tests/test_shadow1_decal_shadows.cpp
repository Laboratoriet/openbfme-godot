// OpenBFME tests of S-3304's decal shadows: the blob under an infantry unit or a hill troll (W3DModelDraw Shadow = SHADOW_DECAL). Which record a draw
// module's shadow comes from, how W3DShadowManager::addShadow routes the types, W3DProjectedShadowManager::addShadow's gate, texture and size, the decal
// it gives (GameEngineDevice/W3DDevice/GameClient/Shadow/W3DProjectedShadow.h), and how the shaders' grid multiplies the surface with it (ShaderClass
// 0x111853, ZERO / SRC_COLOR, RW 0x509A1F; EvaluateSelectionDecals is the shaders' arithmetic in C++). Synthetic INI and textures only. GPL-3.0.

#include "doctest.h"
#include "ObjectTestUtil.h"

#include "GameClient/SelectionDecals.h"
#include "GameEngineDevice/W3DDevice/GameClient/Drawable/Draw/W3DModelDraw.h"
#include "GameEngineDevice/W3DDevice/GameClient/Shadow/W3DProjectedShadow.h"

#include <fstream>
#include <sstream>
#include <string>
#include <vector>

using namespace objtest;
using namespace W3DProjectedShadow;

namespace
{
// the atlas: "blob" at x 0 (rgb 128 inside a disc of radius 24 / 64, white outside, no alpha: as ShadowI is a 24-bit white-bordered grey blob), "ring" at
// x 64 (alpha 255, rgb (0, 0, 255))
struct Atlas
{
	static constexpr int kW = 128, kH = 64;
	std::vector<std::uint8_t> px = std::vector<std::uint8_t>((size_t)kW * kH * 4, 0);
	Atlas()
	{
		for (int y = 0; y < 64; ++y)
		{
			for (int x = 0; x < 64; ++x)
			{
				const float dx = (float)x + 0.5f - 32.0f, dy = (float)y + 0.5f - 32.0f;
				const bool inside = dx * dx + dy * dy <= 24.0f * 24.0f;
				std::uint8_t *b = &px[((size_t)y * kW + (size_t)x) * 4];
				b[0] = b[1] = b[2] = inside ? 128 : 255;
				b[3] = 255;
				std::uint8_t *r = &px[((size_t)y * kW + (size_t)(64 + x)) * 4];
				r[0] = 0;
				r[1] = 0;
				r[2] = 255;
				r[3] = 255;
			}
		}
	}
	DecalImage image() const { return { kW, kH, px.data() }; }
	static bool rect(const std::string &name, MergeDecalAtlasRect &r)
	{
		const int k = name == "blob" ? 0 : name == "ring" ? 1 : -1;
		if (k < 0)
		{
			return false;
		}
		r = { k * 64, 0, 64, 64 };
		return true;
	}
};

SelectionDecal blob(float x, float y, float z = 0.0f)
{
	SelectionDecal d;
	d.position = { x, y, z };
	d.size = 20.0f;
	d.texture = "blob";
	d.style = SHADOW_DECAL;
	d.color = 0xFFFFFFFFu;
	return d;
}

int at(const MergeDecalGrid &g, float x, float y, float z, DecalReceiver r, std::uint8_t surface, bool *drawn = nullptr)
{
	static const Atlas atlas;
	const std::uint8_t s[3] = { surface, surface, surface };
	std::uint8_t out[3] = { 0, 0, 0 };
	const bool d = EvaluateSelectionDecals(g, atlas.image(), x, y, z, r, s, out);
	if (drawn)
	{
		*drawn = d;
	}
	return out[0];
}

SelectionDecalSettings settings()
{
	SelectionDecalSettings s;
	s.showSelectedUnitMarker = true;
	return s;
}
} // namespace

TEST_CASE("shadow1: a draw module's shadow is its condition state's record, else the object's fields with their defaults; ShadowForceDisable makes none")
{
	World w;
	REQUIRE(w.load("Object Troll\n Shadow = SHADOW_DECAL\n ShadowTexture = ShadowI\n ShadowSizeX = 21\n ShadowSizeY = 22\n ShadowOffsetX = 3\n"
				   " ShadowOffsetY = -4\nEnd\n"
				   "Object Still\n Shadow = SHADOW_DECAL\n ShadowSizeX = 10\n ShadowSizeY = 10\n ShadowIsRotatingWithObject = No\n ShadowMaxHeight = 50\n"
				   " ShadowOverrideLODVisibility = Yes\nEnd\n"
				   "Object Plain\nEnd\n")
			  .empty());
	ShadowRecord r;
	// the object's fields (RW 0x4C4ED5 .. 0x4C5175 without a state record): ShadowMaxHeight 20 (RW 0x74015E) and turning (RW 0x740172) by default
	REQUIRE(ModelDrawShadowRecord(w.get("Troll"), nullptr, nullptr, r));
	CHECK(r.type == SHADOW_DECAL);
	CHECK(r.texture == "ShadowI");
	CHECK(r.sizeX == 21.0f);
	CHECK(r.sizeY == 22.0f);
	CHECK(r.offsetX == 3.0f);
	CHECK(r.offsetY == -4.0f);
	CHECK(r.maxHeight == 20.0f);
	CHECK(r.rotates);
	CHECK_FALSE(r.overrideLODVisibility);
	CHECK_FALSE(r.fromState);
	REQUIRE(ModelDrawShadowRecord(w.get("Still"), nullptr, nullptr, r));
	CHECK_FALSE(r.rotates);
	CHECK(r.maxHeight == 50.0f);
	CHECK(r.overrideLODVisibility);
	CHECK(r.texture.empty());
	CHECK_FALSE(ModelDrawShadowRecord(w.get("Plain"), nullptr, nullptr, r));
	CHECK_FALSE(ModelDrawShadowRecord(nullptr, nullptr, nullptr, r));
	// a state's record of a nonzero type wins and always turns (+ 0x30 = 1, RW 0x4C4F53); one of type 0 leaves the object's
	ModelConditionInfo state;
	state.hasShadow = true;
	state.shadow.type = SHADOW_ALPHA_DECAL;
	state.shadow.texture = "ring";
	state.shadow.sizeX = 40.0f;
	state.shadow.sizeY = 40.0f;
	state.shadowOpacityPeak = 0x80;
	REQUIRE(ModelDrawShadowRecord(w.get("Still"), nullptr, &state, r));
	CHECK(r.type == SHADOW_ALPHA_DECAL);
	CHECK(r.texture == "ring");
	CHECK(r.rotates);
	CHECK(r.fromState);
	CHECK(r.opacityPeak == 0x80u);
	CHECK(r.maxHeight == 20.0f); // the record's constructor (RW 0x478DC0)
	state.shadow.type = 0;
	REQUIRE(ModelDrawShadowRecord(w.get("Troll"), nullptr, &state, r));
	CHECK(r.type == SHADOW_DECAL);
	CHECK_FALSE(r.fromState);
	W3DModelDrawModuleData module;
	module.m_shadowForceDisable = true;
	CHECK_FALSE(ModelDrawShadowRecord(w.get("Troll"), &module, nullptr, r));
	CHECK(ModelShadowInfo().maxHeight == 20.0f);
}

TEST_CASE("shadow1: W3DShadowManager::addShadow sends the decal types to the projected manager and makes the *_OR_DECAL types decals without volumes")
{
	const ShadowDecalLOD low{ true, false }, medium{ true, true }, high{ false, false };
	for (int t : { 0x1, 0x20, 0x40, 0x400, 0x800, 0x1000, 0x10000 })
	{
		CHECK(ProjectedShadowType(t, low) == t);
		CHECK(ProjectedShadowType(t, high) == t);
	}
	// RW 0x49A2EB: 0x4000 -> 2 with UseShadowVolumes, else 1; 0x8000 -> 4, else 1
	CHECK(ProjectedShadowType(SHADOW_VOLUME_OR_DECAL, low) == SHADOW_DECAL);
	CHECK(ProjectedShadowType(SHADOW_VOLUME_NEW_OR_DECAL, high) == SHADOW_DECAL);
	CHECK(ProjectedShadowType(SHADOW_VOLUME_OR_DECAL, medium) == 0);
	CHECK(ProjectedShadowType(SHADOW_VOLUME_NEW_OR_DECAL, medium) == 0);
	// the volumes and the projections are not decals; bits combined make no shadow
	for (int t : { 0x2, 0x4, 0x8, 0x10, 0x80, 0x100, 0x200, 0x2000, 0x21, 0x3 })
	{
		CHECK(ProjectedShadowType(t, low) == 0);
	}
	// the gate (RW 0x50BF7B): UseShadowDecals or the record's OverrideLODVisibility
	ShadowRecord r;
	CHECK(ProjectedShadowCreated(r, low));
	CHECK_FALSE(ProjectedShadowCreated(r, high));
	r.overrideLODVisibility = true;
	CHECK(ProjectedShadowCreated(r, high));
	// the texture (RW 0x50BFA6, RW 0x50B67B)
	CHECK(ProjectedShadowTextureFile("ShadowI") == "ShadowI.tga");
	CHECK(ProjectedShadowTextureFile("") == "shadow.tga");
	CHECK(ProjectedShadowTextureFile("x") == "shadow.tga");
	CHECK(ProjectedShadowTextureFile("ab") == "ab.tga");
}

TEST_CASE("shadow1: the decal of a SHADOW_DECAL is white, sized by ShadowSizeX / Y, offset and turned with the drawable; a bounds-sized one is not drawn")
{
	ShadowRecord r;
	r.type = SHADOW_DECAL;
	r.texture = "ShadowI";
	r.sizeX = 21.0f;
	r.sizeY = 21.0f;
	SelectionDecal d;
	bool bounds = true;
	REQUIRE(ProjectedShadowDecal(r, SHADOW_DECAL, Coord3D{ 100.0f, 200.0f, 5.0f }, 0.5f, d, bounds));
	CHECK_FALSE(bounds);
	CHECK(d.texture == "ShadowI.tga");
	CHECK(d.style == 0x1u);
	CHECK(d.color == 0xFFFFFFFFu); // the base diffuse (setOpacity / setColor leave type 1 alone, RW 0x73228B / 0x73232B)
	CHECK(d.size == 21.0f);
	CHECK(d.sizeY == 21.0f);
	CHECK(d.angle == 0.5f);
	CHECK(d.position.x == 100.0f);
	CHECK(d.position.y == 200.0f);
	CHECK(d.drawZ == 5.0f);
	// the offsets along the turned axes (DecalShadowCentre: addShadow negates them, RW 0x50C07E / 0x50C083)
	r.offsetX = 10.0f;
	r.rotates = false;
	REQUIRE(ProjectedShadowDecal(r, SHADOW_DECAL, Coord3D{ 100.0f, 200.0f, 5.0f }, 0.5f, d, bounds));
	CHECK(d.angle == 0.0f);
	CHECK(d.position.x == 110.0f);
	CHECK(d.position.y == 200.0f);
	// an alpha type takes ShadowOpacityPeak (RW 0x4B1BC6)
	r.opacityPeak = 0x40;
	REQUIRE(ProjectedShadowDecal(r, SHADOW_ALPHA_DECAL, Coord3D{ 0.0f, 0.0f, 0.0f }, 0.0f, d, bounds));
	CHECK(d.color == 0x40FFFFFFu);
	// the render object's bounds (RW 0x50C039 / 0x50C059) are not ported: no decal, counted
	r.sizeY = 0.0f;
	CHECK_FALSE(ProjectedShadowDecal(r, SHADOW_DECAL, Coord3D{ 0.0f, 0.0f, 0.0f }, 0.0f, d, bounds));
	CHECK(bounds);
	// SHADOW_MERGE_DECAL and SHADOW_SUBTRACT_DECAL_DYNAMIC drawable shadows are not drawn
	r.sizeY = 21.0f;
	CHECK_FALSE(ProjectedShadowDecal(r, SHADOW_MERGE_DECAL, Coord3D{ 0.0f, 0.0f, 0.0f }, 0.0f, d, bounds));
	CHECK_FALSE(ProjectedShadowDecal(r, SHADOW_SUBTRACT_DECAL_DYNAMIC, Coord3D{ 0.0f, 0.0f, 0.0f }, 0.0f, d, bounds));
	CHECK_FALSE(bounds);
}

TEST_CASE("shadow1: a SHADOW_DECAL blob in the shaders' grid multiplies the surface by its texel (ZERO / SRC_COLOR), on the terrain and a wall top")
{
	MergeDecalGrid g;
	std::string err;
	REQUIRE_MESSAGE(BuildMergeDecalGrid({ blob(0, 0) }, &Atlas::rect, settings(), g, &err), err);
	CHECK(err.empty());
	CHECK(g.decals == 0);
	CHECK(g.alphaDecals == 1);
	CHECK(SelectionDecalShaderMode(g) == 4);
	CHECK(g.texels[15] == -5.0f); // rec3.w: a blob that may draw on a wall top too
	bool drawn = false;
	// the centre: 200 x 128 / 255 = 100.4; the white border keeps the surface
	CHECK(at(g, 0.0f, 0.0f, 0.0f, DecalReceiver::Terrain, 200, &drawn) == 100);
	CHECK(drawn);
	CHECK(at(g, 9.0f, 0.0f, 0.0f, DecalReceiver::Terrain, 200) == 200);
	CHECK(at(g, 30.0f, 0.0f, 0.0f, DecalReceiver::Terrain, 200, &drawn) == 200);
	CHECK_FALSE(drawn);
	// a wall top within 20 of the decal's height takes it, one 25 above does not (kSelectionDecalMaxHeight, RW 0x50CDE4)
	CHECK(at(g, 0.0f, 0.0f, 15.0f, DecalReceiver::Wall, 200) == 100);
	CHECK(at(g, 0.0f, 0.0f, 25.0f, DecalReceiver::Wall, 200) == 200);
	// a terrain-only blob (-4) draws on no wall
	SelectionDecal t = blob(0, 0);
	t.terrainOnly = true;
	REQUIRE(BuildMergeDecalGrid({ t }, &Atlas::rect, settings(), g, &err));
	CHECK(g.texels[15] == -4.0f);
	CHECK(at(g, 0.0f, 0.0f, 0.0f, DecalReceiver::Terrain, 200) == 100);
	CHECK(at(g, 0.0f, 0.0f, 5.0f, DecalReceiver::Wall, 200) == 200);
	// two blobs over one point multiply twice: 200 x (128 / 255)^2 = 50.4
	REQUIRE(BuildMergeDecalGrid({ blob(0, 0), blob(2, 0) }, &Atlas::rect, settings(), g, &err));
	CHECK(at(g, 1.0f, 0.0f, 0.0f, DecalReceiver::Terrain, 200) == 50);
	// a raised blob (the drawable 20 or more above the floor: MarkRaisedSelectionDecals) has no terrain part
	std::vector<SelectionDecal> high = { blob(0, 0, 30.0f) };
	CHECK(MarkRaisedSelectionDecals(high, [](float, float) { return 0.0f; }));
	CHECK(high[0].raised);
	REQUIRE(BuildMergeDecalGrid(high, &Atlas::rect, settings(), g, &err));
	CHECK(at(g, 0.0f, 0.0f, 0.0f, DecalReceiver::Terrain, 200) == 200);
	CHECK(at(g, 0.0f, 0.0f, 30.0f, DecalReceiver::Wall, 200) == 100);
}

TEST_CASE("shadow1: the decal atlas packs a blob's texture (MergeDecalAtlas::update)")
{
	const Atlas atlas;
	MergeDecalAtlas pack;
	std::vector<std::string> errors;
	std::vector<std::string> asked;
	REQUIRE(pack.update({ blob(0, 0) }, settings(), [&](const std::string &name) {
		asked.push_back(name);
		DecalImage img;
		if (name == "blob")
		{
			img = { 64, 64, atlas.px.data() }; // the left 64 of each 128-texel row: only the size and that the pixels exist matter here
		}
		return img;
	}, errors));
	CHECK(errors.empty());
	// a SHADOW_DECAL's texture is asked for (S-3304): once to see that it exists, once to pack it
	CHECK(asked == std::vector<std::string>{ "blob", "blob" });
	CHECK(pack.textures() == 1u);
	MergeDecalAtlasRect r;
	CHECK(pack.rect("blob", r));
	CHECK(r.w == 64);
	CHECK(r.h == 64);
}

TEST_CASE("shadow1: the drawables' blobs come before the selection's alpha decals in the list, so a hero's ring is blended over the darkened ground")
{
	SelectionDecal ring;
	ring.position = { 0.0f, 0.0f, 0.0f };
	ring.size = 40.0f;
	ring.texture = "ring";
	ring.style = 0x20u;
	ring.color = 0x80FFFFFFu; // half opacity
	MergeDecalGrid g;
	std::string err;
	REQUIRE_MESSAGE(BuildMergeDecalGrid({ blob(0, 0), ring }, &Atlas::rect, settings(), g, &err), err);
	CHECK(g.alphaDecals == 2);
	const Atlas atlas;
	const std::uint8_t s[3] = { 200, 200, 200 };
	std::uint8_t out[3] = { 0, 0, 0 };
	REQUIRE(EvaluateSelectionDecals(g, atlas.image(), 0.0f, 0.0f, 0.0f, DecalReceiver::Terrain, s, out));
	// (200 x 128 / 255) x (1 - 128 / 255) + (0, 0, 255) x 128 / 255: red 50, blue 178
	CHECK((int)out[0] == 50);
	CHECK((int)out[2] == 178);
}

TEST_CASE("shadow1: the shaders multiply as EvaluateSelectionDecals does (selection_decals.gdshaderinc, terrain.gdshader)")
{
	auto read = [](const char *path) {
		std::ifstream in(std::string(OPENBFME_DOCS_DIR) + "/../godot/shaders/" + path, std::ios::binary);
		REQUIRE(in.good());
		std::stringstream ss;
		ss << in.rdbuf();
		return ss.str();
	};
	const std::string inc = read("selection_decals.gdshaderinc");
	CHECK(inc.find("vec3 sel_alpha_at(vec3 w, bool wall, out vec3 keep)") != std::string::npos);
	CHECK(inc.find("bool multiply = rec3.w == -4.0 || rec3.w == -5.0;") != std::string::npos);
	CHECK(inc.find("cd *= src; // ZERO / SRC_COLOR") != std::string::npos);
	CHECK(inc.find("keep *= src;") != std::string::npos);
	const std::string terrain = read("terrain.gdshader");
	CHECK(terrain.find("vec3 sela = sel_alpha_at(vec3(v_sage_xy, 0.0), false, sela_keep);") != std::string::npos);
	CHECK(terrain.find("shadow_gamma = gamma * sela_keep;") != std::string::npos);
}
