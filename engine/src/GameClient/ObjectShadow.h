// OpenBFME. GPL-3.0.
#pragma once

#include "Common/Thing/ThingTemplate.h"
#include "GameEngineDevice/W3DDevice/GameClient/Drawable/Draw/W3DModelDraw.h"

namespace ObjectShadow
{
// RW 0xD99EB0's shadow bits (W3DModelDrawNameLists.inc kShadowTypeNames): the volume geometries cast a Godot shadow map (S-3304).
// W3DShadowManager::addShadow (RW 0x49A2EB; BFME2 decomp W3DShadowManagerAddShadow.cpp) sends SHADOW_VOLUME (2) and the three
// SHADOW_VOLUME_NON_SELF_1 / _2 / _3 (0x80 / 0x100 / 0x200) to the volumetric manager (RW 0x4F24A8), SHADOW_VOLUME_NEW (4) to its
// V2 twin, and the two *_OR_DECAL forms to one of those while UseShadowVolumes is set. The NON_SELF types are volumes like
// SHADOW_VOLUME: their (type >> 7) & 7 only picks the stencil group the volume is drawn with (D3DRS_STENCILREF / STENCILMASK,
// RW 0x4F1912; by the name, so that it does not shadow itself). The Godot map has no such groups and also self-shadows those
// casters (S-3304). SHADOW_DECAL is a projected blob texture in retail, not a silhouette, so it casts none here; it and the
// projections remain S-3304.
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
}
