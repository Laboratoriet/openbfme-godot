// OpenBFME retail tests, lane AUTOCAST-1 (owner, 2026-10-10): right-clicking a hero's ability button toggles its autocast and the button glows. GPL-3.0.
//
// The Witch-king's Morgul Blade (Command_WitchkingMorgulBlade, AutoAbility = Yes) on the Palantir arc: the content clip's _OnPress with TheAptWindowManager
// + 0x318 == 2 (RW 0x9D6E54) is the right press, ControlBar::rightPressButton (RW 0x9D28D4 -> processCommandUI RW 0x940435) sends MSG_DO_AUTO_ABILITY
// (RW 0x941511), the logic toggles the AutoAbilityBehavior (RW 0x77B9BA -> 0x85D76C), and the clip's update shows the glow (RW 0x9D2D0E:
// SetAutoAbilityOverlayState "_show"); a second right press turns both off. A left press still casts (MSG_DO_SPECIAL_POWER path, not a toggle).
// The tests SKIP loudly without the installs.

#include "doctest.h"

#include "HudTestUtil.h"

#include "Common/Player.h"
#include "GameClient/ControlBar.h"
#include "GameClient/GUI/AptScreens/AptPalantir.h"
#include "GameClient/GUI/ShellServices.h"
#include "GameClient/GUI/WindowManager.h"
#include "GameClient/InGameHud.h"
#include "GameLogic/Module/HeroAbilityModules.h"
#include "GameLogic/Object/Object.h"
#include "GameClient/MessageStream/LookAtXlat.h"
#include "GameClient/CameraSettings.h"
#include "GameClient/TacticalCamera.h"
#include "Libraries/Source/Apt/Apt.h"
#include "Libraries/Source/Apt/AptButtonInst.h"
#include "Libraries/Source/Apt/AptInput.h"

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

using namespace hudtest;

namespace
{
struct AutocastRig
{
	Rig rig;
	RecordingShellServices services;
	std::unique_ptr<TacticalCamera> cam; // a camera attached by a test (it outlives the HUD: ~AutocastRig resets the HUD first)
	std::unique_ptr<InGameHud> hud;
	explicit AutocastRig(SharedWorld &s) : rig(s, "map mp fall back 4p", "FactionAngmar")
	{
		InGameHud::Config cfg{ *rig.game, *s.world, *s.mount->fs, services, rig.view, s.mouse, s.meta, nullptr };
		hud = std::make_unique<InGameHud>(cfg);
		std::string error;
		REQUIRE_MESSAGE(hud->boot(&error), error);
	}
	~AutocastRig() { hud.reset(); }
	void frames(int n)
	{
		for (int i = 0; i < n; ++i)
		{
			hud->update(0.033);
			rig.game->advance(0.033);
		}
	}
	void select(Object *o)
	{
		rig.lookAt(*o->getPosition());
		frames(5);
		const ICoord2D px = rig.screenOf({ o->getPosition()->x, o->getPosition()->y, 10.0f });
		hud->mouseMove(px.x, px.y);
		hud->mouseButton(HudInput::Button::Left, true, px.x, px.y, 0, rig.timeMs += 500);
		hud->mouseButton(HudInput::Button::Left, false, px.x, px.y, 0, rig.timeMs += 40);
		frames(20);
	}
	const ControlBarButton *arcButton(const std::string &name)
	{
		for (const ControlBarButton &b : hud->controlBar().palantirButtons())
		{
			if (b.button && b.button->m_name == name)
			{
				return &b;
			}
		}
		return nullptr;
	}
	// the movie's own press of the arc position (the callback its clip calls on a click), with the mouse button the input translator recorded
	bool pressInMovie(const ControlBarButton &b, int mouseButton)
	{
		const std::string name = "_level" + std::to_string(hud->palantir()->level()) + ".CommandButtons." + std::to_string(b.position) + ".content_OnPress";
		hud->windows().setPressButton(mouseButton);
		const bool ok = hud->windows().hasCommand(name) && hud->windows().invokeCallback(name, "");
		hud->windows().setPressButton(0);
		return ok;
	}
	int count(const std::string &type)
	{
		int n = 0;
		for (const std::string &l : hud->input().messageLog())
		{
			n += l.rfind(type, 0) == 0 && (l.size() == type.size() || l[type.size()] != '_') ? 1 : 0;
		}
		return n;
	}
	// the window point (= stage point of a 1024 x 768 window) where the input routes to the button of the arc content showing `slot`: the grid of the
	// window searched for a point whose topmost Apt button lies inside that content (InGameHud::commandContentAt's own test)
	bool contentPoint(int slot, int &x, int &y)
	{
		Apt &apt = hud->windows().apt();
		for (int py = 380; py < 768; py += 3)
		{
			for (int px = 0; px < 1024; px += 3)
			{
				AptButtonInst *b = apt.input().hitTestButtons((float)px, (float)py);
				bool arc = false;
				int at = -1;
				if (b && hud->palantir()->contentSlotAt(b->targetPath(), arc, at) && arc && at == slot)
				{
					x = px;
					y = py;
					return true;
				}
			}
		}
		return false;
	}
	void rightClick(int x, int y)
	{
		hud->mouseMove(x, y);
		frames(2);
		hud->mouseButton(HudInput::Button::Right, true, x, y, 0, rig.timeMs += 300);
		hud->mouseButton(HudInput::Button::Right, false, x, y, 0, rig.timeMs += 40);
	}
	int overlayCalls(const char *which)
	{
		int n = 0;
		for (const std::string &c : hud->palantir()->autoAbilityOverlayCalls())
		{
			n += c.size() >= std::string(which).size() && c.compare(c.size() - std::string(which).size(), std::string::npos, which) == 0 ? 1 : 0;
		}
		return n;
	}
};
} // namespace

