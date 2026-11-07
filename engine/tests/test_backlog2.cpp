// OpenBFME unit tests (lane BACKLOG2): the RotWK functions behind the castle, camp and construction stops, ported with Open-BFME-2's byte-matched source as the
// donor. Expected values come from the RotWK disassembly (caveat S-001) at the addresses each case names.

#include "doctest.h"
#include "ProdTestUtil.h"

#include "GameLogic/GameLogicDispatch.h"
#include "GameLogic/Module/CastleModules.h"

using namespace prodtest;

namespace
{
GameMessage queueMessage(int player, const ThingTemplate *t)
{
	GameMessage m(MSG_QUEUE_UNIT_CREATE, player); // RotWK layout (RW 0x77A764)
	m.appendBooleanArgument(false);
	m.appendIntegerArgument((int)t->getTemplateID());
	m.appendIntegerArgument(-1);
	m.appendBooleanArgument(false);
	m.appendBooleanArgument(false);
	return m;
}
GameMessage selectMessage(int player, Object *o)
{
	GameMessage m(MSG_CREATE_SELECTED_GROUP, player);
	m.appendBooleanArgument(true);
	m.appendObjectIDArgument(o->getID());
	return m;
}
} // namespace

TEST_CASE("BACKLOG2 S-207: a factory a script disabled or unpowered queues nothing and charges nothing (RW 0x793F39: Object + 0x457 & 3 -> 3)")
{
	ProdWorld f;
	f.load(kBarracksObjects);
	f.load(kBarracksCommands);
	Object *barracks = f.make("Barracks", f.teamOf("Alice"));
	REQUIRE(barracks != nullptr);
	CommandList list;
	GameLogicDispatch dispatch(*f.logic);
	dispatch.attach(list);
	const ThingTemplate *soldier = f.w.get("Soldier");
	const int alice = f.alice()->getPlayerIndex();
	ProductionUpdateInterface *pu = barracks->getProductionUpdate();
	REQUIRE(pu != nullptr);
	list.append(selectMessage(alice, barracks));
	f.frames(1);
	const std::uint32_t money = f.alice()->getMoney()->countMoney();
	// the script status bits 1 (SCRIPT_DISABLED) and 2 (SCRIPT_UNPOWERED) each make the factory refuse with FACTORY_IS_DISABLED (3)
	for (std::uint8_t bit : { (std::uint8_t)1u, (std::uint8_t)2u })
	{
		barracks->setScriptStatus(bit, true);
		CHECK(BuildAssistant::canMakeUnit(*barracks, soldier, -1) == CANMAKE_FACTORY_IS_DISABLED);
		list.append(queueMessage(alice, soldier));
		f.frames(1);
		CHECK(pu->getProductionCount() == 0);
		CHECK(f.alice()->getMoney()->countMoney() == money);
		barracks->setScriptStatus(bit, false);
	}
	// the other script bits (4 SCRIPT_UNSELLABLE, 8 SCRIPT_UNSTEALTHED, 0x10 SCRIPT_TARGETABLE) are not tested by RW 0x793F43 (`test al, 3`)
	barracks->setScriptStatus(4u | 8u | 0x10u, true);
	CHECK(BuildAssistant::canMakeUnit(*barracks, soldier, -1) == CANMAKE_OK);
	// cleared: the same command queues the soldier and charges its BuildCost (100)
	barracks->setScriptStatus(4u | 8u | 0x10u, false);
	list.append(queueMessage(alice, soldier));
	f.frames(1);
	CHECK(pu->getProductionCount() == 1);
	CHECK(f.alice()->getMoney()->countMoney() == money - 100);
}

