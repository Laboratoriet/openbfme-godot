// OpenBFME retail tests of the Palantir's centre and side state (lane HUD-2): the Evenstar / Ring of the PlayerMagic button (SetPlayerButtonsState), the
// command interface with the selection's portrait (PalantirCommandUI) and the RenderGlobe clip of the globe. They SKIP when ROTWK_INSTALL / BFME2_INSTALL are
// unset. GPL-3.0.

#include "HudTestUtil.h"

#include "Common/PlayerTemplate.h"
#include "Common/ModelState.h"
#include "GameClient/GUI/ShellServices.h"
#include "GameClient/InGameHud.h"
#include "GameClient/InGameHeroSelect.h"
#include "GameClient/PalantirCommandUI.h"
#include "GameLogic/Object/ExperienceTracker.h"
#include "Libraries/Source/Apt/AptCharacterInst.h"
#include "Libraries/Source/Apt/AptRenderList.h"
#include "Libraries/Source/Apt/AptButtonInst.h"
#include "Libraries/Source/Apt/AptInput.h"
#include "GameClient/AptCanvas.h"
#include "GameClient/GUI/AptScreens/AptSpellStore.h"
#include "GameClient/SpellBookUI.h"

#include <algorithm>
#include <array>
#include <map>
#include <set>
#include <variant>

using namespace hudtest;

namespace
{
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

// a clip's content box in window pixels: its content through the global matrix (every viewport transform included)
void globalBox(AptCharacterInst *c, const AptStageMapping &m, float out[4])
{
	float x0, y0, x1, y1;
	REQUIRE(c->contentBounds(x0, y0, x1, y1));
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
}

// the section of a side bar frame's art (InGameSideCommandBar.apt's Frame: _middle, _top, _topbottom, _bottom) the clip stands in
std::string frameArtSection(const AptSpriteInst &s)
{
	std::string best;
	int bestFrame = -1;
	for (const char *l : { "_middle", "_top", "_topbottom", "_bottom" })
	{
		const int f = s.labelFrame(l);
		if (f >= 0 && f <= s.frame && f > bestFrame)
		{
			best = l;
			bestFrame = f;
		}
	}
	return best;
}

struct PalantirRig
{
	Rig rig;
	RecordingShellServices services;
	std::unique_ptr<InGameHud> hud;
	// `localName`: the player the HUD belongs to (Player_1 FactionMen, Player_2 FactionMordor)
	explicit PalantirRig(SharedWorld &s, const char *localName = "Player_1", const char *faction = "FactionMen") : rig(s, "map mp fall back 4p", faction)
	{
		Player *p = rig.game->players().findPlayerWithName(localName);
		REQUIRE(p != nullptr);
		rig.game->players().setLocalPlayer(p);
		rig.local = p;
		InGameHud::Config cfg{ *rig.game, *s.world, *s.mount->fs, services, rig.view, s.mouse, s.meta, nullptr };
		hud = std::make_unique<InGameHud>(cfg);
		std::string error;
		REQUIRE_MESSAGE(hud->boot(&error), error);
	}
	~PalantirRig() { hud.reset(); }
	void frames(int n)
	{
		for (int i = 0; i < n; ++i)
		{
			hud->update(0.033);
			rig.game->advance(0.033);
		}
	}
	AptSpriteInst *clip(const std::string &path)
	{
		AptCharacterInst *c = hud->apt().resolvePath(hud->apt().level(hud->palantir()->level()), path);
		return c ? c->asSprite() : nullptr;
	}
	// the label of the frame the clip stands on ("" when the frame carries none)
	std::string label(const std::string &path)
	{
		AptSpriteInst *s = clip(path);
		REQUIRE_MESSAGE(s != nullptr, path);
		for (const char *l : { "_blank", "_evenstar", "_ring", "_hide", "_show", "_single", "_double" })
		{
			if (s->labelFrame(l) >= 0 && s->labelFrame(l) <= s->frame)
			{
				int best = s->labelFrame(l);
				bool later = false;
				for (const char *m : { "_blank", "_evenstar", "_ring", "_hide", "_show", "_single", "_double" })
				{
					const int f = s->labelFrame(m);
					later = later || (f > best && f <= s->frame);
				}
				if (!later)
				{
					return l;
				}
			}
		}
		return std::string();
	}
	std::vector<AptRenderCommand> commands(const std::string &pathPart)
	{
		AptRenderList rl;
		hud->apt().buildRenderList(rl);
		std::vector<AptRenderCommand> out;
		for (const AptRenderCommand &c : rl.commands)
		{
			if (c.path.find(pathPart) != std::string::npos)
			{
				out.push_back(c);
			}
		}
		return out;
	}
	// whether the PlayerMagic button draws a bitmap fill of image `id`
	bool playerMagicDraws(int id)
	{
		for (const AptRenderCommand &c : commands("PalantirButtons.Buttons.PlayerMagic.ButtonClip"))
		{
			for (const AptRenderFill &f : c.fills)
			{
				if (f.imageId == id)
				{
					return true;
				}
			}
		}
		return false;
	}
	std::string templatePortrait(const Object &o)
	{
		const FieldValue *v = o.getTemplate()->findField("SelectPortrait");
		const std::string *s = v ? std::get_if<std::string>(v) : nullptr;
		return s ? *s : std::string();
	}
};
// The six outer frames stay visible while empty; their contents are removed.
void checkEmptyPanel(PalantirRig &h)
{
	AptPalantir *p = h.hud->palantir();
	REQUIRE(p);
	REQUIRE(h.clip("CommandButtons"));
	CHECK(h.clip("CommandButtons")->visible);
	CHECK(h.label("CommandButtons") == "_show");
	CHECK(h.hud->controlBar().palantirButtons().empty());
	std::map<std::string, std::string> framesByIndex;
	for (const AptPalantir::ButtonFrame &reported : p->buttonFrames())
	{
		std::string path = reported.path;
		if (path.rfind("_level", 0) == 0)
		{
			path = path.substr(path.find('.') + 1);
		}
		if (path.rfind("CommandButtons.", 0) == 0 && reported.index.size() == 1 && reported.index >= "0" && reported.index <= "5")
		{
			framesByIndex[reported.index] = path;
		}
	}
	REQUIRE(framesByIndex.size() == AptPalantir::kArcPositions);
	std::set<std::string> uniqueFrames;
	for (const auto &entry : framesByIndex)
	{
		uniqueFrames.insert(entry.second);
	}
	REQUIRE(uniqueFrames.size() == AptPalantir::kArcPositions);
	AptRenderList render;
	h.hud->apt().buildRenderList(render);
	for (int i = 0; i < AptPalantir::kArcPositions; ++i)
	{
		const std::string frame = framesByIndex.at(std::to_string(i));
		AptSpriteInst *outer = h.clip(frame);
		REQUIRE_MESSAGE(outer != nullptr, frame);
		CHECK(outer->visible);
		CHECK(h.clip(frame + ".content") == nullptr);
		const std::string content = "_level" + std::to_string(p->level()) + "." + frame + ".content";
		CHECK(p->imageFor(content + "_Image") == nullptr);
		CHECK(p->timerFor(content + "_Timer") == -1.0f);
		const std::string *count = h.hud->windows().aptText("APT:" + content + "_ProductionCount");
		CHECK((count == nullptr || *count == " "));
		for (const AptRenderCommand &command : render.commands)
		{
			CHECK(command.path.find(frame + ".content") == std::string::npos);
		}
	}
}

// the arc position's clip as the movie reported it (AptPalantir::buttonFrames: index "0" .. "5", the path without its _level prefix)
std::string arcFrame(PalantirRig &h, int position)
{
	for (const AptPalantir::ButtonFrame &reported : h.hud->palantir()->buttonFrames())
	{
		std::string path = reported.path;
		if (path.rfind("_level", 0) == 0)
		{
			path = path.substr(path.find('.') + 1);
		}
		if (path.rfind("CommandButtons.", 0) == 0 && reported.index == std::to_string(position))
		{
			return path;
		}
	}
	FAIL("no reported arc frame for position " << position);
	return std::string();
}

void checkPassiveContent(PalantirRig &h, const std::string &frame)
{
	AptSpriteInst *content = h.clip(frame + ".content");
	REQUIRE(content);
	const int passive = content->labelFrame("_static");
	const int next = content->labelFrame("_notReady");
	// tolerance: missing labels return -1; a valid timeline frame is nonnegative.
	REQUIRE(passive >= 0);
	// tolerance: the next named label bounds the passive state's timeline.
	REQUIRE(next > passive);
	// tolerance: allow animation within the passive state's timeline, not another state's frames.
	CHECK(content->frame >= passive);
	// tolerance: the next named label begins the following state.
	CHECK(content->frame < next);
	CHECK(content->visible);
}
} // namespace

