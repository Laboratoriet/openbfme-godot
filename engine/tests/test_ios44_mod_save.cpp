// OpenBFME unit tests: lane IOS-44, a save and a load with an install-folder mod mounted (docs/MOD-COMPAT.md row 9). GPL-3.0.
//
// The game's --save-test refused its own save with Edain mounted ("it loads with state hash X ..., the save recorded Y") while RotWK's loaded. This
// test runs a skirmish over the mod's file system (OPENBFME_EDAIN_INSTALL, and OPENBFME_EDAIN_ASSETS_INSTALL when that layer has RotWK files: the
// edainfactions1 test's variables), saves its snapshot, loads it into a newly started game of the same START and compares the state hash; on a
// difference it names the section, the objects and, inside an object, the modules (or the object's own fields) that differ.
// SKIP loudly without ROTWK_INSTALL / BFME2_INSTALL or the mod.

#include "doctest.h"

#include "StartTestUtil.h"

#include "GameEngineDevice/Win32Device/Common/Win32BIGFileSystem.h"

#include "Common/ModMount.h"
#include "Common/PlayerTemplate.h"
#include "Common/RetailArchivePolicy.h"
#include "Common/StateHash.h"
#include "GameClient/GUI/Skirmish/IniSkirmishSetupSource.h"
#include "GameClient/LiveGame.h"
#include "GameClient/MapCreationHooks.h"
#include "GameLogic/NewGame/NewGame.h"
#include "GameLogic/Object/Object.h"
#include "Libraries/WWVegas/WW3D2/assetmgr.h"