TEST_CASE("BACKLOG2 S-951: CastleToUnpackForFaction reads `<side> <base> [<cost> [<limit>]]`; a second line of a side is not inserted; sides compare exactly (RW 0x79BD2F)")
{
	ProdWorld f;
	f.load("Object CTestFlag\n  KindOf = IMMOBILE BASE_FOUNDATION\n  Behavior = CastleBehavior ModuleTag_castle\n"
		   "    CastleToUnpackForFaction = Alpha Base_Alpha 2000\n"
		   "    CastleToUnpackForFaction = Beta Base_Beta 300 7\n"
		   "    CastleToUnpackForFaction = Alpha Base_Other 5\n"
		   "    CastleToUnpackForFaction = alpha Base_Lower\n"
		   "  End\nEnd\n");
	Object *flag = f.make("CTestFlag", f.teamOf("Alice"));
	REQUIRE(flag);
	const CastleBehavior *cb = dynamic_cast<const CastleBehavior *>(flag->findModule("CastleBehavior"));
	REQUIRE(cb);
	const std::vector<CastleFactionEntry> &list = cb->data()->m_castleToUnpackForFaction;
	REQUIRE(list.size() == 3);
	CHECK(list[0].faction == "Alpha");
	CHECK(list[0].base == "Base_Alpha");
	CHECK(list[0].cost == 2000u);
	CHECK(list[0].limit == 0u);
	CHECK(list[1].faction == "Beta");
	CHECK(list[1].cost == 300u);
	CHECK(list[1].limit == 7u);
	CHECK(list[2].faction == "alpha");
	CHECK(list[2].base == "Base_Lower");
	CHECK(list[2].cost == 0u);
	CHECK(cb->data()->entryFor("Alpha")->base == "Base_Alpha"); // the first line of the side stays (map::insert)
	CHECK(cb->data()->entryFor("alpha")->base == "Base_Lower");
	CHECK(cb->data()->entryFor("ALPHA") == nullptr);
}

TEST_CASE("BACKLOG2 S-951: a CastleToUnpackForFaction count that is not an unsigned integer fails the load, as INI::scanUnsignedInt does in retail (RW 0x79BDBD -> 0x42EA42)")
{
	ProdWorld f;
	const std::string err = f.w.load("Object CBadFlag\n  KindOf = IMMOBILE BASE_FOUNDATION\n  Behavior = CastleBehavior ModuleTag_castle\n"
									 "    CastleToUnpackForFaction = Alpha Base_Alpha lots\n  End\nEnd\n");
	CHECK_FALSE(err.empty());
}

#include "GameLogic/CastleCommands.h"

TEST_CASE("BACKLOG2 S-951: the limit column prices the unpack at 99999999 while the player has fewer free command points than it, and at the cost from exactly that many (RW 0x799660 .. 0x799679)")
{
	ProdWorld f;
	f.load("Object CLimitFlag\n  KindOf = IMMOBILE BASE_FOUNDATION\n  Behavior = CastleBehavior ModuleTag_castle\n"
		   "    CastleToUnpackForFaction = Alpha Base_Alpha 300 7\n  End\nEnd\n");
	REQUIRE(f.alice()->getSide() == "Alpha");
	Object *flag = f.make("CLimitFlag", f.teamOf("Alice"));
	REQUIRE(flag);
	CastleBehavior *cb = dynamic_cast<CastleBehavior *>(flag->findModule("CastleBehavior"));
	REQUIRE(cb);
	GameLogicDispatch dispatch(*f.logic);
	CastleCommands::registerHandlers(dispatch);
	f.alice()->selection().clear();
	f.alice()->selection().push_back(flag->getID());
	const int limit = f.economy().commandPointLimit(*f.alice());
	const std::uint32_t money = f.alice()->getMoney()->countMoney();
	REQUIRE(money == 1500u); // the fixture's starting cash: above the cost, below 99999999
	// 6 free points: one below the limit column
	setUsage(*f.alice(), limit - 6);
	REQUIRE(f.alice()->commandPointsAvailable() == 6);
	CHECK(cb->unpackCost(f.alice()) == 99999999u);
	CHECK_FALSE(cb->canAffordUnpack(f.alice()));
	dispatch.dispatch(GameMessage(MSG_CASTLE_UNPACK, f.alice()->getPlayerIndex()));
	CHECK(cb->state() == CastleBehavior::STATE_IDLE);
	CHECK(f.alice()->getMoney()->countMoney() == money);
	// exactly 7: the cost
	setUsage(*f.alice(), limit - 7);
	REQUIRE(f.alice()->commandPointsAvailable() == 7);
	CHECK(cb->unpackCost(f.alice()) == 300u);
	CHECK(cb->canAffordUnpack(f.alice()));
	dispatch.dispatch(GameMessage(MSG_CASTLE_UNPACK, f.alice()->getPlayerIndex()));
	CHECK(cb->state() == CastleBehavior::STATE_PACKED);
	CHECK(f.alice()->getMoney()->countMoney() == money - 300);
	CHECK(cb->storedPrice() == 300.0f);
}

