// OpenBFME. GPL-3.0.
//
// PortraitLayout (lane IOS-38, OpenBFME presentation, NOT retail): the portrait layout prototypes' specs. See PortraitLayout.h.

#include "GameClient/GUI/PortraitLayout.h"

#include <algorithm>
#include <cctype>

const PortraitLayout::Spec &PortraitLayout::spec(Id id)
{
	// the camera angles at the Duo's aspect (626 / 890 = 0.703): today 27.6 x 38.6 degrees (4:3's vertical angle kept); A 38.58 x 52.9 (the landscape
	// view turned upright: as much ground across as a 4:3 screen shows top to bottom); B 33 x 45.6; C 36 x 49.1. Bubbles 1.6: 35 pt at 1.25 -> 45 pt
	static const Spec kSpecs[Count] = {
		{ Today, "default", "Today", 1.0f, 0.0f, SideTopColumn, 1, 0.0f, false, 0.0f, false, 0.0f },
		// lane IOS-42: A's resource bar stays in the Palantir's band (resourcesTop false); its Palantir follows the HUD size (moreMapPalantir)
		{ MoreMap, "a", "More map", 1.25f, 0.0f, SideBottomBlock, 2, 52.0f, false, 0.0f, false, 38.58f, 0.0f },
		{ OneHand, "b", "One hand", 2.0f, 0.0f, SideBottomColumn, 1, 54.0f, false, 0.0f, false, 33.0f, 1.6f },
		{ Split, "c", "Split", 2.0f, 0.5f, SideBottomBlock, 2, 52.0f, true, 120.0f, true, 36.0f, 1.6f },
	};
	return kSpecs[id >= Today && id < Count ? id : Today];
}

float PortraitLayout::moreMapPalantir(float hudScale, float large)
{
	const float base = spec(MoreMap).palantir;
	const float t = std::clamp((hudScale - 1.0f) / (kMoreMapTopScale - 1.0f), 0.0f, 1.0f);
	return base + (std::max(large, base) - base) * t;
}

bool PortraitLayout::parse(const std::string &key, Id &id)
{
	std::string k = key;
	std::transform(k.begin(), k.end(), k.begin(), [](unsigned char c) { return (char)std::tolower(c); });
	if (k.empty() || k == "default" || k == "today")
	{
		id = Today;
		return true;
	}
	for (int i = MoreMap; i < Count; ++i)
	{
		if (k == spec((Id)i).key)
		{
			id = (Id)i;
			return true;
		}
	}
	return false;
}

AptMatrix PortraitLayout::place(float ax, float ay, float a, float d, float px, float py)
{
	AptMatrix m;
	m.a = a;
	m.d = d;
	m.tx = px - a * ax;
	m.ty = py - d * ay;
	return m;
}

float PortraitLayout::factorFor(float pt, float extentStage, float unitPx, float pointPx)
{
	if (extentStage <= 0.0f || unitPx <= 0.0f || pointPx <= 0.0f)
	{
		return 1.0f;
	}
	return pt * pointPx / (extentStage * unitPx);
}
