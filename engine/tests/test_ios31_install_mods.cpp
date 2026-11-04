// OpenBFME unit tests: lane IOS-31, install-folder mods (Edain) in the Mods folder (Common/ModMount.h ClassifyModsFolderEntry, PlanModsFolder). GPL-3.0.
//
// NOT RETAIL: OpenBFME's Mods folder (lane IOS-28) with an install-folder mod in it, mounted as --mod-install mounts one (MountInstallOverlay). Every
// archive and record here is written by the test at runtime (BigTestUtil): no retail or mod bytes. The rules checked: which entries are install-folder
// mods (an openbfme-aio.json, an install/ folder, a lang\*.big), the record's stack (the package itself is the entry, its other layers beside it, a
// layer with nothing for RotWK may be absent), one install-folder mod at a time, and the order: the install-folder mod under every -mod-style mod,
// wherever it sits in the list, so a small mod on top wins its files over the install-folder mod's, which win over retail's.

#include "doctest.h"
#include "BigTestUtil.h"

#include "Common/ArchiveFile.h"
#include "Common/ModMount.h"
#include "GameEngineDevice/Win32Device/Common/Win32BIGFileSystem.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <random>

using namespace bigtest;
namespace fs = std::filesystem;

namespace
{

struct TempDir
{
	fs::path path;
	TempDir()
	{
		std::mt19937_64 rng((unsigned long long)std::chrono::steady_clock::now().time_since_epoch().count());
		path = fs::temp_directory_path() / ("openbfme-ios31-" + std::to_string(rng()));
		fs::create_directories(path);
	}
	~TempDir()
	{
		std::error_code ec;
		fs::remove_all(path, ec);
	}
};

void writeFile(const fs::path &p, const std::string &bytes)
{
	fs::create_directories(p.parent_path());
	std::ofstream out(p, std::ios::binary);
	out.write(bytes.data(), (std::streamsize)bytes.size());
}

void writeBig(const fs::path &p, const std::vector<std::pair<std::string, std::string>> &files)
{
	const std::vector<std::uint8_t> big = makeBig("BIGF", files);
	writeFile(p, std::string(big.begin(), big.end()));
}

std::string readVirtual(ArchiveFileSystem &fsys, const std::string &name)
{
	std::vector<std::uint8_t> out;
	std::string error;
	if (!fsys.readFile(name, out, &error))
	{
		return "<missing: " + error + ">";
	}
	return asString(out);
}

std::string joined(const std::vector<std::string> &v)
{
	std::string out;
	for (const std::string &s : v)
	{
		out += s + "\n";
	}
	return out;
}

// the record tools/mod/aio_package.py writes for Edain 4.8.5.4 (schema 2): its BFME2 "assets" layer first (nothing for RotWK), then the package
std::string edainRecord(const std::string &engineEdits = "")
{
	return R"({
 "schema": "openbfme.aio-package 2", "guid": "0ff0ab7a", "name": "Edain", "version": "4.8.5.4", "type": 0,
 "stack": [
  {"folder": "Edain_assets", "name": "Edain assets", "version": "4.8.5.2", "type": 2, "guid": "272d148c", "parts": []},
  {"folder": "Edain", "name": "Edain", "version": "4.8.5.4", "type": 0, "guid": "0ff0ab7a", "parts": ["install"]}
 ],
 "files": 3, "bytes": 1, "engine_edits": [)" + engineEdits + R"(], "left_out": []
})";
}

// an Edain-like install-folder mod: a data archive and lang\English.big (the subfolder archive that replaces the game's), as the AIO tool lays it out
void writeEdain(const fs::path &entry, const std::string &record = edainRecord())
{
	writeBig(entry / "install" / "__edain_data.big", { { "data\\ini\\a.ini", "edain-a" }, { "data\\ini\\b.ini", "edain-b" } });
	writeBig(entry / "install" / "lang" / "English.big", { { "data\\lotr.str", "edain strings" } });
	writeFile(entry / "install" / "Readme.txt", "not an archive");
	writeFile(entry / "openbfme-aio.json", record);
}

} // namespace

