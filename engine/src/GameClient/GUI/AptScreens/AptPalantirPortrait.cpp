// OpenBFME. GPL-3.0.
//
// lane IOS-38 (OpenBFME presentation, a PROTOTYPE behind a developer switch, NOT retail): a portrait layout prototype's placement of the Palantir movie's
// clips. See GameClient/GUI/PortraitLayout.h for the three layouts and the rules they share.
//
// Palantir.apt's root is flat: the Palantir is ~16 sibling clips (measured on RotWK 2.01, stage units): PalantirBack (the dark disc pair, 6..379 x
// 517..762), PalantirFrame (the carved frame around both globes, 0..384 x 512..768), the minimap globe (RegionBackground, BigGlobeSwirlRender,
// RadarBackground 20..239 x 531..750, Radar, RadarPings, MoviePlayback) with PalantirButtons on its rim (the key, the powers, the flag), the command
// globe (CommandBackground 202..369 x 576..743, GlobeSwirlRender, EmptyGlobe, CommandUI with the portrait, CommandButtons' arc of six, its
// AutoAbilityOverlays), PalantirSpectralHighlight over both, ResourceBar (55..216 x 720..743: the money, the multiplier, the command points),
// HeroSelectUI (the hero buttons, 384..470 x 685..771) and the pieces placed on their own (SideCommandBar, SpellBookUI, planningModeUI, helpBox,
// ButtonFlashStage).
//
// Every placement is a uniform scale about an anchor plus a move (PortraitLayout::place), written into the clip's viewportTransform: in a portrait
// window the stage is stretched (x: width / 1024, y: height / 768 window pixels per unit), so a group drawn at factor k takes a = k across and
// d = k * (width / 1024) / (height / 768) down, which is round on the screen; the round-HUD rule (AptUniformHud) then has nothing to correct. The hit
// tests read the same matrices (AptCharacterInst::globalMatrix), the radar's square its clip's (InGameHud::radarSquare), so a press lands on what is drawn.

#include "GameClient/GUI/AptScreens/AptPalantir.h"
#include "GameClient/GUI/PortraitLayout.h"
#include "Libraries/Source/Apt/Apt.h"
#include "Libraries/Source/Apt/AptCharacterInst.h"
#include "Libraries/Source/Apt/AptFile.h"

#include <algorithm>
#include <cmath>
#include <set>

namespace
{
struct Box
{
	float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
	bool ok() const { return x1 >= x0 && y1 >= y0; }
	float w() const { return x1 - x0; }
	float h() const { return y1 - y0; }
	void add(float x, float y)
	{
		x0 = std::min(x0, x);
		y0 = std::min(y0, y);
		x1 = std::max(x1, x);
		y1 = std::max(y1, y);
	}
	void add(const Box &b)
	{
		if (b.ok())
		{
			add(b.x0, b.y0);
			add(b.x1, b.y1);
		}
	}
	Box through(const AptMatrix &m) const
	{
		Box b;
		if (ok())
		{
			float x, y;
			m.apply(x0, y0, x, y);
			b.add(x, y);
			m.apply(x1, y1, x, y);
			b.add(x, y);
		}
		return b;
	}
};

// the matrix from `c`'s own space to the root's (the root itself excluded): each level's present, viewport and movie matrices
AptMatrix chainToRoot(AptCharacterInst *c, const AptSpriteInst *root)
{
	AptMatrix m;
	for (AptCharacterInst *at = c; at && at != root; at = at->parent())
	{
		m = at->presentTransform.concat(at->viewportTransform.concat(at->matrix)).concat(m);
	}
	return m;
}

Box boxThrough(const AptCharacterInst *c, const AptMatrix &m)
{
	Box b;
	float x0, y0, x1, y1;
	if (!c || !c->contentBounds(x0, y0, x1, y1))
	{
		return b;
	}
	const float xs[4] = { x0, x1, x0, x1 }, ys[4] = { y0, y0, y1, y1 };
	for (int i = 0; i < 4; ++i)
	{
		float x, y;
		m.apply(xs[i], ys[i], x, y);
		b.add(x, y);
	}
	return b;
}

// the first text field under `c` (the resource bar's money)
const AptTextInst *firstText(const AptCharacterInst *c)
{
	if (!c)
	{
		return nullptr;
	}
	if (const AptTextInst *t = dynamic_cast<const AptTextInst *>(c))
	{
		return t;
	}
	if (const AptSpriteInst *s = dynamic_cast<const AptSpriteInst *>(c))
	{
		for (const AptCharacterInst *child : s->children())
		{
			if (const AptTextInst *t = firstText(child))
			{
				return t;
			}
		}
	}
	return nullptr;
}

float fontHeightOf(const AptTextInst *t)
{
	const AptCharacter *ch = t ? t->charRef().character : nullptr;
	return ch && ch->text ? ch->text->fontHeight : 0.0f;
}

// the root's children a prototype places on their own; every other child is the Palantir
bool ownPlace(const std::string &name)
{
	return name == "SideCommandBar" || name == "planningModeUI" || name == "helpBox" || name == "ButtonFlashStage" || name == "SpellBookUI";
}
// C: the minimap globe with the buttons on its rim, apart in the top-right corner
bool radarGlobe(const std::string &name)
{
	return name == "RegionBackground" || name == "BigGlobeSwirlRender" || name == "RadarBackground" || name == "Radar" || name == "RadarPings" ||
		name == "MoviePlayback";
}
// C: the frame and the back around both globes, and the highlight over both, have nothing to frame once the globes are apart
bool frameArt(const std::string &name)
{
	return name == "PalantirFrame" || name == "PalantirBack" || name == "PalantirSpectralHighlight";
}
const char *const kHiddenMark = "~"; // m_protoMoved: "~<name>" is a root child the prototype hid
} // namespace