TEST_CASE("hud2 palantir: nothing selected; the good side's PlayerMagic button shows the Evenstar, the command interface shows an empty portrait and the globe clip")
{
	if (!haveWorld("hud2 palantir evenstar"))
	{
		return;
	}
	PalantirRig h(shared());
	h.frames(60);
	AptPalantir *p = h.hud->palantir();
	REQUIRE(p != nullptr);
	// SetPlayerButtonsState("_evenstar") (RW 0x8001E8): PlayerMagic leaves its frame 0 `_blank` (no ButtonClip) for `_evenstar`, which places the shape of the
	// Evenstar clip; EnablePlayerMagicButton("1") (HUD-3, RW 0x6D5DEB) sends it to `_up`: the Evenstar art 205 of apt_Palantir_1, not the flat `_disabled` 162;
	// the movie's preview branch (not InGame) would show `_ring`
	CHECK(h.label("PalantirButtons.Buttons.PlayerMagic") == "_evenstar");
	CHECK(h.label("PalantirButtons.Buttons.Objectives") == "_evenstar");
	CHECK(h.playerMagicDraws(205));
	CHECK_FALSE(h.playerMagicDraws(162));
	// the command interface follows the control bar's context from the first update on (PalantirCommandUI 0x93085F), the portrait clip has no image
	checkEmptyPanel(h);
	CHECK(p->commandInterfaceShown());
	CHECK(h.label("CommandUI") == "_show");
	CHECK(p->portraitShown().empty());
	CHECK(p->imageForClip(p->portraitKey(), "") == nullptr);
	bool portraitClip = false, globeClip = false;
	for (const AptRenderCommand &c : h.commands("_level"))
	{
		portraitClip = portraitClip || (c.kind == AptRenderCommand::Kind::Placeholder && c.symbolName == "RenderImage" && c.path == p->portraitKey());
		globeClip = globeClip || (c.kind == AptRenderCommand::Kind::Placeholder && c.symbolName == "AptPalantir::RenderGlobe" && c.path.find("GlobeSwirlRender") != std::string::npos);
	}
	CHECK(portraitClip);
	// the live HUD reports the portrait's stop
	bool s760 = false;
	for (const std::string &l : h.hud->stops())
	{
		s760 = s760 || l.rfind("[S-760]", 0) == 0;
	}
	CHECK(s760);
	// the double frame's GlobeSwirlRender reaches frame 25 (its frame 10 stops only when _global.MinLOD is true; the movie writes extern.MinLOD)
	CHECK(globeClip);
	CHECK(p->callErrors().empty());
}

TEST_CASE("hud2 palantir: widescreen panels preserve proportions and edge anchors through resizing")
{
	if (!haveWorld("hud2 widescreen"))
	{
		return;
	}
	PalantirRig hud(shared());
	hud.frames(30);
	Object *builder = hud.rig.make("MenPorter", 2800, 1400);
	REQUIRE(builder != nullptr);
	hud.hud->input().ui().selectObject(builder->getID());
	hud.frames(40);
	REQUIRE(hud.hud->palantir()->sideBarShown());
	AptSpriteInst *frame = hud.clip("PalantirFrame");
	AptSpriteInst *side = hud.clip("SideCommandBar");
	REQUIRE(frame != nullptr);
	REQUIRE(side != nullptr);
	const AptMatrix originalFrame = frame->matrix;
	const AptMatrix originalSide = side->matrix;
	struct Viewport
	{
		int width, height;
		float correction;
	};
	for (const Viewport &viewport : { Viewport{ 1024, 768, 1.0f }, Viewport{ 1280, 720, 0.75f }, Viewport{ 2560, 1080, 0.5625f },
		Viewport{ 1280, 960, 1.0f }, Viewport{ 1280, 720, 0.75f } })
	{
		INFO(viewport.width, "x", viewport.height);
		hud.hud->setWindowSize(viewport.width, viewport.height);
		CHECK(frame->matrix.a == originalFrame.a);
		CHECK(frame->matrix.tx == originalFrame.tx);
		CHECK(side->matrix.a == originalSide.a);
		CHECK(side->matrix.tx == originalSide.tx);
		CHECK(frame->viewportTransform.a == viewport.correction);
		CHECK(frame->viewportTransform.tx == 0.0f);
		CHECK(side->viewportTransform.a == viewport.correction);
		CHECK(side->viewportTransform.tx == 1024.0f * (1.0f - viewport.correction));
		AptStageMapping mapping;
		mapping.windowW = (float)viewport.width;
		mapping.windowH = (float)viewport.height;
		CHECK(frame->viewportTransform.a * mapping.scaleX() == mapping.scaleY());
		float stageX, stageY, windowX, windowY;
		frame->viewportTransform.apply(0, 768, stageX, stageY);
		mapping.stageToWindow(stageX, stageY, windowX, windowY);
		CHECK(windowX == 0.0f);
		CHECK(windowY == (float)viewport.height);
		side->viewportTransform.apply(1024, 384, stageX, stageY);
		mapping.stageToWindow(stageX, stageY, windowX, windowY);
		CHECK(windowX == (float)viewport.width);
		CHECK(windowY == (float)viewport.height * 0.5f);
		for (const char *path : { "PalantirButtons.Buttons.Options", "SideCommandBar" })
		{
			INFO(path);
			AptButtonInst *button = firstButton(hud.hud->apt().resolvePath(hud.hud->apt().level(hud.hud->palantir()->level()), path));
			REQUIRE(button != nullptr);
			float left, top, right, bottom;
			REQUIRE(button->contentBounds(left, top, right, bottom));
			bool hit = false;
			for (int row = 1; row < 16 && !hit; ++row)
			{
				for (int column = 1; column < 16 && !hit; ++column)
				{
					button->globalMatrix().apply(left + (right - left) * (float)column / 16.0f, top + (bottom - top) * (float)row / 16.0f, stageX, stageY);
					if (hud.hud->apt().input().hitTestButtons(stageX, stageY) == button)
					{
						mapping.stageToWindow(stageX, stageY, windowX, windowY);
						hit = hud.hud->isOverGui((int)windowX, (int)windowY);
					}
				}
			}
			CHECK(hit);
		}
	}
}

