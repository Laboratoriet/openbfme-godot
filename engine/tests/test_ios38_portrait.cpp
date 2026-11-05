// OpenBFME. GPL-3.0.
//
// lane IOS-38 (OpenBFME presentation, a PROTOTYPE behind a developer switch, not retail): the portrait layout prototypes (GameClient/GUI/PortraitLayout.h,
// AptPalantirPortrait.cpp, TacticalCamera::setPortraitHorizontalFov). The retail-data cases SKIP without ROTWK_INSTALL / BFME2_INSTALL.

#include "HudTestUtil.h"

#include "GameClient/CameraSettings.h"
#include "GameClient/GUI/PortraitLayout.h"
#include "GameClient/GUI/ShellServices.h"
#include "GameClient/InGameHud.h"
#include "GameClient/TacticalCamera.h"
#include "Libraries/Source/Apt/Apt.h"
#include "Libraries/Source/Apt/AptButtonInst.h"
#include "Libraries/Source/Apt/AptCharacterInst.h"
#include "Libraries/Source/Apt/AptInput.h"
#include "GameClient/AptCanvas.h"

using namespace hudtest;

namespace
{
struct PortraitRig
{
	Rig rig;
	RecordingShellServices services;
	std::unique_ptr<InGameHud> hud;
	explicit PortraitRig(SharedWorld &s) : rig(s, "map mp fall back 4p", "FactionMen")
	{
		Player *p = rig.game->players().findPlayerWithName("Player_1");
		REQUIRE(p != nullptr);
		rig.game->players().setLocalPlayer(p);
		rig.local = p;
		InGameHud::Config cfg{ *rig.game, *s.world, *s.mount->fs, services, rig.view, s.mouse, s.meta, nullptr };
		hud = std::make_unique<InGameHud>(cfg);
		std::string error;
		REQUIRE_MESSAGE(hud->boot(&error), error);
	}
	~PortraitRig() { hud.reset(); }
	void frames(int n)
	{
		for (int i = 0; i < n; ++i)
		{
			hud->update(0.033);
			rig.game->advance(0.033);
		}
	}
	AptSpriteInst *root() { return hud->apt().level(hud->palantir()->level()); }
	AptCharacterInst *at(const std::string &path) { return hud->apt().resolvePath(root(), path); }
};

AptButtonInst *firstButton(AptCharacterInst *instance)
{
	if (!instance)
	{
		return nullptr;
	}
	if (AptButtonInst *button = instance->asButton())
	{
		return button;
	}
	if (AptSpriteInst *sprite = instance->asSprite())
	{
		for (AptCharacterInst *child : sprite->children())
		{
			if (AptButtonInst *button = firstButton(child))
			{
				return button;
			}
		}
	}
	return nullptr;
}

// the window box of `c`'s content as drawn (its global matrix, the stage stretched to the window)
bool windowBox(AptCharacterInst *c, const AptStageMapping &m, float out[4])
{
	float x0, y0, x1, y1;
	if (!c || !c->contentBounds(x0, y0, x1, y1))
	{
		return false;
	}
	out[0] = out[1] = 1e9f;
	out[2] = out[3] = -1e9f;
	const float xs[4] = { x0, x1, x0, x1 }, ys[4] = { y0, y0, y1, y1 };
	for (int i = 0; i < 4; ++i)
	{
		float sx, sy, wx, wy;
		c->globalMatrix().apply(xs[i], ys[i], sx, sy);
		m.stageToWindow(sx, sy, wx, wy);
		out[0] = std::min(out[0], wx);
		out[1] = std::min(out[1], wy);
		out[2] = std::max(out[2], wx);
		out[3] = std::max(out[3], wy);
	}
	return true;
}

// the share of a probe grid over `box` whose press hits `button` and that the HUD takes
float hitShare(PortraitRig &h, AptButtonInst *button, const AptStageMapping &m, const float box[4])
{
	int hits = 0, probes = 0;
	for (int row = 1; row < 8; ++row)
	{
		for (int column = 1; column < 8; ++column)
		{
			const float wx = box[0] + (box[2] - box[0]) * (float)column / 8.0f, wy = box[1] + (box[3] - box[1]) * (float)row / 8.0f;
			float sx, sy;
			m.windowToStage(wx, wy, sx, sy);
			++probes;
			if (h.hud->apt().input().hitTestButtons(sx, sy) == button && h.hud->isOverGui((int)wx, (int)wy))
			{
				++hits;
			}
		}
	}
	return (float)hits / (float)probes;
}
} // namespace

