// OpenBFME. GPL-3.0. Lane IOS-43 (OpenBFME, not retail; touch only): InGameHud::touchTargetAt / cancelTouchTarget, the touch layer's view of a power
// waiting for its target (scripts/touch/touch_controls.gd's ✓ / ✕ targeting). What it answers must be what the left click at that pixel does: the tests
// ask it, then click there through the real mouse stream and compare. Retail 2.01 data; skips without ROTWK_INSTALL / BFME2_INSTALL.

#include "HordeCompleteTestUtil.h"
#include "HudTestUtil.h"
#include "doctest.h"

#include "Common/Player.h"
#include "Common/SpecialPower.h"
#include "GameClient/GUI/GameTextSource.h"
#include "GameClient/GUI/ShellServices.h"
#include "GameClient/InGameHud.h"
#include "GameLogic/Object/ExperienceTracker.h"
#include "GameLogic/Object/Object.h"
#include "GameLogic/System/ShroudManager.h"

#include <memory>
#include <string>

using namespace hudtest;

namespace
{
// the game text: any label is "&<the label's part after ':'>" and a second line (the touch banner's name drops the '&' and stops at the line break)
class LabelText : public GameTextSource
{
public:
	bool fetch(const std::string &label, std::u16string &out) const override
	{
		const std::string name = label.substr(label.find(':') + 1);
		out = u"&" + std::u16string(name.begin(), name.end()) + u"\nSecond line";
		return true;
	}
};

struct TargetRig
{
	Rig rig;
	RecordingShellServices services;
	LabelText text;
	std::unique_ptr<InGameHud> hud;

	explicit TargetRig(SharedWorld &s) : rig(s, "map mp fall back 4p", "FactionMen")
	{
		InGameHud::Config cfg{ *rig.game, *s.world, *s.mount->fs, services, rig.view, s.mouse, s.meta, &text };
		hud = std::make_unique<InGameHud>(cfg);
		std::string error;
		REQUIRE_MESSAGE(hud->boot(&error), error);
		rig.game->shroud().revealMapForPlayerPermanently(rig.index());
	}
	~TargetRig() { hud.reset(); }
	void frames(int n, bool logic = true)
	{
		for (int i = 0; i < n; ++i)
		{
			hud->update(0.034);
			if (logic)
			{
				rig.game->advance(0.034);
			}
		}
	}
	ControlBarButton select(Object &hero, const char *command)
	{
		hero.getExperienceTracker()->gainExpForLevel(10, true, false);
		for (int i = 0; i < 20; ++i) // level upgrades and UnpauseSpecialPower modules run on logic frames
		{
			hud->update(0.034);
			rig.game->advance(0.2);
		}
		hud->input().ui().deselectAll(false);
		hud->input().ui().selectObject(hero.getID());
		hud->update(0.034);
		for (const auto *buttons : { &hud->controlBar().palantirButtons(), &hud->controlBar().sideButtons() })
		{
			for (const auto &b : *buttons)
			{
				if (b.button && b.button->m_name == command)
				{
					return b;
				}
			}
		}
		return {};
	}
	void click(HudInput::Button button, const ICoord2D &p)
	{
		hud->mouseMove(p.x, p.y);
		hud->mouseButton(button, true, p.x, p.y, 0, rig.timeMs += 500);
		hud->mouseButton(button, false, p.x, p.y, 0, rig.timeMs += 40);
		hud->update(0.034);
	}
	size_t casts() const
	{
		size_t n = 0;
		for (const auto &m : rig.game->commands().messages())
		{
			n += m.getType() == MSG_DO_SPECIAL_POWER_AT_LOCATION || m.getType() == MSG_DO_SPECIAL_POWER_AT_OBJECT || m.getType() == MSG_DO_SPECIAL_POWER ? 1 : 0;
		}
		return n;
	}
	std::string label(const InGameHud::TouchTarget &t) const { return std::string(t.label.begin(), t.label.end()); }
};
} // namespace