TEST_CASE("autocast hud retail: a right press on the Witch-king's Morgul Blade toggles autocast through MSG_DO_AUTO_ABILITY and the button glows")
{
	if (!haveWorld("autocast hud"))
	{
		return;
	}
	SharedWorld &s = shared();
	AutocastRig h(s);
	h.hud->setWindowSize(1024, 768);
	h.rig.view.setScreen(1024, 768);
	const Coord3D c = h.rig.freeSpot(2800, 1400, 200.0f);
	Object *wk = h.rig.make("AngmarWitchking", c.x, c.y);
	wk->giveUpgrade("Upgrade_WitchkingMorgulBlade"); // UnpauseSpecialPowerUpgrade ModuleTag_WitchkingMorgulBlade
	h.frames(10);
	h.select(wk);
	REQUIRE(h.hud->input().ui().selected() == std::vector<ObjectID>{ wk->getID() });
	const ControlBarButton *blade = h.arcButton("Command_WitchkingMorgulBlade");
	REQUIRE(blade);
	REQUIRE(blade->state != ButtonState::Restricted);
	CHECK_FALSE(blade->autoAbility);
	AutoAbilityBehavior *aa = AutoAbilityBehavior::forPower(*wk, "SpecialAbilityWitchkingMorgulBlade");
	REQUIRE(aa);
	CHECK(aa->autoButton().empty());
	const int slot = blade->slot;

	// the right press: the toggle message, then the logic's auto button and the glow
	REQUIRE(h.pressInMovie(*blade, 2));
	h.frames(15);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 1);
	CHECK(h.count("MSG_DO_SPECIAL_POWER") == 0);
	CHECK(h.hud->controlBar().autoAbilityToggles() == 1);
	CHECK(aa->autoButton() == "Command_WitchkingMorgulBlade");
	blade = h.arcButton("Command_WitchkingMorgulBlade");
	REQUIRE(blade);
	CHECK(blade->autoAbility);
	CHECK(h.hud->palantir()->autoAbilityOverlayShown(slot, true));
	CHECK(h.overlayCalls(" _show") == 1);
	CHECK(h.hud->palantir()->autoAbilityOverlayErrors() == 0u);
	for (const std::string &e : h.hud->palantir()->callErrors())
	{
		CHECK_MESSAGE(e.find("SetAutoAbilityOverlayState") == std::string::npos, e); // the movie's content clip has the function (libInGameUI.apt)
	}
	// mouse button 1 (neither left nor right): RW 0x9D6E54 does nothing
	REQUIRE(h.pressInMovie(*blade, 1));
	h.frames(10);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 1);

	// a second right press: off, the glow hides
	REQUIRE(h.pressInMovie(*blade, 2));
	h.frames(15);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 2);
	CHECK(aa->autoButton().empty());
	blade = h.arcButton("Command_WitchkingMorgulBlade");
	REQUIRE(blade);
	CHECK_FALSE(blade->autoAbility);
	CHECK_FALSE(h.hud->palantir()->autoAbilityOverlayShown(slot, true));
	CHECK(h.overlayCalls(" _hide") == 1);

	// a button without AutoAbility / CANCELABLE (the stance toggle): a right press sends nothing
	const unsigned before = h.hud->controlBar().autoAbilityToggles();
	for (const ControlBarButton &b : h.hud->controlBar().palantirButtons())
	{
		if (b.button && !b.button->m_autoAbility && !b.button->hasOption(COMMAND_OPTION_CANCELABLE))
		{
			CHECK_FALSE(h.hud->controlBar().rightPressButton(b.slot, true));
		}
	}
	CHECK(h.hud->controlBar().autoAbilityToggles() == before);
}