#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace
{
std::string env(const char *name)
{
	const char *v = std::getenv(name);
	return v ? v : "";
}

// the mod's world: the retail archives with the install-folder mod laid over them (as the Mods folder mounts Edain, ModMount.h MountInstallOverlay)
struct ModWorld
{
	std::unique_ptr<retailtest::Mount> mount;
	std::unique_ptr<starttest::Shared> shared;
	std::vector<MapCacheEntry> maps;
};

ModWorld *edainWorld()
{
	static ModWorld w;
	static bool built = false;
	if (built)
	{
		return w.shared ? &w : nullptr;
	}
	built = true;
	const std::string install = env("OPENBFME_EDAIN_INSTALL");
	if (install.empty() || env("ROTWK_INSTALL").empty() || env("BFME2_INSTALL").empty())
	{
		return nullptr;
	}
	std::vector<std::string> overlays{ install };
	if (!env("OPENBFME_EDAIN_ASSETS_INSTALL").empty())
	{
		overlays.push_back(env("OPENBFME_EDAIN_ASSETS_INSTALL")); // highest priority first
	}
	std::string error;
	RetailInstall rotwk, bfme2;
	rotwk.label = "rotwk";
	rotwk.root = env("ROTWK_INSTALL");
	bfme2.label = "bfme2";
	bfme2.root = env("BFME2_INSTALL");
	REQUIRE_MESSAGE(RetailArchivePolicy::loadBuiltin("rotwk-201", rotwk.policy, &error), error);
	REQUIRE_MESSAGE(RetailArchivePolicy::loadBuiltin("bfme2-106", bfme2.policy, &error), error);
	auto base = std::make_unique<Win32BIGFileSystem>();
	RetailMountOptions retailOptions;
	retailOptions.md5CachePath = (std::filesystem::temp_directory_path() / "ios44-retail-md5.tsv").string();
	const RetailMountReport retail = MountRetailArchives(*base, { rotwk, bfme2 }, retailOptions);
	REQUIRE_MESSAGE(retail.ok, "retail mount: " << (retail.errors.empty() ? "" : retail.errors.front()));
	w.mount = std::make_unique<retailtest::Mount>();
	w.mount->fs = std::make_unique<Win32BIGFileSystem>();
	ModMountOptions modOptions;
	modOptions.rotwkInstallRoot = rotwk.root;
	modOptions.md5CachePath = (std::filesystem::temp_directory_path() / "ios44-mod-md5.tsv").string();
	const ModMountReport mounted = MountInstallOverlay(*w.mount->fs, retail, overlays, modOptions);
	REQUIRE_MESSAGE(mounted.ok, "mod mount: " << (mounted.errors.empty() ? "" : mounted.errors.front()));
	auto s = std::make_unique<starttest::Shared>();
	s->mount = w.mount.get();
	s->world = std::make_unique<RetailObjectWorld>(*w.mount->fs);
	REQUIRE_MESSAGE(s->world->load(&error), error);
	REQUIRE_MESSAGE(MapObjectGameData::load(*w.mount->fs, s->options, &error), error);
	REQUIRE_MESSAGE(MapObjectGameData::loadPlayerTemplates(*w.mount->fs, s->options, &error), error);
	REQUIRE_MESSAGE(MapCreationHooks::load(*w.mount->fs, s->options.creationScripts, &error), error);
	REQUIRE_MESSAGE(GameLogicSettingsLoader::load(*w.mount->fs, s->settings, &error), error);
	auto context = s->world->enterContext();
	REQUIRE_MESSAGE(IniSkirmishSetupSource::loadMapCache(*w.mount->fs, w.maps, &error), error);
	w.shared = std::move(s);
	return &w;
}

struct Game
{
	NewGameStart start{ RandomAlgorithm::ZH_CarryChain };
	std::unique_ptr<ArchiveW3DFileSource> source;
	std::unique_ptr<WW3DAssetManager> assets;
	std::unique_ptr<LiveGame> game;
};

void load(ModWorld &w, const NewGameMessage &m, Game &out)
{
	starttest::Shared &s = *w.shared;
	std::string error;
	REQUIRE_MESSAGE(NewGame::prepareNewGame(m, s.world->playerTemplates(), s.settings, w.maps, RandomAlgorithm::ZH_CarryChain, out.start, &error), error);
	out.source = std::make_unique<ArchiveW3DFileSource>(*s.mount->fs);
	out.assets = std::make_unique<WW3DAssetManager>(*out.source);
	out.game = std::make_unique<LiveGame>(*s.world, *s.mount->fs, *out.assets, s.options);
	LiveGame::Options o;
	o.start = &out.start;
	REQUIRE_MESSAGE(out.game->load(o, &error), error);
}

void runTo(Game &g, UnsignedInt frame)
{
	while (g.game->logic().getFrame() < frame)
	{
		REQUIRE(g.game->advance(0.2) == 1);
		g.game->drainFrames();
	}
	REQUIRE(g.game->logic().getFrame() == frame);
}

// an object's hash cut into its own fields (every module left out) and each module's
struct ObjectParts
{
	ObjectID id = 0;
	std::string templateName;
	std::uint32_t own = 0;
	std::vector<std::pair<std::string, std::uint32_t>> modules;
};

std::vector<ObjectParts> objectParts(const GameLogic &logic)
{
	std::vector<ObjectParts> out;
	for (const Object *o = logic.getFirstObject(); o; o = o->getNextObject())
	{
		ObjectParts p;
		p.id = o->getID();
		p.templateName = o->getTemplate() ? o->getTemplate()->getName() : std::string();
		StateHasher own;
		o->crcOmittingModules(own, [](const BehaviorModule &) { return true; });
		p.own = own.value();
		for (const std::unique_ptr<BehaviorModule> &m : o->modules())
		{
			StateHasher h;
			m->crc(h);
			p.modules.emplace_back(m->getModuleClassName(), h.value());
		}
		out.push_back(std::move(p));
	}
	return out;
}

struct Breakdown
{
	std::uint32_t total = 0;
	std::vector<GameLogic::StateHashSection> sections;
	std::vector<ObjectParts> objects;
};

Breakdown breakdown(const GameLogic &logic)
{
	Breakdown b;
	b.total = logic.computeStateHashBreakdown(b.sections, nullptr);
	b.objects = objectParts(logic);
	return b;
}

// what differs between the saved and the loaded state, named (empty when nothing does)
std::string difference(const Breakdown &a, const Breakdown &b)
{
	std::ostringstream o;
	for (size_t i = 0; i < a.sections.size() || i < b.sections.size(); ++i)
	{
		if (i >= a.sections.size() || i >= b.sections.size() || a.sections[i].name != b.sections[i].name || a.sections[i].value != b.sections[i].value)
		{
			o << " section '" << (i < a.sections.size() ? a.sections[i].name : std::string("-")) << "';";
		}
	}
	if (a.objects.size() != b.objects.size())
	{
		o << " " << a.objects.size() << " objects saved, " << b.objects.size() << " loaded;";
	}
	std::map<std::string, int> byModule;
	int shown = 0, objects = 0;
	for (size_t i = 0; i < a.objects.size() && i < b.objects.size(); ++i)
	{
		const ObjectParts &x = a.objects[i];
		const ObjectParts &y = b.objects[i];
		std::string what;
		if (x.id != y.id || x.templateName != y.templateName)
		{
			what = " another object (" + std::to_string(y.id) + " " + y.templateName + ")";
		}
		else
		{
			if (x.own != y.own)
			{
				what += " its own fields";
				++byModule["(the object's own fields)"];
			}
			for (size_t m = 0; m < x.modules.size() || m < y.modules.size(); ++m)
			{
				if (m >= x.modules.size() || m >= y.modules.size() || x.modules[m] != y.modules[m])
				{
					const std::string name = m < x.modules.size() ? x.modules[m].first : y.modules[m].first;
					what += " module " + std::to_string(m) + " " + name;
					++byModule[name];
				}
			}
		}
		if (!what.empty())
		{
			++objects;
			if (shown++ < 12)
			{
				o << " object " << x.id << " " << x.templateName << ":" << what << ";";
			}
		}
	}
	if (objects)
	{
		o << " " << objects << " objects differ; by part:";
		for (const auto &kv : byModule)
		{
			o << " " << kv.first << " x" << kv.second << ";";
		}
	}
	return o.str();
}

int factionIndex(const PlayerTemplateStore &store, const std::string &name)
{
	for (int i = 0; i < store.getPlayerTemplateCount(); ++i)
	{
		if (store.getNthPlayerTemplate(i)->getName() == name)
		{
			return i;
		}
	}
	return -1;
}

// a slot: who plays it (a human or a Medium computer), the faction (PlayerTemplate index) and the start position
struct Slot
{
	bool human = false;
	int faction = -1;
	int start = 0;
};

NewGameMessage edainMessage(const std::string &map, const std::vector<Slot> &slots, std::uint32_t seed)
{
	NewGameMessage m;
	m.game.mapName = map;
	m.game.seed = seed;
	for (size_t i = 0; i < slots.size(); ++i)
	{
		SkirmishGameSlot &sl = m.game.slots[i];
		sl.state = slots[i].human ? SLOT_PLAYER : SLOT_MED_AI;
		sl.name = slots[i].human ? u"Player" : u"Computer";
		sl.playerTemplate = slots[i].faction;
		REQUIRE(sl.playerTemplate != -1);
		sl.startPos = slots[i].start;
		sl.color = (int)i;
		sl.teamNumber = -1;
	}
	return m;
}
} // namespace