TEST_CASE("IOS-31: what a Mods folder entry is: an archive, a -mod folder, or an install-folder mod by its record, its install/ folder or its lang\\*.big")
{
	TempDir tmp;
	const fs::path mods = tmp.path / "Mods";
	writeEdain(mods / "My Edain"); // the player may rename the package's folder: the record's own guid finds it
	writeFile(mods / "Edain_assets" / "openbfme-aio.json",
		R"({"schema": "openbfme.aio-package 2", "guid": "272d148c", "name": "Edain assets", "version": "4.8.5.2", "type": 2, "stack": null, "dependency_only": true})");
	writeBig(mods / "Laid Out" / "Install" / "_mod.big", { { "data\\ini\\a.ini", "laid" } }); // rule 2: install/ (any case), no .big on top
	writeBig(mods / "Laid Out" / "mod" / "!mod.big", { { "data\\ini\\c.ini", "laid-mod" } });
	writeBig(mods / "Game Copy" / "LANG" / "English.big", { { "data\\lotr.str", "copy" } }); // rule 3: a lang\*.big
	writeBig(mods / "Game Copy" / "_copy.big", { { "data\\ini\\a.ini", "copy" } });
	writeBig(mods / "Small" / "zzz_small.big", { { "data\\ini\\a.ini", "small" } }); // a -mod folder
	writeFile(mods / "Small" / "lang" / "readme.txt", "a lang folder without archives stays a -mod folder's loose files");
	writeBig(mods / "Both" / "top.big", { { "data\\ini\\a.ini", "top" } }); // a .big on top: -mod mounts it, so it stays a -mod folder
	fs::create_directories(mods / "Both" / "install");
	writeBig(mods / "Single.big", { { "data\\ini\\a.ini", "single" } });

	auto kindOf = [&](const std::string &name, InstallFolderMod *install = nullptr) {
		ModsFolderEntryKind kind;
		std::string error;
		REQUIRE_MESSAGE(ClassifyModsFolderEntry(mods.u8string(), name, kind, install, &error), error);
		return kind;
	};
	InstallFolderMod edain;
	CHECK(kindOf("My Edain", &edain) == ModsFolderEntryKind::InstallFolder);
	CHECK(edain.name == "My Edain");
	CHECK(edain.title == "Edain 4.8.5.4");
	CHECK(edain.layout == "aio");
	CHECK(edain.overlays == std::vector<std::string>{ (mods / "My Edain" / "install").u8string() });
	CHECK(edain.modPart.empty());
	CHECK(edain.engineMd5s.empty());
	CHECK(edain.notes.empty()); // Edain_assets is there (empty for RotWK) and has no parts

	InstallFolderMod laid;
	CHECK(kindOf("Laid Out", &laid) == ModsFolderEntryKind::InstallFolder);
	CHECK(laid.layout == "install-folder");
	CHECK(laid.title.empty());
	CHECK(laid.overlays == std::vector<std::string>{ (mods / "Laid Out" / "Install").u8string() });
	CHECK(laid.modPart == (mods / "Laid Out" / "mod").u8string());

	InstallFolderMod copy;
	CHECK(kindOf("Game Copy", &copy) == ModsFolderEntryKind::InstallFolder);
	CHECK(copy.layout == "game-folder");
	CHECK(copy.overlays == std::vector<std::string>{ (mods / "Game Copy").u8string() });

	CHECK(kindOf("Edain_assets") == ModsFolderEntryKind::DependencyOnly);
	CHECK(kindOf("Small") == ModsFolderEntryKind::Folder);
	CHECK(kindOf("Both") == ModsFolderEntryKind::Folder);
	CHECK(kindOf("Single.big") == ModsFolderEntryKind::Archive);
	CHECK(kindOf("Gone") == ModsFolderEntryKind::Missing);

	// the tab's size: every file below the entry
	CHECK(ModsFolderEntryBytes((mods / "Single.big").u8string()) == (std::uint64_t)fs::file_size(mods / "Single.big"));
	CHECK(ModsFolderEntryBytes((mods / "Small").u8string()) ==
		(std::uint64_t)(fs::file_size(mods / "Small" / "zzz_small.big") + fs::file_size(mods / "Small" / "lang" / "readme.txt")));
	CHECK(ModsFolderEntryBytes((mods / "Gone").u8string()) == 0);
}