TEST_CASE("autocast hud retail: a real right click on the Morgul Blade button toggles autocast; right clicks and right drags on the ground still order and scroll")
{
	if (!haveWorld("autocast hud mouse"))
	{
		return;
	}
	SharedWorld &s = shared();
	AutocastRig h(s);
	h.hud->setWindowSize(1024, 768);
	h.rig.view.setScreen(1024, 768);
	const Coord3D c = h.rig.freeSpot(2800, 1400, 200.0f);
	Object *wk = h.rig.make("AngmarWitchking", c.x, c.y);
	wk->giveUpgrade("Upgrade_WitchkingMorgulBlade");
	h.hud->input().commandTranslator().setUseAlternateMouse(true); // RotWK's default setup (RW 0x642A4B): the right click orders
	h.frames(10);
	h.select(wk);
	REQUIRE(h.hud->input().ui().selected() == std::vector<ObjectID>{ wk->getID() });
	const ControlBarButton *blade = h.arcButton("Command_WitchkingMorgulBlade");
	REQUIRE(blade);
	const int slot = blade->slot;
	AutoAbilityBehavior *aa = AutoAbilityBehavior::forPower(*wk, "SpecialAbilityWitchkingMorgulBlade");
	REQUIRE(aa);
	int bx = 0, by = 0;
	REQUIRE_MESSAGE(h.contentPoint(slot, bx, by), "no window point routes to the Morgul Blade's content");
	MESSAGE("the Morgul Blade's content is under window point " << bx << ", " << by);

	// the right click on the button: through InGameHud::mouseButton (TheAptWindowManager + 0x318 = 2, the Apt's press, the content's _OnPress)
	h.rightClick(bx, by);
	h.frames(15);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 1);
	CHECK(h.count("MSG_DO_MOVETO") == 0); // the world did not see the click
	CHECK(aa->autoButton() == "Command_WitchkingMorgulBlade");
	CHECK(h.hud->palantir()->autoAbilityOverlayShown(slot, true));
	CHECK(h.hud->palantir()->autoAbilityOverlayErrors() == 0u);
	CHECK(h.hud->windows().pressButton() == 2); // the last press the game posted
	const ICoord2D ground = h.rig.screenOf({ c.x + 120.0f, c.y + 40.0f, 0.0f });
	REQUIRE(ground.y < 380);

	// a right click on the ground (the alternate setup): the selected Witch-king's move order (MSG_DO_MOVETO), the autocast untouched
	h.rightClick(ground.x, ground.y);
	h.frames(10);
	CHECK(h.count("MSG_DO_MOVETO") == 1);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 1);
	CHECK(aa->autoButton() == "Command_WitchkingMorgulBlade");

	// a right drag on the ground scrolls (the LookAtTranslator's RMB scroll), orders nothing, toggles nothing
	// the camera the game scene attaches (TacticalCamera, CameraSettings from GameData; test_camera.cpp's rig): the LookAtTranslator's RMB scroll
	CameraSettings gd;
	std::string camError;
	REQUIRE_MESSAGE(CameraSettings::load(*s.mount->fs, gd, &camError), camError);
	h.cam = std::make_unique<TacticalCamera>(gd);
	h.cam->setViewport(1024, 768);
	h.hud->input().attachCamera(*h.cam);
	LookAtTranslator *la = h.hud->input().lookAt();
	REQUIRE(la);
	h.hud->mouseMove(ground.x, ground.y);
	h.hud->mouseButton(HudInput::Button::Right, true, ground.x, ground.y, 0, h.rig.timeMs += 300);
	bool scrolled = false;
	for (int k = 1; k <= 8; ++k)
	{
		h.hud->mouseMove(ground.x + 20 * k, ground.y);
		h.frames(1);
		scrolled = scrolled || la->isScrolling();
	}
	h.hud->mouseButton(HudInput::Button::Right, false, ground.x + 160, ground.y, 0, h.rig.timeMs += 400);
	h.frames(5);
	CHECK(scrolled);
	CHECK(h.count("MSG_DO_MOVETO") == 1);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 1);
	CHECK(aa->autoButton() == "Command_WitchkingMorgulBlade");

	// the button again (the camera moved: the arc did not): off
	h.rightClick(bx, by);
	h.frames(15);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 2);
	CHECK(aa->autoButton().empty());
	CHECK_FALSE(h.hud->palantir()->autoAbilityOverlayShown(slot, true));

	// the standard setup: a right click on the ground deselects (MSG_DESTROY_SELECTED_GROUP) and toggles nothing
	h.hud->input().commandTranslator().setUseAlternateMouse(false);
	h.rightClick(ground.x, ground.y);
	h.frames(10);
	CHECK(h.count("MSG_DESTROY_SELECTED_GROUP") >= 1);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 2);
	CHECK(aa->autoButton().empty());
}