TEST_CASE("ios44 edain save: a skirmish with Edain mounted is saved and loaded into the same START's game: the loaded state hashes as the saved one, "
		  "and saving it again gives the same bytes")
{
	ModWorld *w = edainWorld();
	if (!w)
	{
		retailtest::printSkip("ios44 edain save (set OPENBFME_EDAIN_INSTALL, ROTWK_INSTALL and BFME2_INSTALL)");
		return;
	}
	auto context = w->shared->world->enterContext();
	const std::string map = env("OPENBFME_IOS44_MAP").empty() ? "maps/map mp evendim/map mp evendim.map" : env("OPENBFME_IOS44_MAP");
	const UnsignedInt frame = env("OPENBFME_IOS44_FRAME").empty() ? 150u : (UnsignedInt)std::stoul(env("OPENBFME_IOS44_FRAME"));
	const PlayerTemplateStore &store = w->shared->world->playerTemplates();
	// the game's --save-test setup by default (seed 5813): a human Gondor on Evendim's start 3 and a Medium computer Angmar on start 0 (OPENBFME_IOS44_SLOTS: "P:<faction>:<start>,M:...")
	std::vector<Slot> slots;
	const std::string spec = env("OPENBFME_IOS44_SLOTS").empty() ? "P:FactionMen:3,M:FactionAngmar:0" : env("OPENBFME_IOS44_SLOTS");
	std::stringstream ss(spec);
	for (std::string part; std::getline(ss, part, ',');)
	{
		const size_t c1 = part.find(':'), c2 = part.rfind(':');
		Slot sl;
		sl.human = part[0] == 'P';
		const std::string f = part.substr(c1 + 1, c2 - c1 - 1);
		sl.faction = std::isdigit((unsigned char)f[0]) ? std::stoi(f) : factionIndex(store, f);
		sl.start = std::stoi(part.substr(c2 + 1));
		slots.push_back(sl);
	}
	for (const Slot &sl : slots)
	{
		MESSAGE(std::string(sl.human ? "human " : "computer ") << (sl.faction >= 0 ? store.getNthPlayerTemplate(sl.faction)->getName() : std::string("?")) << " at start " << sl.start);
	}
	const std::uint32_t seed = env("OPENBFME_IOS44_SEED").empty() ? 5813u : (std::uint32_t)std::stoul(env("OPENBFME_IOS44_SEED"));
	const NewGameMessage message = edainMessage(map, slots, seed);
	Breakdown saved;
	std::vector<std::uint8_t> snapshot;
	std::string error;
	{
		Game a;
		load(*w, message, a);
		runTo(a, frame);
		REQUIRE_MESSAGE(a.game->logic().saveSnapshot(snapshot, &error), error);
		saved = breakdown(a.game->logic());
		MESSAGE("saved at frame " << frame << ": " << a.game->logic().getObjectCount() << " objects, " << snapshot.size() << " bytes, state hash " << saved.total);
	}
	Game b;
	load(*w, message, b);
	REQUIRE_MESSAGE(b.game->loadSnapshot(snapshot, &error), error);
	CHECK(b.game->logic().getFrame() == frame);
	const Breakdown loaded = breakdown(b.game->logic());
	CHECK_MESSAGE(loaded.total == saved.total, "differs:" << difference(saved, loaded));
	std::vector<std::uint8_t> again;
	REQUIRE_MESSAGE(b.game->logic().saveSnapshot(again, &error), error);
	CHECK(again == snapshot);
}