// lane IOS-18 (OpenBFME, not retail): the HUD size option and the safe area. Each anchored group grows about its anchor, which sits at the safe area's
// corner; the hit test, the help box's place and the radar's square follow the same transform, so a press lands on what is drawn
TEST_CASE("hud2 palantir: the HUD size scales each group about its safe-area anchor and the hit test follows, landscape and portrait")
{
	if (!haveWorld("hud2 hud size"))
	{
		return;
	}
	PalantirRig hud(shared());
	hud.frames(30);
	Object *builder = hud.rig.make("MenPorter", 2800, 1400);
	REQUIRE(builder != nullptr);
	hud.hud->input().ui().selectObject(builder->getID());
	hud.frames(40);
	REQUIRE(hud.hud->palantir()->sideBarShown());
	AptPalantir *p = hud.hud->palantir();
	AptSpriteInst *frame = hud.clip("PalantirFrame");
	AptSpriteInst *side = hud.clip("SideCommandBar");
	REQUIRE(frame != nullptr);
	REQUIRE(side != nullptr);
	AptButtonInst *options = firstButton(hud.hud->apt().resolvePath(hud.hud->apt().level(p->level()), "PalantirButtons.Buttons.Options"));
	AptButtonInst *sideButton = firstButton(side);
	REQUIRE(options != nullptr);
	REQUIRE(sideButton != nullptr);
	struct Case
	{
		int width, height;
		float scale;
		float insets[4];
	};
	// the Duo's inner screen at half size (landscape, portrait), 4:3, and the landscape one with notch-like insets on both sides and a home indicator
	const Case cases[] = {
		{ 1335, 939, 1.0f, { 0, 0, 0, 0 } },
		{ 1335, 939, 1.25f, { 0, 0, 0, 0 } },
		{ 1335, 939, 1.5f, { 0, 0, 0, 0 } },
		{ 939, 1335, 1.0f, { 0, 0, 0, 0 } },
		{ 939, 1335, 1.25f, { 0, 0, 0, 0 } },
		{ 939, 1335, 1.5f, { 0, 0, 0, 0 } },
		{ 1024, 768, 1.0f, { 0, 0, 0, 0 } },
		{ 1024, 768, 1.25f, { 0, 0, 0, 0 } },
		{ 1335, 939, 1.25f, { 40, 0, 40, 20 } },
		{ 939, 1335, 1.25f, { 0, 40, 0, 20 } },
	};
	// a button's box in window pixels (its content through the global matrix: the viewport transform included)
	auto windowBox = [](AptButtonInst *b, const AptStageMapping &m, float out[4]) {
		float x0, y0, x1, y1;
		REQUIRE(b->contentBounds(x0, y0, x1, y1));
		out[0] = out[1] = 1e9f;
		out[2] = out[3] = -1e9f;
		const float xs[4] = { x0, x1, x0, x1 }, ys[4] = { y0, y0, y1, y1 };
		for (int i = 0; i < 4; ++i)
		{
			float sx, sy, wx, wy;
			b->globalMatrix().apply(xs[i], ys[i], sx, sy);
			m.stageToWindow(sx, sy, wx, wy);
			out[0] = std::min(out[0], wx);
			out[1] = std::min(out[1], wy);
			out[2] = std::max(out[2], wx);
			out[3] = std::max(out[3], wy);
		}
	};
	float base[2][4] = {}; // the Options button's and the side button's window box at 100 % in the current window (each size's first case)
	for (const Case &c : cases)
	{
		INFO(c.width, "x", c.height, " at ", c.scale, " insets ", c.insets[0], " ", c.insets[1], " ", c.insets[2], " ", c.insets[3]);
		AptPalantir::HudLayout layout;
		layout.scale = c.scale;
		std::copy(c.insets, c.insets + 4, layout.safeInsets);
		hud.hud->setWindowSize(c.width, c.height);
		hud.hud->setHudLayout(layout);
		hud.frames(2);
		AptStageMapping m;
		m.windowW = (float)c.width;
		m.windowH = (float)c.height;
		const float correction = std::min(1.0f, m.scaleY() / m.scaleX());
		const float vcorrection = c.width < c.height ? std::min(1.0f, m.scaleX() / m.scaleY()) : 1.0f;
		// the Palantir takes the option's factor in full at every size here; the side bar (lane IOS-27, above 100 %) the option's times the boost as far as
		// the safe area's height holds its block, never below 100 %
		const float left = p->hudGroupScale(AptPalantir::HudGroup::BottomLeft);
		const float right = p->hudGroupScale(AptPalantir::HudGroup::BottomRight);
		CHECK(left == c.scale);
		// tolerance: the side bar's factor is the fit to the safe area, between 100 % and the boosted option (its exact value depends on the bar's content)
		CHECK(right >= 1.0f);
		// tolerance: the fit to the safe area, as above (portrait: times 4 / 3, the landscape block's size on the screen)
		CHECK(right <= (c.scale > 1.0f ? c.scale * AptPalantir::kSideBarBoost * (c.width < c.height ? 1024.0f / 768.0f : 1.0f) : 1.0f) + 1e-5f);
		// tolerance: float products of the window mapping (the same factors multiplied in another order)
		CHECK(frame->viewportTransform.a == doctest::Approx(correction * left));
		CHECK(frame->viewportTransform.d == doctest::Approx(vcorrection * left)); // tolerance: float products of the window mapping
		CHECK(side->viewportTransform.a == doctest::Approx(correction * right));
		// the anchors: the stage's bottom-left corner at the safe area's bottom-left, the bottom-right at its bottom-right
		float sx, sy, wx, wy;
		frame->viewportTransform.apply(0, 768, sx, sy);
		m.stageToWindow(sx, sy, wx, wy);
		// tolerance: the anchor goes through two float mappings (stage <-> window); 1e-4 relative
		CHECK(wx == doctest::Approx(c.insets[0]).epsilon(1e-4));
		CHECK(wy == doctest::Approx((float)c.height - c.insets[3]).epsilon(1e-4)); // tolerance: the anchor goes through two float mappings
		side->viewportTransform.apply(1024, 768, sx, sy);
		m.stageToWindow(sx, sy, wx, wy);
		CHECK(wx == doctest::Approx((float)c.width - c.insets[2]).epsilon(1e-4)); // tolerance: the anchor goes through two float mappings
		CHECK(wy == doctest::Approx((float)c.height - c.insets[3]).epsilon(1e-4));
		// the side bar stays inside the safe area: every shown frame with its frame art, through its transforms (lane IOS-27: the frames move into columns)
		float box[4];
		for (int i = 0; i < p->sideBarCount(); ++i)
		{
			AptSpriteInst *f = hud.clip("SideCommandBar.ButtonSet.Button" + std::to_string(i));
			REQUIRE(f != nullptr);
			float fb[4];
			globalBox(f, m, fb);
			// tolerance: a frame's art may touch the safe edge; 0.01 px of float rounding
			CHECK(fb[1] >= c.insets[1] - 0.01f);
			CHECK(fb[0] >= c.insets[0] - 0.01f); // tolerance: a frame's art may touch the safe edge
			CHECK(fb[3] <= (float)c.height - c.insets[3] + 0.01f); // tolerance: a frame's art may touch the safe edge
		}
		// the buttons grow by the factor (against the same window at 100 %)
		for (int b = 0; b < 2; ++b)
		{
			AptButtonInst *button = b == 0 ? options : sideButton;
			const float k = b == 0 ? left : right;
			windowBox(button, m, box);
			if (c.scale == 1.0f)
			{
				std::copy(box, box + 4, base[b]);
			}
			else if (c.insets[0] == 0.0f && c.insets[1] == 0.0f && c.insets[2] == 0.0f && c.insets[3] == 0.0f && base[b][2] > base[b][0])
			{
				// tolerance: the box goes through the stage <-> window float mappings; 1e-3 relative
				CHECK((box[2] - box[0]) == doctest::Approx((base[b][2] - base[b][0]) * k).epsilon(1e-3));
				CHECK((box[3] - box[1]) == doctest::Approx((base[b][3] - base[b][1]) * k).epsilon(1e-3)); // tolerance: the box goes through the stage <-> window float mappings
			}
			// tolerance: a button may touch the safe edge; 0.01 px of float rounding
			CHECK(box[0] >= c.insets[0] - 0.01f);
			CHECK(box[2] <= (float)c.width - c.insets[2] + 0.01f); // tolerance: a button may touch the safe edge
			CHECK(box[1] >= c.insets[1] - 0.01f);
			CHECK(box[3] <= (float)c.height - c.insets[3] + 0.01f); // tolerance: a button may touch the safe edge
			// a press anywhere well inside the drawn box hits that button, the HUD takes it, and the HUD's own window-to-stage mapping agrees
			int hits = 0, probes = 0;
			for (int row = 1; row < 8; ++row)
			{
				for (int column = 1; column < 8; ++column)
				{
					const float wxp = box[0] + (box[2] - box[0]) * (float)column / 8.0f, wyp = box[1] + (box[3] - box[1]) * (float)row / 8.0f;
					float stx, sty;
					m.windowToStage(wxp, wyp, stx, sty);
					++probes;
					if (hud.hud->apt().input().hitTestButtons(stx, sty) == button && hud.hud->isOverGui((int)wxp, (int)wyp))
					{
						++hits;
					}
				}
			}
			// the box is the content's (a round button's corners are outside its Hit shape): most of it, never none
			// tolerance: a probe grid over the content box: a round button's corners are outside its Hit shape, so most probes, not all, hit it
			CHECK(hits * 2 >= probes);
		}
		// the help box keeps clear of the grown Palantir (as at 100 % in a 4:3 window: its left edge at the Palantir's right reach or beyond)
		AptCharacterInst *help = hud.hud->apt().resolvePath(hud.hud->apt().level(p->level()), "helpBox");
		REQUIRE(help != nullptr);
		// tolerance: the help box only ever moves right of where it was (0 at 100 % in 4:3)
		CHECK(help->viewportTransform.tx >= 0.0f);
		// the radar's square, where the device draws the map and a press moves the camera: the radar clip's box through the same transform
		float sq[4];
		if (hud.hud->radarSquare(sq))
		{
			// tolerance: the radar square is in whole pixels (InGameHud::radarSquare rounds through int); 1 px
			CHECK(sq[0] >= c.insets[0] - 1.0f);
			CHECK(sq[3] <= (float)c.height - c.insets[3] + 1.0f); // tolerance: the radar square is in whole pixels
			const float cx = (sq[0] + sq[2]) * 0.5f, cy = (sq[1] + sq[3]) * 0.5f;
			CHECK(hud.hud->isOverGui((int)cx, (int)cy));
		}
	}
	// back to the retail layout: exactly the factors before the option (hud2 palantir: widescreen* keeps the values)
	hud.hud->setWindowSize(1280, 720);
	hud.hud->setHudLayout(AptPalantir::HudLayout());
	CHECK(frame->viewportTransform.a == 0.75f);
	CHECK(frame->viewportTransform.tx == 0.0f);
	CHECK(frame->viewportTransform.d == 1.0f);
	CHECK(frame->viewportTransform.ty == 0.0f);
	CHECK(side->viewportTransform.tx == 1024.0f * (1.0f - 0.75f));
	CHECK(p->hudGroupScale(AptPalantir::HudGroup::BottomLeft) == 1.0f);
	CHECK(p->hudGroupScale(AptPalantir::HudGroup::BottomRight) == 1.0f);
}