TEST_CASE("ios38 portrait: the switch's values, the specs and the placement maths")
{
	PortraitLayout::Id id = PortraitLayout::OneHand;
	CHECK(PortraitLayout::parse("", id));
	CHECK(id == PortraitLayout::Today);
	CHECK(PortraitLayout::parse("a", id));
	CHECK(id == PortraitLayout::MoreMap);
	CHECK(PortraitLayout::parse("B", id));
	CHECK(id == PortraitLayout::OneHand);
	CHECK(PortraitLayout::parse("c", id));
	CHECK(id == PortraitLayout::Split);
	CHECK(PortraitLayout::parse("default", id));
	CHECK(id == PortraitLayout::Today);
	id = PortraitLayout::Split;
	CHECK_FALSE(PortraitLayout::parse("d", id));
	CHECK(id == PortraitLayout::Split); // a refused value leaves the layout
	CHECK(std::string(PortraitLayout::spec(PortraitLayout::Today).key) == "default");
	CHECK(std::string(PortraitLayout::spec(PortraitLayout::MoreMap).key) == "a");
	CHECK(std::string(PortraitLayout::spec(PortraitLayout::OneHand).key) == "b");
	CHECK(std::string(PortraitLayout::spec(PortraitLayout::Split).key) == "c");
	// today's: nothing changes (the factor 1, the IOS-27 column, IOS-3's camera)
	const PortraitLayout::Spec &today = PortraitLayout::spec(PortraitLayout::Today);
	CHECK(today.palantir == 1.0f);
	CHECK(today.sideBar == PortraitLayout::SideTopColumn);
	CHECK(today.hfovDeg == 0.0f);
	// place: (ax, ay) goes to (px, py), distances from it scale by (a, d)
	const AptMatrix m = PortraitLayout::place(0.0f, 768.0f, 2.0f, 0.5f, 10.0f, 700.0f);
	float x, y;
	m.apply(0.0f, 768.0f, x, y);
	CHECK(x == 10.0f);
	CHECK(y == 700.0f);
	m.apply(100.0f, 668.0f, x, y);
	CHECK(x == 210.0f);
	CHECK(y == 650.0f);
	// factorFor: a 40-unit button drawn at 0.5 px / unit is 20 px; 44 pt at 1.5 px / pt is 66 px: factor 3.3
	CHECK(PortraitLayout::factorFor(44.0f, 40.0f, 0.5f, 1.5f) == doctest::Approx(3.3f)); // tolerance: float division
	CHECK(PortraitLayout::factorFor(44.0f, 0.0f, 0.5f, 1.5f) == 1.0f);
}

TEST_CASE("ios38 portrait: a prototype's camera is as wide as its spec in portrait; landscape and today's are untouched")
{
	CameraSettings settings;
	TacticalCamera cam(settings);
	const double deg = 180.0 / 3.14159265358979323846;
	// today's portrait (IOS-3): 4:3's vertical angle (38.58 degrees), narrowed to the aspect
	cam.setViewport(939, 1335);
	const double aspect = 939.0 / 1335.0;
	const double fourThreeV = 2.0 * std::atan(std::tan(25.0 / deg) * 3.0 / 4.0);
	CHECK(cam.verticalFov() == doctest::Approx(fourThreeV).epsilon(1e-6)); // tolerance: float trigonometry
	const float landscapeV = [&] {
		cam.setViewport(1335, 939);
		return cam.verticalFov();
	}();
	for (int i = PortraitLayout::MoreMap; i < PortraitLayout::Count; ++i)
	{
		const PortraitLayout::Spec &s = PortraitLayout::spec((PortraitLayout::Id)i);
		INFO(s.key);
		REQUIRE(s.hfovDeg > 0.0f); // tolerance: every prototype sets its own angle (its value is checked against the camera below)
		cam.setPortraitHorizontalFov((float)(s.hfovDeg / deg));
		cam.setViewport(939, 1335);
		CHECK(cam.viewHorizontalFov() * deg == doctest::Approx(s.hfovDeg).epsilon(1e-5)); // tolerance: float trigonometry
		CHECK(cam.verticalFov() == doctest::Approx(2.0 * std::atan(std::tan(s.hfovDeg / deg / 2.0) / aspect)).epsilon(1e-5)); // tolerance: float trig
		// wider than today's in portrait, never past retail's 50 degrees across
		CHECK(cam.viewHorizontalFov() > (float)(2.0 * std::atan(std::tan(fourThreeV / 2.0) * aspect))); // tolerance: a range: wider than today's
		CHECK(cam.viewHorizontalFov() * deg <= 50.0); // tolerance: a range: never past retail's 50 degrees
		// landscape: exactly today's
		cam.setViewport(1335, 939);
		CHECK(cam.verticalFov() == landscapeV);
		cam.setPortraitHorizontalFov(0.0f);
	}
	cam.setViewport(939, 1335);
	CHECK(cam.verticalFov() == doctest::Approx(fourThreeV).epsilon(1e-6)); // tolerance: float trigonometry
	// A turns the landscape view upright: as wide as a 4:3 screen is tall
	CHECK(PortraitLayout::spec(PortraitLayout::MoreMap).hfovDeg == doctest::Approx(fourThreeV * deg).epsilon(1e-3)); // tolerance: the spec's 2 decimals
}