TEST_CASE("IOS-31: an install-folder mod's record: absent layers, engine programs, and the errors that name what is wrong")
{
	TempDir tmp;
	const fs::path mods = tmp.path / "Mods";
	ModsFolderEntryKind kind;
	std::string error;

	// a layer with nothing for RotWK (Edain's BFME2 assets) may be absent: noted, not needed
	writeEdain(mods / "Edain", edainRecord(R"("Edain: game.dat md5 5c31f503aa")"));
	InstallFolderMod edain;
	REQUIRE_MESSAGE(ClassifyModsFolderEntry(mods.u8string(), "Edain", kind, &edain, &error), error);
	CHECK(kind == ModsFolderEntryKind::InstallFolder);
	CHECK(edain.notes == std::vector<std::string>{ "install mod Edain: Edain assets has nothing for RotWK and is not in the Mods folder (not needed)" });
	CHECK(edain.engineMd5s == std::vector<std::string>{ "5c31f503aa" }); // ModEngineFeatures::activate's key (the launcher's --mod-engine)

	// a layer that has files for RotWK must be beside it
	const std::string needsPatch = R"({"schema": "openbfme.aio-package 2", "guid": "g1", "name": "Mod", "version": "1", "type": 0, "stack": [
		{"folder": "Mod", "name": "Mod", "guid": "g1", "parts": ["install"]},
		{"folder": "Patch_2.02", "name": "Patch 2.02", "guid": "g2", "parts": ["install"]}], "engine_edits": []})";
	writeBig(mods / "Mod" / "install" / "_m.big", { { "a", "b" } });
	writeFile(mods / "Mod" / "openbfme-aio.json", needsPatch);
	CHECK_FALSE(ClassifyModsFolderEntry(mods.u8string(), "Mod", kind, &edain, &error));
	CHECK(error == "mods: 'Mod' needs Patch 2.02 (the folder Patch_2.02, laid out with it by tools/mod/aio_package.py) beside it in the Mods folder");
	// with it there, its install/ folder comes after the package's (the record's priority order)
	writeBig(mods / "Patch_2.02" / "install" / "_p.big", { { "a", "p" } });
	InstallFolderMod mod;
	REQUIRE_MESSAGE(ClassifyModsFolderEntry(mods.u8string(), "Mod", kind, &mod, &error), error);
	CHECK(mod.overlays == std::vector<std::string>{ (mods / "Mod" / "install").u8string(), (mods / "Patch_2.02" / "install").u8string() });

	// an incomplete copy: the record names install/ but the folder is not there
	writeFile(mods / "Half" / "openbfme-aio.json",
		R"({"schema": "openbfme.aio-package 2", "guid": "h", "name": "Half", "version": "1", "stack": [{"folder": "Half", "name": "Half", "guid": "h", "parts": ["install"]}]})");
	CHECK_FALSE(ClassifyModsFolderEntry(mods.u8string(), "Half", kind, &mod, &error));
	CHECK(error == "mods: 'Half': Half's install folder is missing: the copy is incomplete");

	// a record that does not parse, or is something else
	writeFile(mods / "Broken" / "openbfme-aio.json", "{\"schema\": ");
	CHECK_FALSE(ClassifyModsFolderEntry(mods.u8string(), "Broken", kind, &mod, &error));
	CHECK(error.rfind("mods: 'Broken': its openbfme-aio.json does not parse (", 0) == 0);
	writeFile(mods / "Other" / "openbfme-aio.json", "{\"schema\": \"something else\"}");
	CHECK_FALSE(ClassifyModsFolderEntry(mods.u8string(), "Other", kind, &mod, &error));
	CHECK(error == "mods: 'Other': its openbfme-aio.json is not an All In One package record (schema \"openbfme.aio-package\")");

	// a name with a path in it is refused before anything is read
	CHECK_FALSE(ClassifyModsFolderEntry(mods.u8string(), "../Mods/Edain", kind, &mod, &error));
	CHECK(error == "mods: '../Mods/Edain' is not the name of a mod in the Mods folder (a folder or a .big file directly in it)");
}

TEST_CASE("IOS-31: the enabled list: one install-folder mod at a time, taken out of the -mod list wherever it sits; a layer alone is refused")
{
	TempDir tmp;
	const fs::path mods = tmp.path / "Mods";
	writeEdain(mods / "Edain");
	writeBig(mods / "Unchained" / "install" / "__edain_data.big", { { "data\\ini\\a.ini", "unchained" } });
	writeFile(mods / "Edain_assets" / "openbfme-aio.json",
		R"({"schema": "openbfme.aio-package 2", "guid": "272d148c", "name": "Edain assets", "version": "4.8.5.2", "stack": null, "dependency_only": true})");
	writeBig(mods / "Small" / "zzz_small.big", { { "data\\ini\\a.ini", "small" } });
	writeBig(mods / "Tweak.big", { { "data\\ini\\b.ini", "tweak" } });

	ModsFolderPlan plan;
	std::string error;
	// the install-folder mod last in the list (turned on after the small mods) is still mounted first, under them
	REQUIRE_MESSAGE(PlanModsFolder(mods.u8string(), { "Small", "Tweak.big", "Edain", "Gone" }, plan, &error), error);
	CHECK(plan.hasInstall);
	CHECK(plan.install.name == "Edain");
	CHECK(plan.modNames == std::vector<std::string>{ "Small", "Tweak.big", "Gone" }); // Gone: ModsFolderOperands reports it missing

	REQUIRE_MESSAGE(PlanModsFolder(mods.u8string(), { "Small" }, plan, &error), error);
	CHECK_FALSE(plan.hasInstall);
	CHECK(plan.modNames == std::vector<std::string>{ "Small" });

	// two install-folder mods: refused, naming both
	CHECK_FALSE(PlanModsFolder(mods.u8string(), { "Edain", "Small", "Unchained" }, plan, &error));
	CHECK(error == "mods: 'Edain' and 'Unchained' are both install-folder mods, and only one can be on at a time (each replaces the game folder's files): "
				   "turn one of them off in Options > Mods");
	CHECK_FALSE(plan.hasInstall);

	// a layer laid out for another package is not a mod of its own
	CHECK_FALSE(PlanModsFolder(mods.u8string(), { "Edain_assets" }, plan, &error));
	CHECK(error == "mods: 'Edain_assets' is a part of another mod (an All In One package's layer), not a mod of its own: turn on the mod that needs it instead");
}