// lane IOS-27 (OpenBFME presentation, not retail): above 100 % the side bar's buttons are at the HUD size times AptPalantir::kSideBarBoost. Landscape: a
// block in the safe area's bottom-right corner; more than kSideBarMaxRows buttons wrap into two columns (column-major, the columns' last buttons on the
// bottom row), each with its own frame ends. Portrait: one column from the top of the right edge, below the message lines. The hit test, the touch
// layer's button and the held finger's help follow the moved frames; at 100 % the retail column comes back; hidden, the bar slides off the screen
TEST_CASE("hud2 palantir: above 100 % the side bar wraps into two columns in landscape, one top column in portrait, and the hit test follows")
{
	if (!haveWorld("hud2 side bar columns"))
	{
		return;
	}
	struct Builder
	{
		const char *faction, *templateName;
		int buttons; // the builder's build list (measured: the side bar's shown frames)
	};
	for (const Builder &b : { Builder{ "FactionMen", "MenPorter", 12 }, Builder{ "FactionDwarves", "DwarvenPorter", 9 } })
	{
		INFO(b.faction);
		PalantirRig hud(shared(), "Player_1", b.faction);
		hud.frames(30);
		Object *builder = hud.rig.make(b.templateName, 2800, 1400);
		REQUIRE(builder != nullptr);
		hud.hud->input().ui().selectObject(builder->getID());
		hud.frames(40);
		AptPalantir *p = hud.hud->palantir();
		REQUIRE(p->sideBarShown());
		const int n = p->sideBarCount();
		CHECK(n == b.buttons);
		std::vector<AptSpriteInst *> frames;
		std::vector<AptButtonInst *> buttons;
		for (int i = 0; i < n; ++i)
		{
			frames.push_back(hud.clip("SideCommandBar.ButtonSet.Button" + std::to_string(i)));
			REQUIRE(frames.back() != nullptr);
			buttons.push_back(firstButton(frames.back()));
			REQUIRE(buttons.back() != nullptr);
		}
		AptSpriteInst *set = hud.clip("SideCommandBar.ButtonSet");
		REQUIRE(set != nullptr);
		struct Case
		{
			int width, height;
			float scale;
			float insets[4];
			float reserve; // HudLayout::topRightReserve: the message lines' band (window pixels)
		};
		const Case cases[] = {
			{ 1335, 939, 1.15f, { 0, 0, 0, 0 }, 0 },
			{ 1335, 939, 1.25f, { 0, 0, 0, 0 }, 0 },
			{ 1335, 939, 1.5f, { 0, 0, 0, 0 }, 0 },
			{ 939, 1335, 1.15f, { 0, 0, 0, 0 }, 0 },
			{ 939, 1335, 1.25f, { 0, 0, 0, 0 }, 0 },
			{ 939, 1335, 1.5f, { 0, 0, 0, 0 }, 0 },
			{ 1335, 939, 1.25f, { 40, 0, 40, 20 }, 120 },
			{ 939, 1335, 1.25f, { 0, 40, 0, 20 }, 120 },
		};
		for (const Case &c : cases)
		{
			INFO(c.width, "x", c.height, " at ", c.scale, " insets ", c.insets[0], " ", c.insets[1], " ", c.insets[2], " ", c.insets[3], " reserve ", c.reserve);
			const bool portrait = c.width < c.height;
			const int rows = portrait ? n : (n + 1) / 2;
			AptStageMapping m;
			m.windowW = (float)c.width;
			m.windowH = (float)c.height;
			hud.hud->setWindowSize(c.width, c.height);
			// the retail column at 100 % in this window: the buttons' size there
			hud.hud->setHudLayout(AptPalantir::HudLayout());
			hud.frames(2);
			CHECK(p->sideBarColumns() == 1);
			float base[4];
			globalBox(buttons[0], m, base);
			AptPalantir::HudLayout layout;
			layout.scale = c.scale;
			std::copy(c.insets, c.insets + 4, layout.safeInsets);
			layout.topRightReserve = c.reserve;
			hud.hud->setHudLayout(layout);
			hud.frames(2);
			CHECK(p->sideBarColumns() == (portrait ? 1 : 2));
			// the bar fits at the boosted size in each of these windows; portrait's at the landscape block's size on the screen (1335 / 939 > 4 / 3: 4 / 3)
			const float k = c.scale * AptPalantir::kSideBarBoost * (portrait ? 1024.0f / 768.0f : 1.0f);
			// tolerance: the same float product in another order
			CHECK(p->hudGroupScale(AptPalantir::HudGroup::BottomRight) == doctest::Approx(k).epsilon(1e-6));
			std::vector<std::array<float, 4>> box(n), art(n);
			for (int i = 0; i < n; ++i)
			{
				globalBox(buttons[i], m, box[i].data());
				globalBox(frames[i], m, art[i].data());
			}
			// the buttons grow by the factor (against the retail column in the same window)
			// tolerance: the boxes go through the stage <-> window float mappings; 1e-3 relative
			CHECK((box[0][2] - box[0][0]) == doctest::Approx((base[2] - base[0]) * p->hudGroupScale(AptPalantir::HudGroup::BottomRight)).epsilon(1e-3));
			const float pitch = box[1][1] - box[0][1];
			CHECK(pitch > box[0][3] - box[0][1]); // tolerance: the rows' pitch is more than a button's height (the frame between them)
			for (int i = 0; i < n; ++i)
			{
				INFO("button ", i);
				const bool second = !portrait && i >= rows;
				const int first = second ? rows : 0;
				// one x per column, the second column one pitch right of the first (the frames are square), touching the safe area's right edge
				// tolerance: float mappings of the same transforms; 0.01 px
				CHECK(box[i][0] == doctest::Approx(box[first][0]).epsilon(1e-4));
				if (second)
				{
					// tolerance: float mappings of the same transforms
					CHECK(box[i][0] - box[0][0] == doctest::Approx(pitch).epsilon(1e-3));
				}
				// column-major, one pitch apart, and both columns end on the bottom row
				if (i > first)
				{
					// tolerance: float mappings of the same transforms
					CHECK(box[i][1] - box[i - 1][1] == doctest::Approx(pitch).epsilon(1e-3));
				}
				// the frame art: each column its own ends
				const int inColumn = i - first, count = second ? n - rows : rows;
				AptSpriteInst *frameArt = hud.clip("SideCommandBar.ButtonSet.Button" + std::to_string(i) + ".Frame");
				REQUIRE(frameArt != nullptr);
				CHECK(frameArtSection(*frameArt) == (inColumn == 0 ? "_top" : (inColumn == count - 1 ? "_bottom" : "_middle")));
				// inside the safe area
				// tolerance: the art may touch the safe edge; 0.01 px of float rounding
				CHECK(art[i][0] >= c.insets[0] - 0.01f);
				CHECK(art[i][1] >= c.insets[1] - 0.01f); // tolerance: the art may touch the safe edge
				CHECK(art[i][2] <= (float)c.width - c.insets[2] + 0.01f); // tolerance: the art may touch the safe edge
				CHECK(art[i][3] <= (float)c.height - c.insets[3] + 0.01f); // tolerance: the art may touch the safe edge
				// a press well inside the drawn button hits it (the HUD takes it), and a finger there is on it
				int hits = 0, probes = 0;
				for (int row = 1; row < 8; ++row)
				{
					for (int column = 1; column < 8; ++column)
					{
						const float wxp = box[i][0] + (box[i][2] - box[i][0]) * (float)column / 8.0f, wyp = box[i][1] + (box[i][3] - box[i][1]) * (float)row / 8.0f;
						float stx, sty;
						m.windowToStage(wxp, wyp, stx, sty);
						++probes;
						if (hud.hud->apt().input().hitTestButtons(stx, sty) == buttons[i] && hud.hud->isOverGui((int)wxp, (int)wyp))
						{
							++hits;
						}
					}
				}
				// tolerance: a probe grid over the content box: a round button's corners are outside its Hit shape, so most probes, not all, hit it
				CHECK(hits * 2 >= probes);
				const InGameHud::TouchButton t = hud.hud->touchButtonAt((int)((box[i][0] + box[i][2]) * 0.5f), (int)((box[i][1] + box[i][3]) * 0.5f));
				CHECK(t.kind == InGameHud::TouchButton::Movie);
				const std::string framePath = "_level" + std::to_string(p->level()) + ".SideCommandBar.ButtonSet.Button" + std::to_string(i) + ".";
				CHECK(t.target.compare(0, framePath.size(), framePath) == 0);
			}
			// a held finger (IOS-21's touch help) on the first and last button of each column shows that button's help, and lifting presses nothing
			std::vector<HelpDrawOp> ops;
			hud.hud->helpBoxRender(400.0f, 500.0f, 360.0f, 40.0f, ops); // the device's render samples the content width (state 1)
			hud.hud->setTouchHelp(true);
			for (int i : portrait ? std::vector<int>{ 0, n - 1 } : std::vector<int>{ 0, rows - 1, rows, n - 1 })
			{
				INFO("held on button ", i);
				hud.hud->mouseMove((int)((box[i][0] + box[i][2]) * 0.5f), (int)((box[i][1] + box[i][3]) * 0.5f));
				hud.hud->holdHelp(true);
				hud.frames(3);
				CHECK(hud.hud->helpBox().isShown());
				CHECK(hud.hud->helpBox().provider().bar == 1); // the side bar's help (InGameHudHud6.cpp: a content slot of the side bar)
				const std::string hover = "Palantir/SideCommandBar/ButtonSet/Button" + std::to_string(i) + "/";
				CHECK(hud.hud->windows().hoverPath().compare(0, hover.size(), hover) == 0);
				hud.hud->holdHelp(false);
				hud.hud->mouseMove(c.width / 2, 60);
				hud.frames(10);
				CHECK_FALSE(hud.hud->input().ui().isPlacing());
			}
			hud.hud->setTouchHelp(false);
			// landscape: the columns' last buttons share the bottom row and the block's corner is the safe area's bottom-right. Portrait: the column's top
			// is the safe area's or the message lines' bottom, its right the safe area's
			float right = -1e9f, bottom = -1e9f, top = 1e9f;
			for (int i = 0; i < n; ++i)
			{
				right = std::max(right, art[i][2]);
				bottom = std::max(bottom, art[i][3]);
				top = std::min(top, art[i][1]);
			}
			// tolerance: the anchor goes through two float mappings (stage <-> window); 1e-4 relative
			CHECK(right == doctest::Approx((float)c.width - c.insets[2]).epsilon(1e-4));
			if (portrait)
			{
				// tolerance: as above
				CHECK(top == doctest::Approx(std::max(c.insets[1], c.reserve)).epsilon(1e-4));
				CHECK(bottom <= (float)c.height - c.insets[3] + 0.01f); // tolerance: the art may touch the safe edge
			}
			else
			{
				// tolerance: float mappings of the same transforms
				CHECK(box[rows - 1][1] == doctest::Approx(box[n - 1][1]).epsilon(1e-4));
				CHECK(bottom == doctest::Approx((float)c.height - c.insets[3]).epsilon(1e-4)); // tolerance: as above
			}
		}
		// back to 100 %: the retail column, no transform left on its frames, the movie's own frame ends
		hud.hud->setWindowSize(1335, 939);
		hud.hud->setHudLayout(AptPalantir::HudLayout());
		hud.frames(2);
		CHECK(p->sideBarColumns() == 1);
		CHECK(p->hudGroupScale(AptPalantir::HudGroup::BottomRight) == 1.0f);
		CHECK(set->viewportTransform.tx == 0.0f);
		for (int i = 0; i < n; ++i)
		{
			INFO("button ", i);
			CHECK(frames[i]->viewportTransform.tx == 0.0f);
			CHECK(frames[i]->viewportTransform.ty == 0.0f);
			AptSpriteInst *frameArt = hud.clip("SideCommandBar.ButtonSet.Button" + std::to_string(i) + ".Frame");
			CHECK(frameArtSection(*frameArt) == (i == 0 ? "_top" : (i == n - 1 ? "_bottom" : "_middle")));
		}
		// hidden at 125 %: the bar slides out with both columns
		AptPalantir::HudLayout layout;
		layout.scale = 1.25f;
		hud.hud->setHudLayout(layout);
		hud.frames(2);
		REQUIRE(p->sideBarColumns() == 2);
		hud.hud->input().ui().deselectAll();
		hud.frames(60);
		CHECK_FALSE(p->sideBarShown());
		AptStageMapping m;
		m.windowW = 1335.0f;
		m.windowH = 939.0f;
		for (int i = 0; i < n; ++i)
		{
			float hidden[4];
			globalBox(frames[i], m, hidden);
			CHECK(hidden[0] >= 1335.0f); // tolerance: off screen is anything right of the window's edge
		}
	}
}