TEST_CASE("ios38 portrait: each prototype places the HUD round, inside the safe area below the toolbar strip, and a press lands on what is drawn")
{
	if (!haveWorld("ios38 portrait"))
	{
		return;
	}
	PortraitRig h(shared());
	h.frames(30);
	Object *builder = h.rig.make("MenPorter", 2800, 1400);
	REQUIRE(builder != nullptr);
	h.hud->input().ui().selectObject(builder->getID());
	h.frames(40);
	AptPalantir *p = h.hud->palantir();
	REQUIRE(p->sideBarShown());
	REQUIRE(p->sideBarCount() > 1); // tolerance: the builder's build list (its count is the faction's; two or more for a pitch)
	AptCharacterInst *frame = h.at("PalantirFrame");
	AptCharacterInst *side = h.at("SideCommandBar");
	REQUIRE(frame != nullptr);
	REQUIRE(side != nullptr);
	AptButtonInst *options = firstButton(h.at("PalantirButtons.Buttons.Options"));
	REQUIRE(options != nullptr);
	const int width = 939, height = 1335;
	h.hud->setWindowSize(width, height);
	AptStageMapping m;
	m.windowW = (float)width;
	m.windowH = (float)height;
	// today's portrait at 125 %, for the comparison: the prototypes leave it exactly as it was
	AptPalantir::HudLayout base;
	base.scale = 1.25f;
	base.roundHud = true;
	h.hud->setHudLayout(base);
	h.frames(2);
	const AptMatrix todayFrame = frame->viewportTransform, todaySide = side->viewportTransform;
	CHECK(p->portraitReport().empty());
	const float ppt = PortraitLayout::kDefaultPointPx;
	for (int i = PortraitLayout::MoreMap; i < PortraitLayout::Count; ++i)
	{
		const PortraitLayout::Spec &s = PortraitLayout::spec((PortraitLayout::Id)i);
		INFO(s.key);
		AptPalantir::HudLayout layout = base;
		layout.portraitLayout = i;
		h.hud->setHudLayout(layout);
		h.frames(2);
		const std::map<std::string, float> &r = p->portraitReport();
		REQUIRE(r.count("layout") == 1);
		CHECK(r.at("layout") == (float)i);
		const float strip = PortraitLayout::kToolbarPt * ppt;
		CHECK(r.at("strip_bottom") == doctest::Approx(strip)); // tolerance: stage <-> window float mapping
		// round: the Palantir and the side bar are drawn at one scale across and down
		for (AptCharacterInst *c : { frame, side })
		{
			const AptMatrix g = c->globalMatrix();
			// tolerance: the window mapping's float products (a * width / 1024 against d * height / 768)
			CHECK(g.a * m.scaleX() == doctest::Approx(g.d * m.scaleY()).epsilon(1e-4));
		}
		AptCharacterInst *globe = h.at("CommandBackground"); // the command globe: with the Palantir in A and B, the bottom-centre piece in C
		REQUIRE(globe != nullptr);
		CHECK(globe->viewportTransform.a == doctest::Approx(r.at("palantir"))); // tolerance: float mapping
		// the HUD stays inside the window and below the strip (its top reported, and the side bar's frames measured)
		CHECK(r.at("hud_top") >= strip - 0.5f); // tolerance: half a pixel of float mapping
		for (int b = 0; b < p->sideBarCount(); ++b)
		{
			float fb[4];
			REQUIRE(windowBox(h.at("SideCommandBar.ButtonSet.Button" + std::to_string(b)), m, fb));
			CHECK(fb[0] >= -0.5f); // tolerance: half a pixel of float mapping
			CHECK(fb[2] <= (float)width + 0.5f);
			CHECK(fb[1] >= strip - 0.5f); // tolerance: half a pixel of float mapping
			CHECK(fb[3] <= (float)height + 0.5f); // tolerance: half a pixel of float mapping
		}
		float pb[4];
		REQUIRE(windowBox(frame, m, pb));
		CHECK(pb[3] <= (float)height + 0.5f); // tolerance: half a pixel of float mapping
		CHECK(pb[2] <= (float)width + 0.5f);
		// the side bar's buttons are at the spec's pitch (one button and its frame art per pitch): its first button at least 44 pt across less the art
		AptButtonInst *sideButton = firstButton(h.at("SideCommandBar.ButtonSet.Button0"));
		REQUIRE(sideButton != nullptr);
		float sb[4];
		REQUIRE(windowBox(sideButton, m, sb));
		// the spec's pitch in points: the button itself (less its frame art) at least 80 % of it, never under 44 pt less the art's rim (8 pt)
		CHECK(sb[2] - sb[0] >= (s.sideBarPt - 8.0f) * ppt); // tolerance: the frame art's rim between the pitch and the button
		// a press inside the drawn button hits it (most of a round button's box: its corners are outside the Hit shape)
		// tolerance: a probe grid over the content box: a round button's corners are outside its Hit shape, so most probes, not all, hit it
		CHECK(hitShare(h, sideButton, m, sb) >= 0.5f);
		float ob[4];
		REQUIRE(windowBox(options, m, ob));
		CHECK(hitShare(h, options, m, ob) >= 0.5f); // tolerance: as above
		// the prototype differs from today's: the side bar stands at the bottom, not under the message lines at the top
		CHECK(side->viewportTransform.ty != todaySide.ty);
		// B and C: the arc's buttons at least 44 pt (the glass a finger aims at)
		if (s.id != PortraitLayout::MoreMap)
		{
			float gb[4];
			REQUIRE(windowBox(h.at("CommandButtons.glass0"), m, gb));
			CHECK(gb[2] - gb[0] >= PortraitLayout::kTargetPt * ppt - 0.5f); // tolerance: half a pixel of float mapping
		}
		// the resource bar's text at least 11 pt (lane IOS-42: A from a HUD size of 150 %, below)
		if (s.id != PortraitLayout::MoreMap)
		{
			CHECK(r.at("text_pt") >= PortraitLayout::kTextPt - 0.01f); // tolerance: float products
		}
		// C: the minimap globe apart in the top-right corner, below the strip; the press on it is the radar's
		if (s.radarApart)
		{
			float rb[4];
			REQUIRE(windowBox(h.at("RadarBackground"), m, rb));
			CHECK(rb[2] <= (float)width + 0.5f); // tolerance: half a pixel of float mapping
			CHECK(rb[1] >= strip - 0.5f);
			CHECK(rb[3] < (float)height * 0.5f); // tolerance: a range: in the upper half
			CHECK(rb[2] - rb[0] == doctest::Approx(s.radarPt * ppt).epsilon(1e-3)); // tolerance: float mapping
			float sq[4];
			REQUIRE(h.hud->radarSquare(sq));
			CHECK(h.hud->isOverGui((int)((sq[0] + sq[2]) * 0.5f), (int)((sq[1] + sq[3]) * 0.5f)));
			CHECK(sq[1] >= rb[1] - 1.0f); // tolerance: the square is in whole pixels
			CHECK_FALSE(frame->visible); // the frame around both globes is hidden
		}
		else
		{
			CHECK(frame->visible);
		}
	}
	// lane IOS-42: A follows the HUD size. 100 %: its own 1.25, the resource bar in the frame's band (the frame's transform, no plate at the top);
	// 150 %: the arc's buttons 44 pt and the digits 11 pt type; between, between
	{
		AptPalantir::HudLayout a = base;
		a.portraitLayout = PortraitLayout::MoreMap;
		a.scale = 1.0f;
		h.hud->setHudLayout(a);
		h.frames(2);
		const std::map<std::string, float> &r = p->portraitReport();
		CHECK(r.at("palantir") == doctest::Approx(PortraitLayout::spec(PortraitLayout::MoreMap).palantir)); // tolerance: float mapping
		CHECK(r.count("resources_x0") == 0); // no plate: the bar is in its band
		AptCharacterInst *bar = h.at("ResourceBar");
		REQUIRE(bar != nullptr);
		// tolerance: the bar is placed about its own centre with the Palantir's factor: the same matrix up to float rounding
		CHECK(bar->viewportTransform.a == doctest::Approx(frame->viewportTransform.a).epsilon(1e-5));
		CHECK(bar->viewportTransform.d == doctest::Approx(frame->viewportTransform.d).epsilon(1e-5)); // tolerance: as above
		CHECK(bar->viewportTransform.tx == doctest::Approx(frame->viewportTransform.tx).epsilon(1e-3)); // tolerance: as above
		CHECK(bar->viewportTransform.ty == doctest::Approx(frame->viewportTransform.ty).epsilon(1e-3)); // tolerance: as above
		float barBox[4], frameBox[4];
		REQUIRE(windowBox(bar, m, barBox));
		REQUIRE(windowBox(frame, m, frameBox));
		CHECK(barBox[1] >= frameBox[1]); // tolerance: a range: inside the frame's box (its band)
		CHECK(barBox[3] <= frameBox[3] + 0.5f); // tolerance: half a pixel of float mapping
		const float small = r.at("palantir");
		a.scale = 1.25f;
		h.hud->setHudLayout(a);
		h.frames(2);
		const float middle = p->portraitReport().at("palantir");
		a.scale = 1.5f;
		h.hud->setHudLayout(a);
		h.frames(2);
		const std::map<std::string, float> &top = p->portraitReport();
		CHECK(middle > small); // tolerance: a range: the Palantir grows with the HUD size
		CHECK(top.at("palantir") > middle); // tolerance: as above
		// tolerance: linear in the HUD size: the middle size halfway
		CHECK(middle == doctest::Approx((small + top.at("palantir")) * 0.5f).epsilon(1e-4));
		float gb[4];
		REQUIRE(windowBox(h.at("CommandButtons.glass0"), m, gb));
		CHECK(gb[2] - gb[0] >= PortraitLayout::kTargetPt * ppt - 0.5f); // tolerance: half a pixel of float mapping
		CHECK(top.at("text_pt") >= PortraitLayout::kTextPt - 0.01f); // tolerance: float products
		CHECK(top.at("hud_top") >= PortraitLayout::kToolbarPt * ppt - 0.5f); // tolerance: half a pixel; still below the toolbar strip
		float pb[4];
		REQUIRE(windowBox(frame, m, pb));
		CHECK(pb[2] <= (float)width + 0.5f); // tolerance: half a pixel of float mapping
		// the mapping itself: the spec's at 100 % and below, `large` at 150 % and above
		CHECK(PortraitLayout::moreMapPalantir(0.8f, 2.0f) == PortraitLayout::spec(PortraitLayout::MoreMap).palantir);
		CHECK(PortraitLayout::moreMapPalantir(2.0f, 2.0f) == 2.0f);
		CHECK(PortraitLayout::moreMapPalantir(1.5f, 1.0f) == PortraitLayout::spec(PortraitLayout::MoreMap).palantir); // never below the spec's
	}
	// back to today's: exactly as before, and the report is empty
	h.hud->setHudLayout(base);
	h.frames(2);
	CHECK(p->portraitReport().empty());
	CHECK(frame->viewportTransform.a == todayFrame.a);
	CHECK(frame->viewportTransform.tx == todayFrame.tx);
	CHECK(frame->viewportTransform.ty == todayFrame.ty);
	CHECK(side->viewportTransform.a == todaySide.a);
	CHECK(side->viewportTransform.ty == todaySide.ty);
	// landscape with a prototype chosen: today's landscape layout exactly
	h.hud->setWindowSize(1335, 939);
	h.hud->setHudLayout(base);
	h.frames(2);
	const AptMatrix landFrame = frame->viewportTransform, landSide = side->viewportTransform;
	for (int i = PortraitLayout::MoreMap; i < PortraitLayout::Count; ++i)
	{
		AptPalantir::HudLayout layout = base;
		layout.portraitLayout = i;
		h.hud->setHudLayout(layout);
		h.frames(2);
		CHECK(p->portraitReport().empty());
		CHECK(frame->viewportTransform.a == landFrame.a);
		CHECK(frame->viewportTransform.tx == landFrame.tx);
		CHECK(frame->viewportTransform.ty == landFrame.ty);
		CHECK(side->viewportTransform.a == landSide.a);
		CHECK(side->viewportTransform.tx == landSide.tx);
	}
}
