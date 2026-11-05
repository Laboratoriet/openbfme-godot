// OpenBFME. GPL-3.0.
//
// PortraitLayout (lane IOS-38, OpenBFME presentation, NOT retail): portrait layout PROTOTYPES for the owner to choose from (2026-11-05: "propose
// 2-3 options as mock-ups, don't commit to one"). Behind a developer switch only: game.gd's --portrait-layout=a|b|c or the Options.ini key
// OpenBFMEPortraitLayout (no Options row). Without it, and in landscape always, the layout is today's exactly (IOS-3 / 18 / 27 / 29 / 32 / 33).
//
// Each prototype is one coherent whole for a phone held upright (the iPhone Duo's inner screen: 626 x 890 pt):
//   A "More map"   the Palantir docked in the bottom-left corner at today's size, the side bar a block beside it in the bottom-right corner (the
//                  upper three quarters of the screen are map only), the resource bar at the top-left, the camera's view as wide as a 4:3 screen's
//                  is tall (Hor+ turned upright: about four times today's ground);
//   B "One hand"   the Palantir large in the lower third (its arc's buttons at least 44 pt), the side bar one column on the right edge from the bottom
//                  up (in the right thumb's reach), the camera between today's and A's;
//   C "Split"      mobile strategy-game conventions: the command arc and the portrait centred at the bottom, the minimap globe apart in the top-right
//                  corner under the toolbar strip, the resource bar at the top-left beside it, the side bar a block in the bottom-right corner.
// All three keep a strip of kToolbarPt at the top of the safe area free (the touch command toolbar of lane IOS-37 lives there), move InGameUI's
// message lines below it (at least kTextPt), and draw the resource bar's digits as tall as 11 pt type's capitals (kTextCapPt): A and C move the bar
// to the top-left under the strip, B's large Palantir draws it that size in place.
// How: transforms only. Palantir.apt's root is flat (the frame, each globe's clips, the arc, the resource bar are siblings), so each root child gets
// a viewportTransform that scales it uniformly about an anchor of its own and moves the anchor to a point of the safe area (place()); C hides the
// carved frame around both globes. The round-HUD rule (AptUniformHud) then finds every unit uniform already. The hit tests read the same matrices (AptCharacterInst::globalMatrix), so a press lands on what is drawn.

#pragma once

#include "Libraries/Source/Apt/AptCharacterInst.h"

#include <string>

class PortraitLayout
{
public:
	enum Id
	{
		Today = 0,    ///< today's portrait (no prototype)
		MoreMap = 1,  ///< A
		OneHand = 2,  ///< B
		Split = 3,    ///< C
		Count
	};
	// where the side bar's buttons go
	enum SideBar
	{
		SideTopColumn = 0,    ///< IOS-27's portrait column from the top of the right edge
		SideBottomBlock = 1,  ///< a block of up to `sideColumns` columns standing in the safe area's bottom-right corner
		SideBottomColumn = 2, ///< one column on the right edge, its last button at the safe area's bottom (grows upwards)
	};
	static constexpr float kToolbarPt = 52.0f; ///< the strip kept free at the safe area's top (IOS-37's toolbar: 44 pt buttons and a margin)
	static constexpr float kTextPt = 11.0f;    ///< the smallest text the prototypes draw (the resource bar, the message lines)
	///< text size is judged by the drawn digits: 11 pt type (Apple's smallest body size) has a cap height of about 0.7 em (SF Pro), 7.7 pt
	static constexpr float kTextCapPt = 7.7f;
	///< the resource bar's digits are this share of their Apt font height when drawn (measured on the Mac stand-in, RotWK 2.01's Palantir font:
	///< 7 px digits at a 16.5 px font height)
	static constexpr float kResourceCapPerFont = 0.42f;
	static constexpr float kTargetPt = 44.0f;  ///< Apple's smallest comfortable touch target
	static constexpr float kDefaultPointPx = 1.5f; ///< pixels per point when the device does not say (the Mac stand-in: the Duo's 3 px / pt at half size)

	struct Spec
	{
		Id id = Today;
		const char *key = "";   ///< the switch's value: "a", "b", "c"
		const char *name = "";  ///< "More map" ...
		float palantir = 1.0f;  ///< the Palantir's factor on top of the width-fit size (today: the HUD size option, 1.25 on a phone)
		float palantirX = 0.0f; ///< the Palantir's anchor across the safe area: 0 its bottom-left corner, 0.5 its bottom centre
		SideBar sideBar = SideTopColumn;
		int sideColumns = 1;    ///< SideBottomBlock: at most this many columns (two: IOS-27's landscape rule)
		float sideBarPt = 0.0f; ///< the side bar's button pitch in points (0: IOS-27's size)
		bool radarApart = false; ///< C: the minimap globe in the top-right corner
		float radarPt = 0.0f;   ///< C: the globe's diameter in points
		bool resourcesTop = false; ///< A, C: the resource bar at the top-left, under the toolbar strip, on a plate the device draws
		float hfovDeg = 0.0f;   ///< the camera's horizontal field of view in portrait, degrees (0: IOS-3's 4:3 vertical view, narrowed: 27.6 at the Duo's aspect)
		float bubbles = 0.0f;   ///< the radial bubbles' square size factor over a building (0: the HUD size option's, 125 % on a phone: 35 pt)
	};
	static const Spec &spec(Id id);
	// "" / "default" / "today" -> Today, "a" / "b" / "c" (any case) -> A / B / C; false for anything else (`id` untouched)
	static bool parse(const std::string &key, Id &id);
	// the matrix that scales by (a, d) about the stage point (ax, ay) and moves that point to (px, py): x' = a x + tx, y' = d y + ty
	static AptMatrix place(float ax, float ay, float a, float d, float px, float py);
	// the factor that makes `extentStage` (stage units, drawn at `unitPx` window pixels per stage unit) measure `pt` points at `pointPx`
	static float factorFor(float pt, float extentStage, float unitPx, float pointPx);
};
