// OpenBFME. GPL-3.0.
// See W3DProjectedShadow.h for the sources of every rule below.

#include "GameEngineDevice/W3DDevice/GameClient/Shadow/W3DProjectedShadow.h"

#include "Common/Thing/ThingTemplate.h"
#include "GameClient/Drawable.h"
#include "GameClient/DrawableManager.h"
#include "GameClient/LogicSnapshot.h"
#include "GameEngineDevice/W3DDevice/GameClient/Drawable/Draw/W3DModelDraw.h"
#include "GameEngineDevice/W3DDevice/GameClient/Drawable/Draw/W3DScriptedModelDraw.h"

namespace W3DProjectedShadow
{
namespace
{
float floatField(const ThingTemplate &t, const char *name, float dflt)
{
	const FieldValue *v = t.findField(name);
	const float *f = v ? std::get_if<float>(v) : nullptr;
	return f ? *f : dflt;
}

bool boolField(const ThingTemplate &t, const char *name, bool dflt)
{
	const FieldValue *v = t.findField(name);
	const bool *b = v ? std::get_if<bool>(v) : nullptr;
	return b ? *b : dflt;
}
} // namespace

bool ModelDrawShadowRecord(const ThingTemplate *object, const W3DModelDrawModuleData *module, const ModelConditionInfo *state, ShadowRecord &out)
{
	out = ShadowRecord();
	if (module && module->m_shadowForceDisable)
	{
		return false; // the module's + 0x12B (RW 0x4C4ED5)
	}
	if (state && state->hasShadow && state->shadow.type != 0)
	{
		// the condition state's record (state + 0xDC), turning with the drawable (+ 0x30 = 1, RW 0x4C4F53)
		const ModelShadowInfo &s = state->shadow;
		out.type = s.type;
		out.texture = s.texture;
		out.sizeX = s.sizeX;
		out.sizeY = s.sizeY;
		out.offsetX = s.offsetX;
		out.offsetY = s.offsetY;
		out.maxHeight = s.maxHeight;
		out.overrideLODVisibility = s.overrideLODVisibility;
		out.rotates = true;
		out.opacityPeak = state->shadowOpacityPeak;
		out.fromState = true;
		return true;
	}
	if (!object)
	{
		return false;
	}
	// the object's own fields (field table RW 0xDA3DF8)
	const FieldValue *bits = object->findField("Shadow");
	const long long *type = bits ? std::get_if<long long>(bits) : nullptr;
	if (!type || *type == 0)
	{
		return false;
	}
	out.type = (int)*type;
	if (const FieldValue *v = object->findField("ShadowTexture"))
	{
		if (const std::string *s = std::get_if<std::string>(v))
		{
			out.texture = *s;
		}
	}
	out.sizeX = floatField(*object, "ShadowSizeX", 0.0f);
	out.sizeY = floatField(*object, "ShadowSizeY", 0.0f);
	out.offsetX = floatField(*object, "ShadowOffsetX", 0.0f);
	out.offsetY = floatField(*object, "ShadowOffsetY", 0.0f);
	out.maxHeight = floatField(*object, "ShadowMaxHeight", 20.0f);                     // RW 0x74015E
	out.overrideLODVisibility = boolField(*object, "ShadowOverrideLODVisibility", false);
	out.rotates = boolField(*object, "ShadowIsRotatingWithObject", true);              // RW 0x740172
	if (const FieldValue *v = object->findField("ShadowOpacityPeak"))
	{
		if (const long long *p = std::get_if<long long>(v))
		{
			out.opacityPeak = (unsigned)*p;
		}
	}
	return true;
}

int ProjectedShadowType(int type, const ShadowDecalLOD &lod)
{
	// RW 0x49A2EB
	if (type == SHADOW_VOLUME_OR_DECAL)
	{
		type = lod.useShadowVolumes ? SHADOW_VOLUME : SHADOW_DECAL;
	}
	else if (type == SHADOW_VOLUME_NEW_OR_DECAL)
	{
		type = lod.useShadowVolumes ? SHADOW_VOLUME_NEW : SHADOW_DECAL;
	}
	switch (type)
	{
		case SHADOW_DECAL:
		case SHADOW_ALPHA_DECAL:
		case SHADOW_ADDITIVE_DECAL:
		case SHADOW_ALPHA_DECAL_DYNAMIC:
		case SHADOW_ADDITIVE_DECAL_DYNAMIC:
		case SHADOW_MERGE_DECAL:
		case SHADOW_SUBTRACT_DECAL_DYNAMIC:
			return type;
		default:
			return 0;
	}
}

bool ProjectedShadowCreated(const ShadowRecord &record, const ShadowDecalLOD &lod)
{
	return lod.useShadowDecals || record.overrideLODVisibility; // RW 0x50BF7B
}

std::string ProjectedShadowTextureFile(const std::string &name)
{
	return (name.size() <= 1 ? std::string("shadow") : name) + ".tga"; // RW 0x50BFA6, RW 0x50B67B
}

bool ProjectedShadowDecal(const ShadowRecord &record, int projectedType, const Coord3D &p, float orientation, SelectionDecal &out, bool &boundsSized)
{
	boundsSized = false;
	out = SelectionDecal();
	if (projectedType == SHADOW_MERGE_DECAL || projectedType == SHADOW_SUBTRACT_DECAL_DYNAMIC || projectedType == 0)
	{
		return false;
	}
	if (record.sizeX == 0.0f || record.sizeY == 0.0f)
	{
		boundsSized = true; // the render object's bounds (RW 0x50C039 / 0x50C059): not ported (S-3304)
		return false;
	}
	const float angle = record.rotates ? orientation : 0.0f;
	out.texture = ProjectedShadowTextureFile(record.texture);
	out.style = (std::uint32_t)projectedType;
	// SHADOW_DECAL keeps the base diffuse (white, opacity 0xFF); the alpha and additive types take ShadowOpacityPeak (RW 0x4B1BC6 -> RW 0x73228B)
	out.color = projectedType == SHADOW_DECAL ? 0xFFFFFFFFu : DecalShadowColor(record.opacityPeak);
	out.size = record.sizeX;
	out.sizeY = record.sizeY;
	out.angle = angle;
	out.position = DecalShadowCentre(p, record.offsetX, record.offsetY, angle);
	out.drawZ = p.z;
	return true;
}

void BuildDrawableShadowDecals(const DrawableManager &drawables, const LogicSnapshot *presented, bool shroudDrawn, const ShadowDecalLOD &lod,
	std::vector<SelectionDecal> &out, ShadowDecalCounts &counts)
{
	for (size_t id = 1; id < drawables.slotCount(); ++id)
	{
		const Drawable *d = drawables.find((DrawableID)id);
		if (!d)
		{
			continue;
		}
		// renderShadows' skips (RW 0x50D92C): + 4 clear (hidden: RW 0x4B66F8, the fade's hidden state; the device's hidden look takes the logic's
		// drawable-hidden flag, which a container sets, and stealth), + 5 set (fully obscured by the shroud, RW 0x4B675E: the fogged look)
		const Drawable::PresentedLook look = d->presentedLook(presented, shroudDrawn);
		const bool skip = look.hidden || look.fogLook || d->drawOpacity() <= 0.0f;
		bool dead = false;
		if (presented)
		{
			bool synced = false;
			const ObjectSnapshot *rec = d->syncedRecord(*presented, synced);
			if (!synced)
			{
				rec = presented->find(d->getObjectID());
			}
			dead = rec && rec->effectivelyDead;
		}
		for (const DrawEntry &e : d->entries())
		{
			if (e.kind != W3D_DRAWKIND_MODEL || !e.draw || e.moduleHidden || e.missingModel)
			{
				continue;
			}
			ShadowRecord r;
			if (!ModelDrawShadowRecord(d->getTemplate(), dynamic_cast<const W3DModelDrawModuleData *>(e.data), e.draw->currentModelState(), r))
			{
				continue;
			}
			const int type = ProjectedShadowType(r.type, lod);
			if (type == 0 || !ProjectedShadowCreated(r, lod))
			{
				continue;
			}
			++counts.shadows;
			// a dead object's exactly-SHADOW_DECAL shadow (RW 0x4C781E .. 0x4C7888: type 1 and Object + 0x458 bit 0)
			if (skip || (dead && r.type == SHADOW_DECAL))
			{
				++counts.skipped;
				continue;
			}
			SelectionDecal decal;
			bool bounds = false;
			if (!ProjectedShadowDecal(r, type, *d->getPosition(), d->getOrientation(), decal, bounds))
			{
				++(bounds ? counts.boundsSized : counts.otherType);
				continue;
			}
			decal.object = d->getObjectID();
			decal.drawable = (unsigned)id;
			out.push_back(std::move(decal));
			++counts.drawn;
		}
	}
}
} // namespace W3DProjectedShadow