bool AptPalantir::layoutPortraitPrototype(AptSpriteInst *root, int width, int height, const HudLayout &layout)
{
	m_portraitReport.clear();
	Apt &apt = windows().apt();
	auto releaseMoved = [&]() {
		for (const std::string &entry : m_protoMoved)
		{
			if (entry.rfind(kHiddenMark, 0) == 0)
			{
				if (AptCharacterInst *c = apt.resolvePath(root, entry.substr(1)))
				{
					c->visible = true;
				}
			}
		}
		m_protoMoved.clear();
	};
	if (m_bfme1 || !layout.portraitPrototype(width, height))
	{
		releaseMoved();
		m_protoSideColumns = 0;
		return false;
	}
	const PortraitLayout::Spec &spec = PortraitLayout::spec((PortraitLayout::Id)layout.portraitLayout);
	const float stageW = (float)root->timelineFile->width, stageH = (float)root->timelineFile->height;
	const float unitX = (float)width / stageW, unitY = (float)height / stageH; // window pixels per stage unit
	const float vs = unitX / unitY;                                           // a uniform factor's d per a
	const float ppt = layout.pointPx > 0.0f ? layout.pointPx : PortraitLayout::kDefaultPointPx;
	const float safeLeft = layout.safeInsets[0] / unitX, safeTop = layout.safeInsets[1] / unitY;
	const float safeRight = stageW - layout.safeInsets[2] / unitX, safeBottom = stageH - layout.safeInsets[3] / unitY;
	const float strip = safeTop + PortraitLayout::kToolbarPt * ppt / unitY; // the toolbar strip's bottom (stage y)
	const float safeW = safeRight - safeLeft;
	const float gapX = 8.0f * ppt / unitX, gapY = 8.0f * ppt / unitY; // an 8 pt margin
	auto px = [&](float stageUnits) { return stageUnits * unitX; };    // a horizontal stage extent in window pixels at factor 1
	m_portraitReport["layout"] = (float)spec.id;
	m_portraitReport["point_px"] = ppt;
	m_portraitReport["strip_bottom"] = strip * unitY;

	// ---- what the movie measures (its own matrices: every viewportTransform is ours) ----
	auto movieBox = [&](const std::string &name) { return boxThrough(apt.resolvePath(root, name), apt.resolvePath(root, name) ? apt.resolvePath(root, name)->matrix : AptMatrix()); };
	Box arcGlass; // one arc button's glass (the drawn circle a finger aims at)
	if (AptCharacterInst *glass = apt.resolvePath(root, "CommandButtons.glass0"))
	{
		arcGlass = boxThrough(glass, glass->matrix).through(glass->parent()->matrix); // in the root's units (CommandButtons is a root child)
	}
	// 4 % over 44 pt: the button's hit shape is a little inside its glass
	const float arcK = arcGlass.ok() ? PortraitLayout::factorFor(PortraitLayout::kTargetPt * 1.04f, std::max(arcGlass.w(), arcGlass.h()), unitX, ppt) : 1.0f;
	const AptTextInst *money = firstText(apt.resolvePath(root, "ResourceBar.Resources"));
	const float fontH = fontHeightOf(money);
	// the factor that draws the resource bar's digits as tall as 11 pt type's capitals (its font height, the digits' share of it, the text's own scale
	// inside the bar)
	float textK = 1.0f;
	if (money && fontH > 0.0f)
	{
		const AptMatrix inBar = chainToRoot(const_cast<AptTextInst *>(money), root);
		AptCharacterInst *bar = apt.resolvePath(root, "ResourceBar");
		const float own = bar && bar->viewportTransform.d != 0.0f ? std::fabs(inBar.d / bar->viewportTransform.d) : std::fabs(inBar.d);
		textK = PortraitLayout::kTextCapPt * ppt / (fontH * PortraitLayout::kResourceCapPerFont * own * vs * unitY);
	}
	m_portraitReport["arc_factor_44pt"] = arcK;
	m_portraitReport["text_factor_11pt"] = textK;

	// ---- the groups ----
	std::set<std::string> palantirSet, radarSet, hidden;
	for (AptCharacterInst *child : root->children())
	{
		const std::string &name = child->instName();
		if (ownPlace(name))
		{
			continue;
		}
		if (spec.radarApart && radarGlobe(name))
		{
			radarSet.insert(name);
		}
		else if (spec.radarApart && frameArt(name))
		{
			hidden.insert(name);
		}
		else if (!(spec.resourcesTop && name == "ResourceBar") && !(spec.radarApart && (name == "HeroSelectUI" || name == "PalantirButtons")))
		{
			palantirSet.insert(name);
		}
	}
	// hide (and remember) what C has no use for; show again what an earlier pass hid and this one keeps
	std::vector<std::string> moved;
	for (const std::string &entry : m_protoMoved)
	{
		if (entry.rfind(kHiddenMark, 0) == 0 && !hidden.count(entry.substr(1)))
		{
			if (AptCharacterInst *c = apt.resolvePath(root, entry.substr(1)))
			{
				c->visible = true;
			}
		}
	}
	for (const std::string &name : hidden)
	{
		if (AptCharacterInst *c = apt.resolvePath(root, name))
		{
			c->visible = false;
			c->viewportTransform = AptMatrix();
			moved.push_back(kHiddenMark + name);
		}
	}
	m_protoMoved = moved;
	auto placeAll = [&](const std::set<std::string> &names, const AptMatrix &m) {
		for (const std::string &name : names)
		{
			if (AptCharacterInst *c = apt.resolvePath(root, name))
			{
				c->viewportTransform = m;
			}
		}
	};
	auto unionOf = [&](const std::set<std::string> &names) {
		Box b;
		for (const std::string &name : names)
		{
			b.add(movieBox(name));
		}
		return b;
	};

	// ---- the Palantir (A, B: whole; C: the command globe) at the safe area's bottom ----
	const Box movie = unionOf(palantirSet);
	if (!movie.ok())
	{
		releaseMoved();
		return false;
	}
	float k = spec.palantir;
	if (spec.id == PortraitLayout::MoreMap)
	{
		k = PortraitLayout::moreMapPalantir(layout.scale, std::max(arcK, textK)); // lane IOS-42: A follows the HUD size
	}
	if (spec.id == PortraitLayout::OneHand || spec.id == PortraitLayout::Split)
	{
		k = std::max(k, arcK); // B and C: the arc's buttons at least 44 pt
	}
	if (spec.id == PortraitLayout::OneHand)
	{
		k = std::max(k, textK); // B: the resource bar stays in the frame's band, the whole Palantir as large as its text needs
	}
	// the anchor: A, B the stage's bottom-left corner (as today: the frame's rim reaches the stage's left edge); C the command globe's bottom centre
	const float anchorX = spec.palantirX <= 0.0f ? 0.0f : movie.x0 + movie.w() * spec.palantirX;
	const float reachW = spec.palantirX <= 0.0f ? movie.x1 : movie.w();
	if (reachW * k > safeW)
	{
		k = safeW / reachW; // never wider than the safe area
	}
	const float targetX = spec.palantirX <= 0.0f ? safeLeft : safeLeft + safeW * spec.palantirX;
	const float anchorY = spec.radarApart ? movie.y1 : stageH;
	const AptMatrix palantir = PortraitLayout::place(anchorX, anchorY, k, vs * k, targetX, safeBottom);
	placeAll(palantirSet, palantir);
	m_groupScale[(int)HudGroup::BottomLeft] = k;
	const Box placed = movie.through(palantir);
	m_portraitReport["palantir"] = k;
	m_portraitReport["palantir_top"] = placed.y0 * unitY;
	m_portraitReport["palantir_left"] = placed.x0 * unitX;
	m_portraitReport["palantir_right"] = placed.x1 * unitX;
	float hudTop = placed.y0;

	float statusBottom = strip; // A, C: the resource plate's bottom (C's globe buttons go under it)
	// ---- the resource bar: its digits as tall as 11 pt type's capitals ----
	if (AptCharacterInst *bar = apt.resolvePath(root, "ResourceBar"))
	{
		const Box rb = movieBox("ResourceBar");
		if (spec.resourcesTop)
		{
			// A, C: under the toolbar strip at the top-left (the status where a phone's games keep it)
			const float kr = std::max(textK, 1.0f);
			bar->viewportTransform = PortraitLayout::place(rb.x0, rb.y0, kr, vs * kr, safeLeft + gapX * 1.5f, strip + gapY * 1.5f);
			m_portraitReport["resources"] = kr;
			// its frame was PalantirFrame's bottom band: the device draws a plate under it (InGameHudNode, the game's dark and gold)
			const Box at = rb.through(bar->viewportTransform);
			m_portraitReport["resources_x0"] = (at.x0 - gapX * 0.5f) * unitX;
			m_portraitReport["resources_y0"] = (at.y0 - gapY * 0.5f) * unitY;
			m_portraitReport["resources_x1"] = (at.x1 + gapX * 0.5f) * unitX;
			m_portraitReport["resources_y1"] = (at.y1 + gapY * 0.5f) * unitY;
			statusBottom = at.y1 + gapY * 0.5f;
		}
		else
		{
			// B: in the frame's bottom band, with the Palantir (whose factor is at least textK); lane IOS-42, A: there too, at the Palantir's factor (the
			// band is the bar's frame: moved away, it left an empty slot)
			const float kr = spec.id == PortraitLayout::MoreMap ? k : std::max(k, textK);
			const float cx = (rb.x0 + rb.x1) * 0.5f, cy = (rb.y0 + rb.y1) * 0.5f;
			float wx, wy;
			palantir.apply(cx, cy, wx, wy);
			bar->viewportTransform = PortraitLayout::place(cx, cy, kr, vs * kr, std::max(wx, safeLeft + rb.w() * 0.5f * kr), wy);
			m_portraitReport["resources"] = kr;
		}
		// the digits' drawn height in points, and the type size whose capitals are that tall
		const float cap = fontH * PortraitLayout::kResourceCapPerFont * std::fabs(chainToRoot(const_cast<AptTextInst *>(money), root).d) * unitY / ppt;
		m_portraitReport["text_cap_pt"] = cap;
		m_portraitReport["text_pt"] = cap * PortraitLayout::kTextPt / PortraitLayout::kTextCapPt;
		m_portraitReport["font_height"] = fontH;
	}

	// ---- C: the minimap globe in the top-right corner, the hero buttons in the bottom-left ----
	float messagesTop = strip;
	if (spec.radarApart)
	{
		const Box globe = movieBox("RadarBackground");
		const Box all = unionOf(radarSet); // with the buttons on its rim
		if (globe.ok() && all.ok())
		{
			const float kr = spec.radarPt * ppt / px(globe.w());
			// the globe's top-right on the safe area's, under the strip
			const AptMatrix m = PortraitLayout::place(all.x1, all.y0, kr, vs * kr, safeRight - gapX, strip + gapY);
			placeAll(radarSet, m);
			const Box at = all.through(m);
			messagesTop = at.y1 + gapY;
			m_portraitReport["radar"] = kr;
			m_portraitReport["radar_bottom"] = at.y1 * unitY;
			// the key, the powers and the flag: a row at the top-left under the resource plate (the status and the menus in one corner, the map in the
			// other; under the globe they met the centred menus' title band), each at least 44 pt (on the globe's rim they were 20 pt)
			if (AptCharacterInst *buttons = apt.resolvePath(root, "PalantirButtons"))
			{
				const Box bb = movieBox("PalantirButtons");
				buttons->viewportTransform = AptMatrix();
				AptCharacterInst *options = apt.resolvePath(root, "PalantirButtons.Buttons.Options");
				const Box ob = options ? boxThrough(options, chainToRoot(options, root)) : Box();
				float kb = arcK;
				if (ob.ok())
				{
					kb = std::max(kb, PortraitLayout::factorFor(PortraitLayout::kTargetPt, std::min(ob.w(), ob.h() / vs), unitX, ppt));
				}
				buttons->viewportTransform = PortraitLayout::place(ob.ok() ? ob.x0 : bb.x0, bb.y0, kb, vs * kb, safeLeft + gapX * 1.5f, statusBottom + gapY); // the key's rim in line with the plate's edge
				m_portraitReport["globe_buttons"] = kb;
			}
		}
		if (AptCharacterInst *heroes = apt.resolvePath(root, "HeroSelectUI"))
		{
			const Box hb = movieBox("HeroSelectUI");
			const float kh = k;
			heroes->viewportTransform = PortraitLayout::place(hb.x0, hb.y1, kh, vs * kh, safeLeft + gapX, safeBottom);
		}
	}
	m_portraitReport["messages_top"] = messagesTop * unitY;

	// ---- the side bar ----
	float sideK = 1.25f * kSideBarBoost;
	if (spec.sideBarPt > 0.0f && m_sideCount > 1)
	{
		// the frames' pitch in root units (the bar's and ButtonSet's scale): the factor that makes it spec.sideBarPt points
		AptCharacterInst *f0 = apt.resolvePath(root, m_sideFramePath[0].substr(0, m_sideFramePath[0].rfind('.')));
		AptCharacterInst *f1 = apt.resolvePath(root, m_sideFramePath[1].substr(0, m_sideFramePath[1].rfind('.')));
		if (f0 && f1 && f0->parent() == f1->parent())
		{
			AptCharacterInst *set = f0->parent();
			AptCharacterInst *bar = set ? set->parent() : nullptr;
			const float unit = bar && set ? std::fabs(bar->matrix.d * set->matrix.d) : 1.0f;
			const float pitch = std::fabs(f1->matrix.ty - f0->matrix.ty) * unit;
			if (pitch > 0.0f)
			{
				sideK = spec.sideBarPt * ppt / (pitch * vs * unitY);
			}
		}
	}
	// the side bar's foot: the safe area's bottom, or (B) above the hero buttons, which stand at the Palantir's bottom-right
	float sideBottom = safeBottom;
	if (spec.sideBar == PortraitLayout::SideBottomColumn && palantirSet.count("HeroSelectUI"))
	{
		const Box hero = movieBox("HeroSelectUI").through(palantir);
		if (hero.ok())
		{
			sideBottom = hero.y0 - gapY;
		}
	}
	m_protoSideColumns = spec.sideBar == PortraitLayout::SideBottomColumn ? 1 : 0;
	if (!arrangeSideBar(root, spec.sideBar == PortraitLayout::SideTopColumn, vs, stageW, stageH, strip, sideBottom, sideK))
	{
		sideK = 1.0f;
	}
	m_groupScale[(int)HudGroup::BottomRight] = sideK;
	if (AptCharacterInst *side = apt.resolvePath(root, "SideCommandBar"))
	{
		side->viewportTransform = PortraitLayout::place(stageW, stageH, sideK, vs * sideK, m_sideShown ? safeRight : stageW, sideBottom);
		Box sb;
		for (int i = 0; i < std::min(m_sideCount, 16); ++i)
		{
			if (AptCharacterInst *f = m_sideFramePath[i].empty() ? nullptr : apt.resolvePath(root, m_sideFramePath[i].substr(0, m_sideFramePath[i].rfind('.'))))
			{
				sb.add(boxThrough(f, chainToRoot(f, root)));
			}
		}
		if (m_sideShown && sb.ok())
		{
			hudTop = std::min(hudTop, sb.y0);
			m_portraitReport["side_top"] = sb.y0 * unitY;
			m_portraitReport["side_left"] = sb.x0 * unitX;
		}
		m_portraitReport["side"] = sideK;
		m_portraitReport["side_columns"] = (float)m_sideColumns;
	}

	// ---- the planning mode's bar: below the toolbar strip, centred ----
	if (AptCharacterInst *plan = apt.resolvePath(root, "planningModeUI"))
	{
		plan->viewportTransform = PortraitLayout::place(stageW * 0.5f, 0.0f, 1.0f, vs, (safeLeft + safeRight) * 0.5f, strip);
	}

	float bookRight = safeLeft; // the spell book's right edge (root units): the help box keeps right of it
	// ---- the spell book: hangs by its vine from the Palantir's top-left (C: from where a 125 % Palantir's would be), under the strip ----
	if (AptCharacterInst *book = apt.resolvePath(root, "SpellBookUI"))
	{
		const AptMatrix from = spec.radarApart ? PortraitLayout::place(0.0f, stageH, k, vs * k, safeLeft, safeBottom) : palantir;
		const float kb = k;
		book->viewportTransform = from;
		m_spellBookScale = kb;
		float x0, y0, x1, y1;
		if (book->contentBounds(x0, y0, x1, y1))
		{
			float topX, topY, bottomX, bottomY;
			book->matrix.apply(x0, y0, topX, topY);
			book->matrix.apply(x1, y1, bottomX, bottomY);
			const float footX = 0.0f, footY = std::max(topY, bottomY);
			float placedX, placedY;
			from.apply(footX, footY, placedX, placedY);
			if (spec.radarApart)
			{
				placedY = std::min(placedY, placed.y0); // C: no frame to hang from: the vine stands on the command globe's top
			}
			float ks = kb;
			const float up = footY - std::min(topY, bottomY);
			if (up > 0.0f && vs * ks * up > placedY - strip)
			{
				ks = std::max(0.0f, (placedY - strip) / (vs * up));
			}
			m_spellBookScale = ks;
			book->viewportTransform = PortraitLayout::place(footX, footY, ks, vs * ks, placedX, placedY);
			const float top = placedY - vs * ks * up;
			hudTop = std::min(hudTop, top);
			m_portraitReport["spellbook"] = ks;
			bookRight = book->viewportTransform.a * std::max(topX, bottomX) + book->viewportTransform.tx;
			m_portraitReport["spellbook_top"] = top * unitY;
		}
	}

	// ---- the help box: right of the Palantir's grown right side (as today), never past the safe area ----
	if (AptCharacterInst *help = apt.resolvePath(root, "helpBox"))
	{
		const Box hb = movieBox("helpBox");
		AptMatrix m;
		if (hb.ok())
		{
			// its bottom-left just above the Palantir's top, at the Palantir's left (C: the command globe's), uniform at today's factor
			// at most twice the width-fit size (its text then reads), as far as the width right of the vine holds it
			const float left = std::max(spec.radarApart ? safeLeft : placed.x0, bookRight) + gapX;
			const float kh = std::max(1.0f, std::min(2.0f, (safeRight - gapX - left) / hb.w()));
			const float x = std::min(left, safeRight - hb.w() * kh);
			m = PortraitLayout::place(hb.x0, hb.y1, kh, vs * kh, std::max(safeLeft, x), placed.y0 - gapY);
		}
		help->viewportTransform = m;
	}
	m_portraitReport["hud_top"] = hudTop * unitY;
	return true;
}
