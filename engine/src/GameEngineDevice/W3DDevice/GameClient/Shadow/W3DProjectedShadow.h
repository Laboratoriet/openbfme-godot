// OpenBFME. GPL-3.0.
//
// The drawables' projected decal shadows (stop S-3304): the blob under an infantry unit, a hill troll or an optimized tree. Which W3DModelDraw shadow
// becomes a decal, with which texture, size, offset and turn, and when it is drawn. The ZH / BFME names are kept: W3DModelDraw's shadow setup,
// W3DShadowManager::addShadow, W3DProjectedShadowManager::addShadow and W3DProjectedShadowManager::renderShadows.
//
// TARGET FACTS (RotWK game.dat, caveat S-001; BFME2 decomp W3DShadowManagerAddShadow.cpp, W3DProjectedShadow.cpp, W3DProjectedShadowRenderShadows.cpp,
// W3DProjectedShadowManagerFlushDecals.cpp; ZH W3DProjectedShadow.cpp addShadow / renderShadows as the donor shape):
// - W3DModelDraw's shadow setup (RW 0x4C4ED5 .. 0x4C5175): nothing with ShadowForceDisable (the module's + 0x12B). A model condition state whose shadow
//   record has a nonzero type gives that record, and the shadow turns with the drawable (+ 0x30 = 1, RW 0x4C4F53); otherwise the object's own fields
//   (ThingTemplate, field table RW 0xDA3DF8: Shadow + 0x5F2, ShadowTexture + 0x90, ShadowSizeX / Y + 0x4F8 / + 0x4FC, ShadowOffsetX / Y + 0x500 / + 0x504,
//   ShadowMaxHeight + 0x514, 20 by default (RW 0x74015E), ShadowOverrideLODVisibility + 0x5FD), turning when ShadowIsRotatingWithObject (+ 0x5FF, true by
//   default, RW 0x740172). All 442 retail SHADOW_DECAL rows are object fields.
// - W3DShadowManager::addShadow (RW 0x49A2EB): SHADOW_VOLUME_OR_DECAL (0x4000) is SHADOW_VOLUME (0x2) with GlobalData UseShadowVolumes (+ 0x60), else
//   SHADOW_DECAL (0x1); SHADOW_VOLUME_NEW_OR_DECAL (0x8000) is SHADOW_VOLUME_NEW (0x4) or SHADOW_DECAL. Exactly 0x1, 0x20, 0x40, 0x400, 0x800, 0x1000 and
//   0x10000 go to the projected manager; the volumes go to the volume managers; any other value (bits combined) makes no shadow.
// - W3DProjectedShadowManager::addShadow (RW 0x50BF6A .. 0x50C0B3): no shadow unless GlobalData UseShadowDecals (+ 0x61, RW 0x50BF7B) or the record's
//   OverrideLODVisibility; the texture "shadow" when the name has at most one character (RW 0x50BFA6), with ".tga" appended (RW 0x50B67B); a zero
//   ShadowSizeX or ShadowSizeY takes the render object's bounds (2 x, -2 y, RW 0x50C039 / 0x50C059); the offsets negated (RW 0x50C07E / 0x50C083; the
//   projection adds them to its 0.5, DecalShadowCentre). UseShadowDecals is the static LOD's (GameLODManager: ShadowLOD Low and Medium).
// - setOpacity / setColor (RW 0x73228B / 0x73232B) change the diffuse of the alpha types (mask 0x1420) and the additive types (0x10840) only, so a
//   SHADOW_DECAL keeps the base diffuse 0xFFFFFFFF (BFME2 decomp Rva000EFA4EBase.cpp); flushDecals draws it with ShaderClass 0x111853 (RW 0x509A1F,
//   constant at RW 0xD9B2F4): ZERO / SRC_COLOR, the surface multiplied by texel x white. The alpha and additive types take ShadowOpacityPeak (RW 0x4B1BC6:
//   setOpacity(Peak) for the types that are not dynamic).
// - renderShadows (RW 0x50D92C): a shadow is skipped while it is not enabled (+ 4: the drawable hidden, RW 0x4B66F8, or the module's + 0x4B: contained
//   without ShowShadowWhileContained, or an exactly-SHADOW_DECAL shadow of a dead object, RW 0x4C781E .. 0x4C7888) or while it is invisible (+ 5: the
//   drawable fully obscured by the shroud, RW 0x4B675E).
// - the decal's terrain part is drawn only while the drawable stands less than ShadowMaxHeight above the floor (RW 0x50CDE4 .. 0x50CDF9); no retail
//   SHADOW_DECAL row sets ShadowMaxHeight, so MarkRaisedSelectionDecals' 20 is each decal's value.
// INFERENCE / not ported (stop S-3304, docs/STOPS.md): a decal whose size comes from the render object's bounds is not drawn (counted:
// ShadowDecalCounts::boundsSized); the contained test is the device's (Drawable::presentedLook hides what a container hides; a visible horde member keeps
// its shadow: the container's vslot 0x2C is not identified); SHADOW_MERGE_DECAL and RotWK's SHADOW_SUBTRACT_DECAL_DYNAMIC (0x10000) drawable shadows and
// the _DYNAMIC types' opacity fade are not drawn / run; UseShadowDecals is read every frame, retail reads it when the shadow is made.