// lane IOS-27 (OpenBFME presentation, not retail): the spell book hangs from the Palantir's top-left with the Palantir's factor, and fits on its own under the
// safe area's top: a long vine (every power bought) no longer holds the whole Palantir at 100 %. A held finger on a power shows its help and presses nothing
TEST_CASE("hud2 palantir: the spell book grows with the Palantir, fits under the safe area's top, and a held finger shows a power's help")
{
	if (!haveWorld("hud2 spell book hud size"))
	{
		return;
	}
	PalantirRig hud(shared(), "Player_1", "FactionDwarves");
	auto context = hud.hud->enterContext();
	hud.frames(30);
	AptPalantir *p = hud.hud->palantir();
	std::string error;
	REQUIRE_MESSAGE(hud.hud->openSpellStore(&error), error);
	hud.frames(40);
	AptSpellStore *store = hud.hud->spellStore();
	REQUIRE(store != nullptr);
	REQUIRE(store->model().buttons().size() == 12);
	REQUIRE(store->model().buttons()[1].scienceName == "SCIENCE_Rebuild"); // the Dwarves' store: Rebuild is its second button
	REQUIRE(store->click(1));
	hud.hud->closeSpellStore();
	hud.frames(40);
	REQUIRE(p->spellSlotButton(0) == 1); // the first slot shows the spell book's second button, Rebuild (the set's order is the store's)
	AptSpriteInst *book = hud.clip(p->spellBookPath());
	AptSpriteInst *frame = hud.clip("PalantirFrame");
	REQUIRE(book != nullptr);
	REQUIRE(frame != nullptr);
	AptButtonInst *spell = firstButton(hud.clip(p->spellBookPath() + ".Spell1"));
	REQUIRE(spell != nullptr);
	AptStageMapping m;
	m.windowW = 1335.0f;
	m.windowH = 939.0f;
	hud.hud->setWindowSize(1335, 939);
	hud.hud->setHudLayout(AptPalantir::HudLayout());
	hud.frames(2);
	float base[4];
	globalBox(spell, m, base);
	for (float scale : { 1.15f, 1.25f, 1.5f })
	{
		INFO("one power at ", scale);
		AptPalantir::HudLayout layout;
		layout.scale = scale;
		layout.safeInsets[3] = 20.0f;
		hud.hud->setHudLayout(layout);
		hud.frames(2);
		// one power: the book takes the Palantir's factor and transform (it hangs from the Palantir as at 100 %)
		CHECK(p->hudGroupScale(AptPalantir::HudGroup::BottomLeft) == scale);
		CHECK(p->spellBookScale() == scale);
		// tolerance: the same transform computed about the book's foot instead of the corner (float products)
		CHECK(book->viewportTransform.a == doctest::Approx(frame->viewportTransform.a));
		CHECK(book->viewportTransform.d == doctest::Approx(frame->viewportTransform.d)); // tolerance: as above
		CHECK(book->viewportTransform.tx == doctest::Approx(frame->viewportTransform.tx).epsilon(1e-4)); // tolerance: as above
		CHECK(book->viewportTransform.ty == doctest::Approx(frame->viewportTransform.ty).epsilon(1e-4)); // tolerance: as above
		float box[4];
		globalBox(spell, m, box);
		// tolerance: the box goes through the stage <-> window float mappings; 1e-3 relative
		CHECK((box[2] - box[0]) == doctest::Approx((base[2] - base[0]) * scale).epsilon(1e-3));
	}
	// held: the power's help (the spell book's provider, bar 3), shown at once; nothing pressed (no target wanted)
	float box[4];
	globalBox(spell, m, box);
	const int cx = (int)((box[0] + box[2]) * 0.5f), cy = (int)((box[1] + box[3]) * 0.5f);
	const InGameHud::TouchButton t = hud.hud->touchButtonAt(cx, cy);
	CHECK(t.kind == InGameHud::TouchButton::Movie);
	CHECK(t.target.find(".SpellBookUI.Spell1") != std::string::npos);
	std::vector<HelpDrawOp> ops;
	hud.hud->helpBoxRender(400.0f, 500.0f, 360.0f, 40.0f, ops); // the device's render samples the content width (state 1)
	hud.hud->setTouchHelp(true);
	hud.hud->mouseMove(cx, cy);
	hud.frames(10);
	CHECK_FALSE(hud.hud->helpBox().isShown());
	hud.hud->holdHelp(true);
	hud.frames(3);
	CHECK(hud.hud->helpBox().isShown());
	CHECK(hud.hud->helpBox().provider().bar == 3);
	REQUIRE(hud.hud->helpBox().provider().button != nullptr);
	CHECK(hud.hud->helpBox().provider().button->m_name.find("Rebuild") != std::string::npos);
	hud.hud->holdHelp(false);
	hud.frames(10);
	CHECK_FALSE(hud.hud->helpBox().isShown());
	CHECK_FALSE(hud.hud->spellBar().targeting());
	hud.hud->setTouchHelp(false);

	// every power: the vine reaches the stage's top at 100 %. The Palantir keeps the option's factor; the book is as large as fits under the top
	hud.rig.local->science().addSciencePurchasePoints(200);
	REQUIRE_MESSAGE(hud.hud->openSpellStore(&error), error);
	hud.frames(40);
	store = hud.hud->spellStore();
	REQUIRE(store != nullptr);
	for (int pass = 0; pass < 5; ++pass)
	{
		for (int i = 0; i < 12; ++i)
		{
			store->click(i);
		}
		hud.frames(4);
	}
	hud.hud->closeSpellStore();
	hud.frames(60);
	for (int i = 0; i < 12; ++i)
	{
		REQUIRE(p->spellSlotButton(i) == i); // every power bought: each slot shows its own button
	}
	for (float scale : { 1.0f, 1.25f, 1.5f })
	{
		for (auto size : { std::pair<int, int>{ 1335, 939 }, std::pair<int, int>{ 939, 1335 } })
		{
			INFO("every power at ", scale, " in ", size.first, "x", size.second);
			AptPalantir::HudLayout layout;
			layout.scale = scale;
			layout.safeInsets[3] = 20.0f;
			hud.hud->setWindowSize(size.first, size.second);
			hud.hud->setHudLayout(layout);
			hud.frames(2);
			CHECK(p->hudGroupScale(AptPalantir::HudGroup::BottomLeft) == scale);
			// tolerance: the book's factor is the fit under the top, at most the Palantir's (its exact value depends on the vine's art)
			CHECK(p->spellBookScale() <= scale);
			AptStageMapping mm;
			mm.windowW = (float)size.first;
			mm.windowH = (float)size.second;
			float top = 1e9f;
			for (int i = 0; i < 12; ++i)
			{
				AptButtonInst *b = firstButton(hud.clip(p->spellBookPath() + ".Spell" + std::to_string(i + 1)));
				REQUIRE(b != nullptr);
				float bb[4];
				globalBox(b, mm, bb);
				top = std::min(top, bb[1]);
			}
			// tolerance: the top power may touch the window's top; 0.01 px of float rounding
			CHECK(top >= -0.01f);
		}
	}
	(void)context;
}

