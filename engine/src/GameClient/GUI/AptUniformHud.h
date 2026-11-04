// OpenBFME. GPL-3.0.
//
// AptUniformHud (lane IOS-29, OpenBFME presentation, NOT retail): the round-HUD rule for the in-game Apt movies.
//
// TARGET FACT (RotWK, S-130): the Apt stage (1024 x 768) is drawn to the window with an independent x and y scale (AptStageMapping::Stretch,
// the donor's setScaledTransform007833E0), so everything an in-game movie draws is round only on a 4:3 display: on the iPhone Duo's inner
// screen (2670 x 1878 landscape, 1878 x 2670 portrait) a round button is a wide oval in landscape (x / y 1.067) and a tall one in portrait
// (x / y 0.528).
//
// THE RULE (on touch / mobile, or with a HUD layout other than retail's: AptPalantir::HudLayout::uniform): nothing an in-game movie draws keeps
// sx != sy. Walking each loaded level, a "unit" is drawn at the window scale (sx, sy) its stage mapping and the viewport transforms above it give;
// a unit with |sx / sy - 1| > kTolerance gets a presentTransform that scales its larger axis down to s = min(sx, sy) (the 4:3-fit size) about
// its anchor, so it stays where it belongs on the screen:
//   * the unit: a level whose screen lays out its own children (one of the root's children carries a viewport transform: the Palantir, whose
//     groups AptPalantir::setViewportSize already scales uniformly about their corners) is handled child by child, so only the children it does
//     not lay out (the help box, the button flash stage) are corrected; any other level (the quit menu, the objectives, the spell store, a
//     future in-game movie) is one unit: its root;
//   * the anchor: per axis, the point of the unit's content box at the box's own relative place on the stage (t = x0 / (stage - width),
//     clamped to 0 .. 1): a box flush with the left edge keeps that edge, one flush right its right edge, a centred one (a full-screen menu)
//     its centre - a uniformly scaled, centred menu, as the front end's Fit mapping draws it in portrait.
//   * a backdrop (a root unit's child edge to edge across the stage on the shrunk axis, with no button in it: a shade, a band) keeps the stretch
//     on that axis (backdrop()), so the pause menu still dims the whole screen and its title band still spans it. Lane IOS-33: the dim itself is
//     the in-game background's View3D (SFE_MenuOverlay), a model seen at a fixed horizontal field of view: the device draws a backdrop's View3D
//     over the whole window (isBackdrop, AptView3DBackdropWidth), so in portrait the game is dimmed above and below the menu too.
// The correction sits in AptCharacterInst::presentTransform, outside the screen's own viewport transforms, so the drawing (AptRenderList) and every
// hit test (globalMatrix: AptInput, the tap assist's nearest button, the held finger's help) read the same matrix. Off (a desktop at 100 %),
// every presentTransform is the identity and the drawing is retail's exactly.
// INFERENCE: the content box is AptSpriteInst::contentBounds (every child, shown or not), measured every frame (a unit that grows moves its anchor
// smoothly: the anchor is linear in the box's position).
//
// THE MENUS (lane IOS-32, the owner's call 2026-11-04: "centre the menus in portrait"): a full-screen in-game menu (the pause menu, the objectives,
// the save / load menu, the players screen, the in-game Options, the spell store and the dimmed background under them: Menus::levels, chosen by
// InGameHud by movie) is not anchored at its content box but drawn as the front end's Fit mapping draws a whole stage: the stage's centre on the
// safe area's centre on the shrunk axis. The pause menu's title band starts at the stage's top, so the anchor rule pinned it to the window's top
// in portrait; centred, every menu's title band sits at the same height, at the top of the dimmed 4:3 band, and the menu in the middle of the
// safe area (the notch and the home indicator excluded). Landscape keeps its look (the stage's centre is the content's there); the HUD (the
// Palantir, the banners, the chat) stays anchored.

#pragma once

#include "GameClient/AptCanvas.h"