// lane IOS-21 (OpenBFME, not retail; touch only): the touch layer's double tap toggles autocast only where a right press would (InGameHud::touchButtonAt,
// ControlBar::rightPressKind), and with touch help the help box shows only while a finger is held on the button (InGameHud::setTouchHelp / holdHelp)
TEST_CASE("ios21 retail: touchButtonAt names the Morgul Blade an autocast button and no other arc button; touch help shows only while held, at once")
{
	if (!haveWorld("ios21 touch help"))
	{
		return;
	}
	SharedWorld &s = shared();
	AutocastRig h(s);
	h.hud->setWindowSize(1024, 768);
	h.rig.view.setScreen(1024, 768);
	const Coord3D c = h.rig.freeSpot(2800, 1400, 200.0f);
	Object *wk = h.rig.make("AngmarWitchking", c.x, c.y);
	wk->giveUpgrade("Upgrade_WitchkingMorgulBlade");
	h.frames(10);
	h.select(wk);
	REQUIRE(h.hud->input().ui().selected() == std::vector<ObjectID>{ wk->getID() });
	const ControlBarButton *blade = h.arcButton("Command_WitchkingMorgulBlade");
	REQUIRE(blade);
	const int slot = blade->slot;
	CHECK(h.hud->controlBar().rightPressKind(slot, true) == ControlBar::RightPress::AutoAbility);
	int bx = 0, by = 0;
	REQUIRE(h.contentPoint(slot, bx, by));
	const InGameHud::TouchButton on = h.hud->touchButtonAt(bx, by);
	CHECK(on.kind == InGameHud::TouchButton::Movie);
	CHECK(on.autocast);
	// every other arc button: a movie button, never an autocast one (the Witch-king's other buttons have neither AutoAbility nor CANCELABLE)
	int others = 0;
	for (const ControlBarButton &b : h.hud->controlBar().palantirButtons())
	{
		int x = 0, y = 0;
		if (b.slot == slot || !b.button || !h.contentPoint(b.slot, x, y))
		{
			continue;
		}
		++others;
		const InGameHud::TouchButton t = h.hud->touchButtonAt(x, y);
		CHECK(t.kind == InGameHud::TouchButton::Movie);
		CHECK_MESSAGE(t.autocast == (h.hud->controlBar().rightPressKind(b.slot, true) == ControlBar::RightPress::AutoAbility), b.button->m_name);
		CHECK_FALSE_MESSAGE(t.autocast, b.button->m_name);
	}
	CHECK(others >= 1); // tolerance: the count is the Witch-king's arc layout's (not this lane's); the property is "at least one other button was asked"
	// the ground above the Palantir: no button
	const ICoord2D ground = h.rig.screenOf({ c.x + 120.0f, c.y + 40.0f, 0.0f });
	REQUIRE(ground.y < 380); // tolerance: the point only has to be above the Palantir (the arc's grid starts at y 380, contentPoint)
	CHECK(h.hud->touchButtonAt(ground.x, ground.y).kind == InGameHud::TouchButton::None);
	// a menu over the game is the input's top: no HUD button for a finger
	h.hud->setModal(true);
	CHECK(h.hud->touchButtonAt(bx, by).kind == InGameHud::TouchButton::None);
	h.hud->setModal(false);

	// touch help: the pointer resting on the button (where a tap leaves it) opens nothing
	std::vector<HelpDrawOp> ops;
	h.hud->helpBoxRender(400.0f, 500.0f, 360.0f, 40.0f, ops); // the device's render samples the content width (state 1)
	h.hud->setTouchHelp(true);
	h.hud->mouseMove(bx, by);
	h.frames(20);
	CHECK_FALSE(h.hud->helpBox().isShown());
	const unsigned shown0 = h.hud->helpBox().helpsShown();
	// held: the help shows in the next updates (no TOOLTIPDELAY), the button's
	h.hud->holdHelp(true);
	h.frames(3);
	CHECK(h.hud->helpBox().isShown());
	CHECK(h.hud->helpBox().helpsShown() == shown0 + 1);
	REQUIRE(h.hud->helpBox().help() != nullptr);
	CHECK_FALSE(h.hud->helpBox().help()->name().empty());
	CHECK(h.hud->helpBox().provider().button == blade->button);
	// still held: still shown, not shown again
	h.frames(20);
	CHECK(h.hud->helpBox().isShown());
	CHECK(h.hud->helpBox().helpsShown() == shown0 + 1);
	// lifted: it hides (the help box's own count down), the pointer still on the button; nothing was pressed
	h.hud->holdHelp(false);
	h.frames(10);
	CHECK_FALSE(h.hud->helpBox().isShown());
	CHECK(h.count("MSG_DO_SPECIAL_POWER") == 0);
	CHECK(h.count("MSG_DO_AUTO_ABILITY") == 0);
	// touch help off (a desktop, a mouse on an iPad): the retail hover shows it again
	h.hud->setTouchHelp(false);
	h.hud->mouseMove(5, 5);
	h.frames(10);
	h.hud->mouseMove(bx, by);
	h.frames(10);
	CHECK(h.hud->helpBox().isShown());
}