TEST_CASE("hud2 palantir: a radar ping keeps its supplied stage position under the HUD size and a portrait window")
{
	if (!haveWorld("hud2 hud size radar pings"))
	{
		return;
	}
	PalantirRig hud(shared());
	hud.frames(30);
	AptSpriteInst *pings = hud.clip("RadarPings.PingStage");
	AptSpriteInst *radarPings = hud.clip("RadarPings");
	REQUIRE(pings != nullptr);
	REQUIRE(radarPings != nullptr);
	REQUIRE(hud.hud->palantir()->createRadarPing(77, "PingAttack"));
	hud.frames(1);
	AptCharacterInst *ping = pings->children().back();
	for (float scale : { 1.0f, 1.25f, 1.5f })
	{
		for (auto size : { std::pair<int, int>{ 1335, 939 }, std::pair<int, int>{ 939, 1335 } })
		{
			INFO(size.first, "x", size.second, " at ", scale);
			AptPalantir::HudLayout layout;
			layout.scale = scale;
			hud.hud->setWindowSize(size.first, size.second);
			hud.hud->setHudLayout(layout);
			// a stage point inside the radar as drawn (its 128-unit centre through the RadarPings transform)
			float stageX, stageY;
			radarPings->viewportTransform.apply(128, 640, stageX, stageY);
			REQUIRE(hud.hud->palantir()->moveRadarPing(77, stageX, stageY));
			float actualX, actualY;
			ping->globalMatrix().apply(0, 0, actualX, actualY);
			// tolerance: the ping's stage position goes through the transform and back (float division)
			CHECK(actualX == doctest::Approx(stageX));
			CHECK(actualY == doctest::Approx(stageY)); // tolerance: the ping's stage position goes through the transform and back
		}
	}
}