TEST_CASE("IOS-43 touch targeting: a hero's object power (Gloin's Slam) and ground power (Gimli's Leap) as touchTargetAt sees them, matching the click")
{
	if (!haveWorld("ios43 touch target abilities"))
	{
		return;
	}
	{
		TargetRig h(shared());
		auto context = h.hud->enterContext();
		const Coord3D home = h.rig.freeSpot(1800, 1400, 300.0f);
		Object *hero = h.rig.make("DwarvenGloin", home.x, home.y);
		REQUIRE(hero);
		const auto b = h.select(*hero, "Command_SpecialAbilityDwarvenGloinSlam");
		REQUIRE(b.button);
		Object *ally = h.rig.make("GondorFighter", home.x + 100, home.y);
		Object *enemy = h.rig.make("GondorFighter", home.x + 200, home.y, h.rig.game->players().findPlayerWithName("Player_2"));
		REQUIRE(ally);
		REQUIRE(enemy);
		h.hud->input().context().pickRay = {}; // the input stack's geometry picker (test_hero_activation_targeting.cpp's reason)
		CHECK(h.hud->touchTargetAt(10, 10).kind == InGameHud::TouchTarget::None); // nothing waits yet
		CHECK_FALSE(h.hud->cancelTouchTarget());
		REQUIRE(h.hud->controlBar().pressButton(b.slot, b.inPalantir));
		h.frames(1, false);
		h.rig.lookAt(*ally->getPosition());
		h.frames(1, false);
		const ICoord2D onAlly = h.rig.screenOf(*ally->getPosition());
		InGameHud::TouchTarget t = h.hud->touchTargetAt(onAlly.x, onAlly.y);
		CHECK(t.kind == InGameHud::TouchTarget::Object);
		CHECK_FALSE(t.spellBook);
		CHECK(t.button == b.button);
		REQUIRE(t.power);
		CHECK(t.power->getName() == b.button->m_specialPowerName);
		CHECK(h.label(t) == b.button->m_textLabel.front().substr(b.button->m_textLabel.front().find(':') + 1)); // no '&', the first line only
		CHECK(t.world);
		CHECK(t.ground);
		CHECK_FALSE(t.valid); // the enemy-only power on an ally: the click casts nothing
		const size_t before = h.casts();
		h.click(HudInput::Button::Left, onAlly);
		CHECK(h.casts() == before);
		CHECK(h.hud->input().ui().getGUICommand() == b.button);
		const ICoord2D onEnemy = h.rig.screenOf(*enemy->getPosition());
		t = h.hud->touchTargetAt(onEnemy.x, onEnemy.y);
		CHECK(t.kind == InGameHud::TouchTarget::Object);
		CHECK(t.object == enemy->getID());
		CHECK(t.valid);
		// the cancel (✕): the command mode ends without a cast, the hero stays selected, and the query says nothing waits
		REQUIRE(h.hud->cancelTouchTarget());
		CHECK(h.hud->input().ui().getGUICommand() == nullptr);
		CHECK(h.hud->input().ui().firstSelected() == hero->getID());
		CHECK(h.hud->touchTargetAt(onEnemy.x, onEnemy.y).kind == InGameHud::TouchTarget::None);
		CHECK(h.casts() == before);
		// again, and ✓: the click at the enemy casts at it, as the query said
		REQUIRE(h.hud->controlBar().pressButton(b.slot, b.inPalantir));
		h.frames(1, false);
		REQUIRE(h.hud->touchTargetAt(onEnemy.x, onEnemy.y).valid);
		h.click(HudInput::Button::Left, onEnemy);
		CHECK(h.casts() == before + 1);
		CHECK(h.hud->touchTargetAt(onEnemy.x, onEnemy.y).kind == InGameHud::TouchTarget::None);
	}
	{
		TargetRig h(shared());
		auto context = h.hud->enterContext();
		const Coord3D home = h.rig.freeSpot(1800, 1400, 300.0f);
		Object *hero = h.rig.make("DwarvenGimli", home.x, home.y);
		REQUIRE(hero);
		const auto b = h.select(*hero, "Command_RohanGimliLeap");
		REQUIRE(b.button);
		REQUIRE(h.hud->controlBar().pressButton(b.slot, b.inPalantir));
		const Coord3D target{ home.x + 250, home.y, h.rig.logic().getGroundHeight(home.x + 250, home.y) };
		h.rig.lookAt(target);
		const ICoord2D p = h.rig.screenOf(target);
		h.hud->mouseMove(p.x, p.y);
		h.frames(1, false);
		InGameHud::TouchTarget t = h.hud->touchTargetAt(p.x, p.y);
		CHECK(t.kind == InGameHud::TouchTarget::Location);
		CHECK(t.radius == 35.0f); // the retail decal's 70 diameter (test_hero_activation_targeting.cpp): RadiusCursorRadius 35
		CHECK(t.decal);           // retail's LeapRadiusCursor is drawn under the pointer
		CHECK(t.valid);
		const size_t before = h.casts();
		h.click(HudInput::Button::Left, p);
		CHECK(h.casts() == before + 1);
	}
}