// lane IOS-40 (OpenBFME, not retail; touch only): "Button taps" previews a button whose press costs. ControlBar::pressCosts reads the Command alone: money,
// the spell book's points or a recharge; every other command acts at once
TEST_CASE("ios40: pressCosts names build, recruit, upgrade, revive, castle, science, power and ability commands, and no quick command")
{
	const std::vector<int> costs = { GUI_COMMAND_DOZER_CONSTRUCT, GUI_COMMAND_FOUNDATION_CONSTRUCT, GUI_COMMAND_CASTLE_UNPACK,
		GUI_COMMAND_CASTLE_UNPACK_EXPLICIT_OBJECT, GUI_COMMAND_UNIT_BUILD, GUI_COMMAND_SECONDARY_UNIT_BUILD, GUI_COMMAND_REVIVE, GUI_COMMAND_PLAYER_UPGRADE,
		GUI_COMMAND_OBJECT_UPGRADE, GUI_COMMAND_CASTLE_UPGRADE, GUI_COMMAND_PURCHASE_SCIENCE, GUI_COMMAND_SPECIAL_POWER,
		GUI_COMMAND_SPECIAL_POWER_FROM_COMMAND_CENTER, GUI_COMMAND_SPECIAL_POWER_TOGGLE, GUI_COMMAND_FIRE_WEAPON, GUI_COMMAND_ONE_RING };
	int previewed = 0;
	for (int c = 0; c < GUI_COMMAND_NUM_COMMANDS; ++c)
	{
		CommandButton b;
		b.m_command = c;
		const bool want = std::find(costs.begin(), costs.end(), c) != costs.end();
		CHECK_MESSAGE(ControlBar::pressCosts(b) == want, GUICommandName(c));
		previewed += ControlBar::pressCosts(b) ? 1 : 0;
	}
	CHECK(previewed == 16);
	// the quick commands the owner named act at once
	for (int c : { GUI_COMMAND_STOP, GUI_COMMAND_HORDE_SET_FORMATION, GUI_COMMAND_HORDE_TOGGLE_FORMATION, GUI_COMMAND_SET_RALLY_POINT, GUI_COMMAND_SET_STANCE,
	               GUI_COMMAND_TOGGLE_STANCE, GUI_COMMAND_ATTACK_MOVE, GUI_COMMAND_GUARD, GUI_COMMAND_SPELL_BOOK, GUI_COMMAND_SELL, GUI_COMMAND_EVACUATE })
	{
		CommandButton b;
		b.m_command = c;
		CHECK_FALSE_MESSAGE(ControlBar::pressCosts(b), GUICommandName(c));
	}
}