#include <string>
#include <vector>

class Apt;
class AptCharacterInst;
class AptSpriteInst;

class AptUniformHud
{
public:
	static constexpr float kTolerance = 0.01f; ///< |sx / sy - 1| above this is a squashed circle

	// one drawn unit or one instance with its own viewport transform: the window pixels per stage unit it is drawn at
	struct Entry
	{
		int level = 0;
		std::string path;    ///< targetPath
		float sx = 1, sy = 1; ///< window pixels per stage unit, as drawn (mapping x every present / viewport transform down to it)
		float fixX = 1, fixY = 1; ///< the rule's factors on this instance (1, 1: none)
		bool unit = false;    ///< a unit of the rule (a level's root, or a root's child of a level laid out per child)
		///< drawn edge to edge across the window on its more stretched axis: a full-bleed backdrop (the spell store's banner and shade, which
		///< AptSpellStore keeps stage-wide on purpose), a fill with nothing round to squash; the guard allows it
		bool fullBleed = false;
		bool distorted() const { return sx <= 0.0f || sy <= 0.0f || ratioOff(sx, sy) > kTolerance; }
		bool squashes() const { return distorted() && !fullBleed; } ///< what the guard refuses
	};
	static float ratioOff(float sx, float sy) { return sx > sy ? sx / sy - 1.0f : sy / sx - 1.0f; }

	// lane IOS-32: the levels drawn as centred menus, and the window's safe area (window pixels kept clear: left, top, right, bottom)
	struct Menus
	{
		std::vector<int> levels;
		float safeInsets[4] = {};
		bool has(int level) const;
	};
	// the rule, once per HUD update after the screens laid out their children; `enabled` false resets every presentTransform to the identity
	static void apply(Apt &apt, const AptStageMapping &mapping, bool enabled, const Menus &menus);
	static void apply(Apt &apt, const AptStageMapping &mapping, bool enabled); // no menu levels
	// lane IOS-32: the stage point the safe area's centre is drawn at (the stage mapping's inverse of the safe area's middle)
	static void safeCentre(const AptStageMapping &mapping, const float safeInsets[4], float &cx, float &cy);
	// the audit: every unit and every instance carrying a viewport or present transform, in level and tree order
	static void audit(Apt &apt, const AptStageMapping &mapping, std::vector<Entry> &out);
	// the rule's x / y factors on the instance at `path` ("_level<n>.<child>...": its level root's and that root child's presentTransform), 1 / 1 when
	// none: the device's View3D (AptView3DImageSize) undoes only the stretch the rule left (GodotAptPlayer)
	static void presentScale(Apt &apt, const std::string &path, float &fx, float &fy);
	// lane IOS-33: is the instance at `path` in a backdrop of a corrected level (backdrop(): a root's child kept edge to edge on the window)? The
	// device draws such a View3D (the in-game background's dimming plane, SFE_MenuOverlay) over the whole window (AptView3DBackdropWidth)
	static bool isBackdrop(Apt &apt, const std::string &path);
	// a root unit's child drawn edge to edge across the stage on the axis the root's correction shrinks, with no button in it (the in-game
	// background's shade, the pause menu's title band): a backdrop - it keeps the stage's stretch on that axis (a fill has nothing round to squash;
	// shrunk, it would leave the game un-dimmed beside it) and the root's correction on the other; the identity for any other child
	static AptMatrix backdrop(AptSpriteInst &root, AptCharacterInst &child, const AptStageMapping &mapping);
	// the presentTransform the rule gives `unit` drawn under `parentChain` (the stage <- parent matrix); the identity when it is uniform already
	// `centre` (lane IOS-32, a menu's root): the stage point the stage's centre goes to on the shrunk axis, instead of the content box's anchor
	static AptMatrix correction(const AptCharacterInst &unit, const AptMatrix &parentChain, const AptStageMapping &mapping, float &fixX, float &fixY,
		const float *centre = nullptr);
};