#include "Common/StateHash.h"
#include "Common/XferLoad.h"
#include "Common/XferSave.h"

TEST_CASE("BACKLOG2 S-951 snapshot: a castle a player paid to unpack keeps its unpack price (+ 0x4C) and explicit object (+ 0x98) through the snapshot, so "
		  "the loaded castle hashes as the saved one; a castle nobody paid for keeps its version 2 bytes")
{
	ProdWorld f;
	f.load("Object CSaveFlag\n  KindOf = IMMOBILE BASE_FOUNDATION\n  Behavior = CastleBehavior ModuleTag_castle\n"
		   "    CastleToUnpackForFaction = Alpha Base_Alpha 300\n  End\nEnd\n");
	f.load(kBarracksObjects);
	Object *flag = f.make("CSaveFlag", f.teamOf("Alice"));
	REQUIRE(flag);
	CastleBehavior *cb = dynamic_cast<CastleBehavior *>(flag->findModule("CastleBehavior"));
	REQUIRE(cb);
	// nothing paid: the price and the explicit object are not in the state hash, and the snapshot keeps the version 2 layout (an older game's bytes)
	XferSave unpaid;
	cb->xfer(unpaid);
	REQUIRE_FALSE(unpaid.data().empty());
	CHECK(unpaid.data()[0] == 2);
	GameLogicDispatch dispatch(*f.logic);
	CastleCommands::registerHandlers(dispatch);
	f.alice()->selection().clear();
	f.alice()->selection().push_back(flag->getID());
	// MSG_CASTLE_UNPACK_EXPLICIT_OBJECT (RW 0x77C338): initiateUnpack keeps the template (RW 0x79C18D), RW 0x797B06 pays its price and keeps it
	const ThingTemplate *archer = f.w.get("Archer");   // BuildCost 150
	const ThingTemplate *soldier = f.w.get("Soldier"); // BuildCost 100
	REQUIRE(archer);
	REQUIRE(soldier);
	GameMessage m(MSG_CASTLE_UNPACK_EXPLICIT_OBJECT, f.alice()->getPlayerIndex());
	m.appendIntegerArgument((int)archer->getTemplateID());
	dispatch.dispatch(m);
	REQUIRE(cb->state() == CastleBehavior::STATE_PACKED);
	REQUIRE(cb->explicitTemplateName() == "Archer");
	REQUIRE(cb->storedPrice() == 150.0f);
	StateHasher before;
	cb->crc(before);
	XferSave saved;
	cb->xfer(saved);
	REQUIRE_FALSE(saved.data().empty());
	CHECK(saved.data()[0] == 3);
	// changed after the save (another explicit unpack: another template and price), then loaded back: the saved ones return
	cb->initiateUnpack(false, soldier);
	REQUIRE(cb->explicitTemplateName() == "Soldier");
	REQUIRE(cb->storedPrice() == 100.0f);
	{
		XferLoad load(saved.data());
		cb->xfer(load);
	}
	CHECK(cb->storedPrice() == 150.0f);
	CHECK(cb->explicitTemplateName() == "Archer");
	StateHasher after;
	cb->crc(after);
	CHECK(after.value() == before.value());
	// a version 2 snapshot (written before version 3, or by a castle nobody paid for) loads with price 0 and no explicit object
	{
		XferLoad load(unpaid.data());
		cb->xfer(load);
	}
	CHECK(cb->storedPrice() == 0.0f);
	CHECK(cb->explicitTemplateName().empty());
}