TEST_CASE("hud2 palantir: widescreen radar pings retain their supplied stage position")
{
	if (!haveWorld("hud2 widescreen radar pings"))
	{
		return;
	}
	PalantirRig hud(shared());
	hud.frames(30);
	AptSpriteInst *radarPings = hud.clip("RadarPings");
	AptSpriteInst *pings = hud.clip("RadarPings.PingStage");
	REQUIRE(radarPings != nullptr);
	REQUIRE(pings != nullptr);
	const size_t before = pings->children().size();
	REQUIRE(hud.hud->palantir()->createRadarPing(123, "PingAttack"));
	hud.frames(1);
	REQUIRE(pings->children().size() == before + 1);
	AptCharacterInst *ping = pings->children().back();
	for (int width : { 1024, 2048, 4096, 1024 })
	{
		hud.hud->setWindowSize(width, 768);
		const float stageX = 128.0f * radarPings->viewportTransform.a;
		REQUIRE(hud.hud->palantir()->moveRadarPing(123, stageX, 640));
		float actualX, actualY;
		ping->globalMatrix().apply(0, 0, actualX, actualY);
		CHECK(actualX == stageX);
		CHECK(actualY == 640.0f);
	}
}

TEST_CASE("hud2 palantir: an evil side's PlayerMagic button shows the Ring (the power cap state is Living World only and not sent)")
{
	if (!haveWorld("hud2 palantir ring"))
	{
		return;
	}
	PalantirRig h(shared(), "Player_2");
	REQUIRE(h.rig.local->getPlayerTemplate() != nullptr);
	REQUIRE(h.rig.local->getPlayerTemplate()->m_evil);
	h.frames(60);
	CHECK(h.label("PalantirButtons.Buttons.PlayerMagic") == "_ring");
	CHECK(h.label("PalantirButtons.Buttons.Objectives") == "_ring");
	CHECK(h.playerMagicDraws(219)); // the Ring's `_up` art
	CHECK_FALSE(h.playerMagicDraws(176));
	CHECK(h.hud->palantir()->callErrors().empty());
}

TEST_CASE("hud2 palantir: a selected unit and a selected building show their SelectPortrait in CommandUI.Portrait; a mixed selection the side's multi portrait")
{
	if (!haveWorld("hud2 palantir portrait"))
	{
		return;
	}
	PalantirRig h(shared());
	const Coord3D c = h.rig.freeSpot(2800, 1400, 200.0f);
	Object *b = h.rig.make("GondorBarracks", c.x, c.y);
	Object *u = h.rig.make("GondorFighterHorde", c.x + 250.0f, c.y);
	REQUIRE(b != nullptr);
	REQUIRE(u != nullptr);
	h.rig.lookAt({ c.x, c.y, 0 });
	h.frames(20);
	AptPalantir *p = h.hud->palantir();

	// a unit
	h.hud->input().ui().selectObject(u->getID());
	h.frames(10);
	const std::string unitPortrait = h.templatePortrait(*u);
	REQUIRE(!unitPortrait.empty());
	CHECK(p->portraitShown() == unitPortrait);
	const AptPalantir::NativeImage *img = p->imageForClip(p->portraitKey(), "");
	REQUIRE(img != nullptr);
	CHECK(img->image == unitPortrait);
	CHECK(p->commandInterfaceShown());

	// Deselecting a unit must retain the six empty frames and their parent panel.
	h.hud->input().ui().deselectAll(false);
	h.frames(20);
	checkEmptyPanel(h);

	// a building
	h.hud->input().ui().deselectAll(false);
	h.hud->input().ui().selectObject(b->getID());
	h.frames(10);
	const std::string buildingPortrait = h.templatePortrait(*b);
	REQUIRE(!buildingPortrait.empty());
	CHECK(buildingPortrait != unitPortrait);
	CHECK(p->portraitShown() == buildingPortrait);
	REQUIRE(p->imageForClip(p->portraitKey(), "") != nullptr);
	CHECK(p->imageForClip(p->portraitKey(), "")->image == buildingPortrait);

	// both: different portraits, the controlling player's template MultiSelectionPortrait, else "MultiPortrait" (RW 0x92FF0F .. 0x92FF47)
	h.hud->input().ui().selectObject(u->getID());
	h.frames(10);
	REQUIRE(h.hud->input().ui().getSelectCount() == 2);
	const std::string multi = h.rig.local->getPlayerTemplate()->m_multiSelectionPortrait;
	CHECK(p->portraitShown() == (multi.empty() ? std::string("MultiPortrait") : multi));

	// nothing: the portrait is cleared, the interface stays shown
	h.hud->input().ui().deselectAll(false);
	h.frames(10);
	CHECK(p->portraitShown().empty());
	CHECK(p->imageForClip(p->portraitKey(), "") == nullptr);
	CHECK(p->commandInterfaceShown());
	checkEmptyPanel(h);
	// HUD-1's command buttons retry CreateContent / SetState until their clips' frames define them; the calls of this lane never fail
	for (const std::string &e : p->callErrors())
	{
		CHECK_MESSAGE((e.find("CommandInterface") == std::string::npos && e.find("SetPlayer") == std::string::npos), e);
	}
}