TEST_CASE("IOS-43 touch targeting: the spell book's ground power (the Men's first, Heal) as touchTargetAt sees it; the cancel; the click it predicts")
{
	if (!haveWorld("ios43 touch target spell book"))
	{
		return;
	}
	SharedWorld &s = shared();
	TargetRig h(s);
	h.hud->setWindowSize(1024, 768);
	h.rig.view.setScreen(1024, 768);
	auto ctx = h.hud->enterContext();
	const ThingTemplate *cit = s.world->things().findTemplate("MenFortressCitadel");
	REQUIRE(cit);
	Object *fort = h.rig.logic().newObject(cit, h.rig.local->getDefaultTeam(), ObjectStatusMaskType{});
	REQUIRE(fort);
	Coord3D at{ 600, 600, 0 };
	fort->setPosition(&at);
	testutil::completeHorde(fort);
	fort->friend_onBuildComplete();
	h.frames(40);
	REQUIRE(h.hud->palantir()->spellBookShown());
	std::string error;
	REQUIRE_MESSAGE(h.hud->openSpellStore(&error), error);
	h.frames(40);
	int buy = -1;
	for (const SpellStoreModel::Button &b : h.hud->spellStore()->model().buttons())
	{
		if (b.state == SpellStoreModel::STATE_AVAILABLE && buy < 0)
		{
			buy = b.index;
		}
	}
	REQUIRE(buy >= 0); // tolerance: the index is the retail store's first power the rank-1 points buy
	REQUIRE(h.hud->spellStore()->click(buy));
	h.hud->closeSpellStore();
	h.frames(40);
	int aim = -1;
	for (const InGameSpellBookModel::Button &b : h.hud->spellBar().buttons())
	{
		if (b.owned && b.ready && b.needsPosition && aim < 0)
		{
			aim = b.index;
		}
	}
	REQUIRE(aim >= 0); // tolerance: the bought power's command set slot comes from retail data
	const Coord3D c = h.rig.freeSpot(2800, 1400, 200.0f);
	h.rig.lookAt(c);
	h.frames(5);
	const ICoord2D ground = h.rig.screenOf({ c.x, c.y, h.rig.logic().getGroundHeight(c.x, c.y) });
	REQUIRE_FALSE(h.hud->isOverGui(ground.x, ground.y));

	REQUIRE(h.hud->pressSpell(aim));
	h.frames(2);
	InGameHud::TouchTarget t = h.hud->touchTargetAt(ground.x, ground.y);
	CHECK(t.kind == InGameHud::TouchTarget::Location);
	CHECK(t.spellBook);
	REQUIRE(t.power);
	CHECK(t.power->getName() == "SpellBookHeal");
	CHECK(h.label(t) == "Heal");
	CHECK(t.radius > 0.0f); // tolerance: SPELL_HEAL_RADIUS_CURSOR is a retail macro; any positive radius is drawn
	CHECK(t.world);
	CHECK(t.valid);
	CHECK(t.object == INVALID_ID);
	// a point on the Palantir is no world point
	bool found = false;
	for (int y = 767; y > 500 && !found; y -= 8)
	{
		for (int x = 8; x < 1024 && !found; x += 32)
		{
			if (h.hud->isOverGui(x, y))
			{
				CHECK_FALSE(h.hud->touchTargetAt(x, y).world);
				found = true;
			}
		}
	}
	CHECK(found);
	// ✕: the cancel ends the aim, casts nothing
	const size_t before = h.casts();
	REQUIRE(h.hud->cancelTouchTarget());
	CHECK_FALSE(h.hud->spellBar().targeting());
	CHECK(h.hud->touchTargetAt(ground.x, ground.y).kind == InGameHud::TouchTarget::None);
	h.frames(2);
	CHECK(h.casts() == before);
	// with a script's input off nothing is cancelled (the right click's rule), and it waits on
	REQUIRE(h.hud->pressSpell(aim));
	h.frames(2);
	h.hud->input().ui().setInputEnabled(false);
	CHECK_FALSE(h.hud->cancelTouchTarget());
	CHECK(h.hud->spellBar().targeting());
	CHECK_FALSE(h.hud->touchTargetAt(ground.x, ground.y).valid);
	h.hud->input().ui().setInputEnabled(true);
	// ✓: the left click at the valid point casts there
	REQUIRE(h.hud->touchTargetAt(ground.x, ground.y).valid);
	h.click(HudInput::Button::Left, ground);
	h.frames(2);
	CHECK_FALSE(h.hud->spellBar().targeting());
}