TEST_CASE("ios40 retail: touchButtonAt tells each arc button's command, whether it costs, and its window rectangle")
{
	if (!haveWorld("ios40 touch preview"))
	{
		return;
	}
	SharedWorld &s = shared();
	AutocastRig h(s);
	h.hud->setWindowSize(1024, 768);
	h.rig.view.setScreen(1024, 768);
	const Coord3D c = h.rig.freeSpot(2800, 1400, 200.0f);
	Object *wk = h.rig.make("AngmarWitchking", c.x, c.y);
	wk->giveUpgrade("Upgrade_WitchkingMorgulBlade");
	h.frames(10);
	h.select(wk);
	REQUIRE(h.hud->input().ui().selected() == std::vector<ObjectID>{ wk->getID() });
	int asked = 0, costing = 0;
	for (const ControlBarButton &b : h.hud->controlBar().palantirButtons())
	{
		int x = 0, y = 0;
		if (!b.button || !h.contentPoint(b.slot, x, y))
		{
			continue;
		}
		++asked;
		const InGameHud::TouchButton t = h.hud->touchButtonAt(x, y);
		CHECK(t.kind == InGameHud::TouchButton::Movie);
		CHECK_MESSAGE(t.button == b.button, b.button->m_name);
		CHECK_MESSAGE(t.costs == ControlBar::pressCosts(*b.button), b.button->m_name);
		costing += t.costs ? 1 : 0;
		CHECK(t.radialSlot == -1);
		REQUIRE(t.hasRect);
		// the rectangle holds the point the finger is on, and is a button's (at most a quarter of the window)
		// tolerance: containment is the property (the hit box's size is the movie's, not this lane's)
		CHECK_MESSAGE((t.rect[0] <= x && x <= t.rect[2] && t.rect[1] <= y && y <= t.rect[3]), b.button->m_name);
		const float w = t.rect[2] - t.rect[0], hgt = t.rect[3] - t.rect[1];
		CHECK(w > 0.0f); // tolerance: a measured, non-empty box (its size is the movie's)
		CHECK(w < 256.0f);   // tolerance: a quarter of the 1024 px window, a bound on "a button", not a measured size
		CHECK(hgt < 192.0f); // tolerance: a quarter of the 768 px window
	}
	CHECK(asked >= 1); // tolerance: the Witch-king's arc layout's count (not this lane's); the property is "every arc button asked agrees"
	const ControlBarButton *blade = h.arcButton("Command_WitchkingMorgulBlade");
	REQUIRE(blade);
	int bx = 0, by = 0;
	REQUIRE(h.contentPoint(blade->slot, bx, by));
	const InGameHud::TouchButton on = h.hud->touchButtonAt(bx, by);
	CHECK(on.costs); // a special power: a recharge
	CHECK(on.autocast);
	CHECK(costing >= 1); // tolerance: at least the Morgul Blade
	// the world: no button, nothing costs
	const ICoord2D ground = h.rig.screenOf({ c.x + 120.0f, c.y + 40.0f, 0.0f });
	const InGameHud::TouchButton none = h.hud->touchButtonAt(ground.x, ground.y);
	CHECK(none.kind == InGameHud::TouchButton::None);
	CHECK(none.button == nullptr);
	CHECK_FALSE(none.costs);
	CHECK_FALSE(none.hasRect);
}
