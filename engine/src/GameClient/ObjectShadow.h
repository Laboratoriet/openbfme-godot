// OpenBFME. GPL-3.0.
#pragma once

#include "Common/Thing/ThingTemplate.h"
#include "GameEngineDevice/W3DDevice/GameClient/Drawable/Draw/W3DDrawModules.h"
#include "GameEngineDevice/W3DDevice/GameClient/Drawable/Draw/W3DModelDraw.h"

namespace ObjectShadow
{
// RW 0xD99EB0's shadow bits (W3DModelDrawNameLists.inc kShadowTypeNames): the volume geometries cast a Godot shadow map (S-3304).
// W3DShadowManager::addShadow (RW 0x49A2EB; BFME2 decomp W3DShadowManagerAddShadow.cpp) sends SHADOW_VOLUME (2) and the three
// SHADOW_VOLUME_NON_SELF_1 / _2 / _3 (0x80 / 0x100 / 0x200) to the volumetric manager (RW 0x4F24A8), SHADOW_VOLUME_NEW (4) to its
// V2 twin, and the two *_OR_DECAL forms to one of those while UseShadowVolumes is set. The NON_SELF types are volumes like
// SHADOW_VOLUME: their (type >> 7) & 7 only picks the stencil group the volume is drawn with (D3DRS_STENCILREF / STENCILMASK,
// RW 0x4F1912; by the name, so that it does not shadow itself). The Godot map has no such groups and also self-shadows those
// casters (S-3304). SHADOW_DECAL is a projected blob texture in retail, not a silhouette, so at Medium it casts none here:
// GameEngineDevice/W3DDevice/GameClient/Shadow/W3DProjectedShadow.h draws it (ShadowLOD Low / Medium); the projections remain S-3304.
// At High and UltraHigh retail draws a real shadow map instead, whose casters do not depend on these bits: see mapCaster below.
constexpr int MapMask = (1 << 1) | (1 << 2) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 14) | (1 << 15);

inline bool castsMap(const ThingTemplate *object, const W3DModelDrawModuleData *module, const ModelConditionInfo *state)
{
	if (module && module->m_shadowForceDisable) return false;
	if (state && state->hasShadow) return (state->shadow.type & MapMask) != 0;
	if (!object) return false;
	const FieldValue *field = object->findField("Shadow");
	const long long *bits = field ? std::get_if<long long>(field) : nullptr;
	return bits && (*bits & MapMask) != 0;
}

// The casters of RotWK's own shadow map, drawn while the static level's UseShadowMapping is set (GlobalData + 0x62; gamelod.ini
// High and UltraHigh, ShadowLOD >= 3 in a custom level; the level then clears UseShadowVolumes and UseShadowDecals, RW 0x601C62).
// W3DShadowMapManager::UpdateShadowMap (RW 0x47D5C9; BFME2 decomp W3DShadowMapManagerUpdateShadowMap.cpp) renders the whole 3D
// scene into the map with WW3D::IsCurrentlyRenderingShadowMap set (RW 0xDD1E44). Nothing on that path reads a drawable's Shadow
// type or ShadowForceDisable (Visibility_Check RW 0x470B83, Customized_Render RW 0x46FE84, Flush RW 0x470F44, renderOneObject
// RW 0x46F48E): a mesh casts when its FX material has a _CreateShadowMap technique (the shadow method's Begin, RW 0x47B1BB;
// fxshaderasset.cpp: technique 0), as DefaultW3D.fx has and the High levels' classic materials are converted to
// (ShaderMaterialReplacement). So every drawn model casts, the SHADOW_DECAL infantry, cavalry and heroes included:
// - a W3DModelDraw drawable (the scene's render objects);
// - a W3DPropDraw prop: the terrain systems' render (BFME2 decomp FlatHeightMap.cpp 0x000E2FBD) skips two blocks while the
//   flag is set (RW 0x4E2E7D, 0x4E30D8) but calls W3DPropBuffer::drawProps after both (RW 0x4E3304), which renders each
//   prop's render object;
// - not a floor: W3DFloorBuffer::drawFloors (RW 0x4E2F6C) is inside the first skipped block, so floors never enter the map;
// - a tree keeps castsMap: W3DTreeBuffer's draw path in the shadow pass was not traced.
// Not ported: a surface the classic conversion refuses stays fixed-function in retail and casts nothing (MeshClass::Render
// returns while the flag is set, RW 0x54B775); here the whole model casts (S-3304).
inline bool mapCaster(int drawKind)
{
	return drawKind == W3D_DRAWKIND_MODEL || drawKind == W3D_DRAWKIND_PROP;
}

// Whether an instance is drawn into the Godot shadow map: the volume stand-in (castsMap, the Medium levels' stencil volumes, held
// by the caller for non-floor draws) or, while the level uses shadow mapping, retail's map caster set above.
inline bool drawsIntoMap(bool castsVolume, bool isMapCaster, bool useShadowMapping)
{
	return castsVolume || (useShadowMapping && isMapCaster);
}
}