TEST_CASE("IOS-31: precedence: a small mod over the install-folder mod over retail; the install mod's lang\\English.big replaces the game's")
{
	TempDir tmp;
	// the "retail" install as MountRetailArchives reports it (test_mods1_mount.cpp MODS-2 builds it the same way)
	writeBig(tmp.path / "rotwk" / "INI.big",
		{ { "data\\ini\\a.ini", "retail-a" }, { "data\\ini\\b.ini", "retail-b" }, { "data\\ini\\c.ini", "retail-c" }, { "data\\ini\\d.ini", "retail-d" } });
	writeBig(tmp.path / "rotwk" / "lang" / "English.big", { { "data\\lotr.str", "retail strings" } });
	RetailMountReport retail;
	retail.ok = true;
	for (const std::string &path : { std::string("INI.big"), std::string("lang/English.big") })
	{
		const fs::path disk = tmp.path / "rotwk" / fs::u8path(path);
		retail.mounted.push_back({ "rotwk", path, disk.u8string(), (std::uint64_t)fs::file_size(disk), "md5-" + path });
	}
	const fs::path mods = tmp.path / "Mods";
	writeEdain(mods / "Edain");
	writeBig(mods / "Small" / "zzz_small.big", { { "data\\ini\\a.ini", "small-a" } });
	writeBig(mods / "Tweak.big", { { "data\\ini\\c.ini", "tweak-c" } });

	// the list as the Mods tab writes it: Edain turned on last
	ModsFolderPlan plan;
	std::string error;
	REQUIRE_MESSAGE(PlanModsFolder(mods.u8string(), { "Small", "Tweak.big", "Edain" }, plan, &error), error);
	REQUIRE(plan.hasInstall);

	// RetailFileSystem::mountFrom's order: the install overlay first (the same call as --mod-install), then the -mod-style mods over it
	Win32BIGFileSystem fsys;
	const ModMountReport overlay = MountInstallOverlay(fsys, retail, plan.install.overlays, ModMountOptions());
	REQUIRE_MESSAGE(overlay.ok, joined(overlay.errors));
	CHECK(overlay.folderName == "Edain"); // an install/ folder is named after the package folder it sits in (MountInstallOverlay)
	CHECK(overlay.archives.size() == 2); // __edain_data.big and lang/English.big (the subfolder archive)
	CHECK(overlay.notes == std::vector<std::string>{ "install mod Edain: Readme.txt is not an archive: not used" });
	std::vector<ModOperand> ops;
	std::vector<std::string> missing;
	REQUIRE_MESSAGE(ModsFolderOperands(mods.u8string(), plan.modNames, ops, missing, &error), error);
	ModMountOptions options;
	options.rotwkInstallRoot = (tmp.path / "rotwk").u8string();
	const ModMountReport small = MountRetailMods(fsys, ops, options);
	REQUIRE_MESSAGE(small.ok, joined(small.errors));

	CHECK(readVirtual(fsys, "data\\ini\\a.ini") == "small-a");      // the small mod over Edain
	CHECK(readVirtual(fsys, "data\\ini\\c.ini") == "tweak-c");      // the small mod over retail
	CHECK(readVirtual(fsys, "data\\ini\\b.ini") == "edain-b");      // Edain over retail
	CHECK(readVirtual(fsys, "data\\ini\\d.ini") == "retail-d");     // retail where nobody replaces it
	CHECK(readVirtual(fsys, "data\\lotr.str") == "edain strings");  // Edain's lang\English.big replaced the game's file of that path
	// the identity: the install mod's lines first (RetailFileSystem::modIdentity), then one line per small mod in mount order
	REQUIRE(overlay.identity.size() == 2);
	CHECK(overlay.identity[0] == "mod install Edain");
	CHECK(small.identity.size() == 3);
	CHECK(small.identity[0] == "mod folder Small");
	CHECK(small.identity[1] == "mod archive Tweak.big");
	CHECK(small.identity[2].rfind("modcontent 2 archives 1 files ", 0) == 0); // a folder's archive is one of its loose files too
}