TEST_CASE("hud2 palantir: passive contents are removed on context changes, deselection and selected-unit destruction")
{
	if (!haveWorld("hud2 palantir passive context"))
	{
		return;
	}
	PalantirRig h(shared());
	h.frames(30);
	AptPalantir *p = h.hud->palantir();
	REQUIRE(p);
	checkEmptyPanel(h);
	CHECK_FALSE(p->rankInterfaceShown());

	const Coord3D c = h.rig.freeSpot(2800, 1400, 250.0f);
	Object *boromir = h.rig.make("GondorBoromir", c.x, c.y);
	REQUIRE(boromir);
	ExperienceTracker *xp = boromir->getExperienceTracker();
	REQUIRE(xp);
	REQUIRE(xp->isTrainable());
	xp->gainLevels(20, false);
	h.hud->input().ui().selectObject(boromir->getID());
	h.frames(10);
	REQUIRE(p->rankInterfaceShown());

	std::vector<int> passiveSlots;
	for (const ControlBarButton &button : h.hud->controlBar().palantirButtons())
	{
		if (button.button && button.button->hasOption(COMMAND_OPTION_NONPRESSABLE))
		{
			passiveSlots.push_back(button.position);
		}
	}
	REQUIRE_FALSE(passiveSlots.empty());
	for (int slot : passiveSlots)
	{
		// tolerance: the passive button's position must fit the six-frame arc table before deriving its clip path.
		REQUIRE((slot >= 0 && slot < AptPalantir::kArcPositions));
		const std::string frame = arcFrame(h, slot);
		checkPassiveContent(h, frame);
		const std::string content = "_level" + std::to_string(p->movieLevel()) + "." + frame + ".content";
		REQUIRE(p->imageFor(content + "_Image") != nullptr);
	}

	auto checkOldPassiveSlotsAreEmpty = [&] {
		AptRenderList render;
		h.hud->apt().buildRenderList(render);
		for (int slot : passiveSlots)
		{
			const bool occupied = std::any_of(h.hud->controlBar().palantirButtons().begin(), h.hud->controlBar().palantirButtons().end(),
				[slot](const ControlBarButton &button) { return button.position == slot; });
			if (occupied)
			{
				continue;
			}
			const std::string frame = arcFrame(h, slot);
			const std::string content = "_level" + std::to_string(p->movieLevel()) + "." + frame + ".content";
			CHECK(h.clip(frame + ".content") == nullptr);
			CHECK(p->imageFor(content + "_Image") == nullptr);
			CHECK(p->timerFor(content + "_Timer") == -1.0f);
			for (const AptRenderCommand &command : render.commands)
			{
				CHECK(command.path.find(frame + ".content") == std::string::npos);
			}
		}
	};

	Object *secondHero = h.rig.make("GondorAragornMP", c.x + 250.0f, c.y);
	REQUIRE(secondHero);
	ExperienceTracker *secondXp = secondHero->getExperienceTracker();
	REQUIRE(secondXp);
	REQUIRE(secondXp->isTrainable());
	secondXp->gainLevels(20, false);
	h.hud->input().ui().deselectAll(false);
	h.hud->input().ui().selectObject(secondHero->getID());
	h.frames(10);
	const PalantirCommandUI::RankInfo expectedRank = PalantirCommandUI::rankInfo(h.hud->input().context(), *secondHero);
	REQUIRE(expectedRank.type == 0);
	CHECK(expectedRank.rank == secondXp->getRank());
	CHECK(p->rankInterfaceShown());
	CHECK(p->rankProgressShown() == expectedRank.progress);
	checkOldPassiveSlotsAreEmpty();

	h.hud->input().ui().deselectAll(false);
	h.hud->input().ui().selectObject(boromir->getID());
	h.frames(10);
	REQUIRE(p->rankInterfaceShown());
	for (int slot : passiveSlots)
	{
		const auto button = std::find_if(h.hud->controlBar().palantirButtons().begin(), h.hud->controlBar().palantirButtons().end(),
			[slot](const ControlBarButton &candidate) { return candidate.position == slot; });
		REQUIRE(button != h.hud->controlBar().palantirButtons().end());
		REQUIRE(button->button);
		CHECK(button->button->hasOption(COMMAND_OPTION_NONPRESSABLE));
		const std::string frame = arcFrame(h, slot);
		checkPassiveContent(h, frame);
	}
	h.hud->input().ui().deselectAll(false);
	h.frames(10);
	checkEmptyPanel(h);
	CHECK_FALSE(p->rankInterfaceShown());

	Object *fighter = h.rig.make("GondorFighter", c.x + 250.0f, c.y);
	REQUIRE(fighter);
	h.hud->input().ui().deselectAll(false);
	h.hud->input().ui().selectObject(fighter->getID());
	h.frames(10);
	// (the rank interface's own rules are test_hud2_palantir's rank cases; this case checks only that no passive content is left)
	for (const ControlBarButton &button : h.hud->controlBar().palantirButtons())
	{
		CHECK_FALSE((button.button && button.button->hasOption(COMMAND_OPTION_NONPRESSABLE)));
	}
	checkOldPassiveSlotsAreEmpty();

	h.hud->input().ui().deselectAll(false);
	h.frames(10);
	checkEmptyPanel(h);
	CHECK_FALSE(p->rankInterfaceShown());

	h.hud->input().ui().selectObject(boromir->getID());
	h.frames(5);
	REQUIRE(boromir->getID() == h.hud->controlBar().sourceObject());
	REQUIRE(p->rankInterfaceShown());
	for (int slot : passiveSlots)
	{
		const auto button = std::find_if(h.hud->controlBar().palantirButtons().begin(), h.hud->controlBar().palantirButtons().end(),
			[slot](const ControlBarButton &candidate) { return candidate.position == slot; });
		REQUIRE(button != h.hud->controlBar().palantirButtons().end());
		REQUIRE(button->button);
		CHECK(button->button->hasOption(COMMAND_OPTION_NONPRESSABLE));
		const std::string frame = arcFrame(h, slot);
		checkPassiveContent(h, frame);
		const std::string content = "_level" + std::to_string(p->movieLevel()) + "." + frame + ".content";
		CHECK(p->imageFor(content + "_Image") != nullptr);
	}
	const ObjectID boromirId = boromir->getID();
	h.rig.logic().destroyObject(boromir);
	h.frames(5);
	CHECK(h.rig.logic().findObjectByID(boromirId) == nullptr);
	CHECK_FALSE(p->rankInterfaceShown());
	checkEmptyPanel(h);
}

TEST_CASE("stop S-760: the Palantir portrait reports the branches it does not port")
{
	const std::vector<std::string> stops = PalantirCommandUI::acceptanceStops();
	REQUIRE(stops.size() == 1);
	CHECK(stops[0].rfind("[S-760]", 0) == 0);
}

TEST_CASE("hud2 palantir: custom heroes use their model-state portraits rather than the generic Wanderer")
{
	if (!haveWorld("hud2 custom hero portrait"))
	{
		return;
	}
	PalantirRig h(shared());
	Object *maiden = h.rig.make("CreateAHero", 2800, 1400);
	Object *captain = h.rig.make("CreateAHero", 3000, 1400);
	REQUIRE(maiden);
	REQUIRE(captain);
	// Independent retail CreateAHeroModels.inc expectations: CREATE_A_HERO_02
	// names CPShieldMaiden; CREATE_A_HERO_00 names CPCaptainofGondor.
	maiden->setModelConditionState(ModelCondition::indexOf("CREATE_A_HERO_02"), true);
	captain->setModelConditionState(ModelCondition::indexOf("CREATE_A_HERO_00"), true);
	CHECK(PalantirCommandUI::objectPortrait(*maiden) == "CPShieldMaiden");
	CHECK(PalantirCommandUI::objectPortrait(*captain) == "CPCaptainofGondor");
	h.hud->input().ui().selectObject(maiden->getID());
	h.frames(10);
	CHECK(h.hud->palantir()->portraitShown() == "CPShieldMaiden");
	// Both objects have the same template, but different portraits: do not
	// skip the second object using the ordinary template comparison cache.
	h.hud->input().ui().selectObject(captain->getID());
	h.frames(10);
	CHECK(h.hud->palantir()->portraitShown() == h.rig.local->getPlayerTemplate()->m_multiSelectionPortrait);
}

TEST_CASE("hud2 custom hero buttons: model-state icons distinguish Shield Maiden and Captain")
{
	if (!haveWorld("hud2 custom hero button")) return;
	PalantirRig h(shared());
	Object *maiden = h.rig.make("CreateAHero", 2800, 1400);
	Object *captain = h.rig.make("CreateAHero", 3000, 1400);
	REQUIRE(maiden);
	REQUIRE(captain);
	maiden->setModelConditionState(ModelCondition::indexOf("CREATE_A_HERO_02"), true);
	captain->setModelConditionState(ModelCondition::indexOf("CREATE_A_HERO_00"), true);
	CHECK(InGameHeroSelect::buttonImage(*maiden) == "HICAHShieldMaiden");
	CHECK(InGameHeroSelect::buttonImage(*captain) == "HICAHCaptainGondor");
	maiden->setModelConditionState(ModelCondition::indexOf("MOUNTED"), true);
	CHECK(InGameHeroSelect::buttonImage(*maiden) == "HICAHShieldMaiden");
}