#pragma once

#include "GameClient/SelectionDecals.h"

#include <cstddef>
#include <string>
#include <vector>

class DrawableManager;
class ThingTemplate;
struct LogicSnapshot;
struct ModelConditionInfo;
class W3DModelDrawModuleData;

namespace W3DProjectedShadow
{
// RW 0xD99EB0's bits (W3DModelDrawNameLists.inc kShadowTypeNames)
enum ShadowType : int
{
	SHADOW_DECAL = 0x1,
	SHADOW_VOLUME = 0x2,
	SHADOW_VOLUME_NEW = 0x4,
	SHADOW_ALPHA_DECAL = 0x20,
	SHADOW_ADDITIVE_DECAL = 0x40,
	SHADOW_ALPHA_DECAL_DYNAMIC = 0x400,
	SHADOW_ADDITIVE_DECAL_DYNAMIC = 0x800,
	SHADOW_MERGE_DECAL = 0x1000,
	SHADOW_VOLUME_OR_DECAL = 0x4000,
	SHADOW_VOLUME_NEW_OR_DECAL = 0x8000,
	SHADOW_SUBTRACT_DECAL_DYNAMIC = 0x10000
};

// TheGlobalData's two flags the static LOD level sets (GameLODManager StaticLODState: + 0x61 / + 0x60)
struct ShadowDecalLOD
{
	bool useShadowDecals = false;
	bool useShadowVolumes = false;
	bool operator==(const ShadowDecalLOD &o) const { return useShadowDecals == o.useShadowDecals && useShadowVolumes == o.useShadowVolumes; }
};

// the shadow record a draw module's shadow is made from (W3DModelDraw's shadow setup)
struct ShadowRecord
{
	int type = 0;
	std::string texture;
	float sizeX = 0.0f, sizeY = 0.0f, offsetX = 0.0f, offsetY = 0.0f;
	float maxHeight = 20.0f; ///< + 0x20 of the record (ShadowTypeInfo's constructor, RW 0x478DC0; the object's default RW 0x74015E)
	bool overrideLODVisibility = false;
	bool rotates = true;     ///< a state's record always; the object's ShadowIsRotatingWithObject
	unsigned opacityPeak = 0xFF;
	bool fromState = false;
};

// W3DModelDraw's shadow setup: false when the module makes no shadow (ShadowForceDisable, or no type)
bool ModelDrawShadowRecord(const ThingTemplate *object, const W3DModelDrawModuleData *module, const ModelConditionInfo *state, ShadowRecord &out);
// W3DShadowManager::addShadow: the type the projected manager gets for `type`, 0 when it is no projected shadow
int ProjectedShadowType(int type, const ShadowDecalLOD &lod);
// W3DProjectedShadowManager::addShadow's gate (RW 0x50BF7B)
bool ProjectedShadowCreated(const ShadowRecord &record, const ShadowDecalLOD &lod);
// the texture file a record's ShadowTexture names (RW 0x50BFA6 / 0x50B67B)
std::string ProjectedShadowTextureFile(const std::string &name);
// the decal of a projected shadow of `projectedType` for a drawable at `p` turned `orientation`; false (nothing in `out`) when the type is one the port
// does not draw or the size would come from the bounds (`boundsSized` set then)
bool ProjectedShadowDecal(const ShadowRecord &record, int projectedType, const Coord3D &p, float orientation, SelectionDecal &out, bool &boundsSized);

struct ShadowDecalCounts
{
	size_t shadows = 0;     ///< projected shadows made (after the gate)
	size_t drawn = 0;       ///< decals in the list
	size_t skipped = 0;     ///< renderShadows' skips: hidden, fully obscured, a dead object's SHADOW_DECAL
	size_t boundsSized = 0; ///< not drawn: the size is the render object's bounds (S-3304)
	size_t otherType = 0;   ///< not drawn: SHADOW_MERGE_DECAL or SHADOW_SUBTRACT_DECAL_DYNAMIC (S-3304)
};

// every drawable's projected decal shadows (each W3DModelDraw module that shows, in the drawables' order, appended to `out`); `presented` / `shroudDrawn`:
// what the device draws (Drawable::presentedLook)
void BuildDrawableShadowDecals(const DrawableManager &drawables, const LogicSnapshot *presented, bool shroudDrawn, const ShadowDecalLOD &lod,
	std::vector<SelectionDecal> &out, ShadowDecalCounts &counts);
} // namespace W3DProjectedShadow
