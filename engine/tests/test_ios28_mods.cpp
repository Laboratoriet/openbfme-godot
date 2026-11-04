// OpenBFME unit tests: lane IOS-28, several mods from the Mods folder (Common/ModMount.h MountRetailMods, ModsFolderOperands). GPL-3.0.
//
// NOT RETAIL: an OpenBFME extension of RotWK's single -mod (test_mods1_mount.cpp has retail's). Every archive and file here is written by the test
// at runtime (BigTestUtil): no retail bytes. The rules checked: the operands mount one after another with overwrite, so a later one (higher priority)
// wins a name; the folders' loose files make one layer in which the later folder wins and which answers before every archive; one "mod ..." identity
// line per operand in mount order; one operand is exactly MountRetailMod; a missing name is left out and reported; a failure mounts nothing.

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
		path = fs::temp_directory_path() / ("openbfme-ios28-" + std::to_string(rng()));
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

void mountBase(Win32BIGFileSystem &fsys)
{
	std::string error;
	auto base = fsys.openArchiveFromMemory("rotwk/INI.big",
		std::make_shared<const std::vector<std::uint8_t>>(makeBig("BIGF", { { "data\\ini\\a.ini", "retail-a" }, { "data\\ini\\b.ini", "retail-b" },
																		  { "data\\ini\\c.ini", "retail-c" }, { "data\\ini\\d.ini", "retail-d" } })),
		&error);
	REQUIRE_MESSAGE(base, error);
	fsys.mountArchive(std::move(base), "rotwk/INI.big", false);
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

ModMountOptions optionsIn(const TempDir &tmp)
{
	ModMountOptions options;
	options.rotwkInstallRoot = (tmp.path / "install").u8string();
	fs::create_directories(options.rotwkInstallRoot);
	return options;
}

} // namespace

TEST_CASE("IOS-28: the Mods folder's names become operands in order; a folder is a folder mod, a .big an archive mod; a missing one is reported")
{
	TempDir tmp;
	const fs::path mods = tmp.path / "Mods";
	fs::create_directories(mods / "Folder Mod");
	writeFile(mods / "Single.BIG", "x");
	writeFile(mods / "notes.txt", "y");

	std::vector<ModOperand> ops;
	std::vector<std::string> missing;
	std::string error;
	REQUIRE_MESSAGE(ModsFolderOperands(mods.u8string(), { "Single.BIG", "Gone", "Folder Mod" }, ops, missing, &error), error);
	REQUIRE(ops.size() == 2);
	CHECK(ops[0].archive == (mods / "Single.BIG").u8string());
	CHECK(ops[0].dir.empty());
	CHECK(ops[1].dir == (mods / "Folder Mod").u8string() + "/");
	CHECK(ops[1].archive.empty());
	CHECK(missing == std::vector<std::string>{ "Gone" });

	// nothing enabled: no operand, nothing missing
	REQUIRE(ModsFolderOperands(mods.u8string(), {}, ops, missing, &error));
	CHECK(ops.empty());
	CHECK(missing.empty());

	// errors: a path (it could leave the folder), a name twice (without case, as the folder's file system), a file that is not an archive
	CHECK_FALSE(ModsFolderOperands(mods.u8string(), { "../Mods/Single.BIG" }, ops, missing, &error));
	CHECK(error == "mods: '../Mods/Single.BIG' is not the name of a mod in the Mods folder (a folder or a .big file directly in it)");
	CHECK_FALSE(ModsFolderOperands(mods.u8string(), { "a\\b" }, ops, missing, &error));
	CHECK_FALSE(ModsFolderOperands(mods.u8string(), { ".." }, ops, missing, &error));
	CHECK_FALSE(ModsFolderOperands(mods.u8string(), { "" }, ops, missing, &error));
	CHECK_FALSE(ModsFolderOperands(mods.u8string(), { "Single.BIG", "single.big" }, ops, missing, &error));
	CHECK(error == "mods: 'single.big' is enabled twice");
	CHECK_FALSE(ModsFolderOperands(mods.u8string(), { "notes.txt" }, ops, missing, &error));
	CHECK(error == "mods: 'notes.txt' in " + mods.u8string() + " is neither a folder nor a .big file");
}

TEST_CASE("IOS-28: several mods: a later mod wins a name over an earlier one and over retail; the order is logged and identified")
{
	TempDir tmp;
	const fs::path mods = tmp.path / "Mods";
	writeBig(mods / "Low.big", { { "data\\ini\\a.ini", "low-a" }, { "data\\ini\\b.ini", "low-b" } });
	writeBig(mods / "Mid" / "m1.big", { { "data\\ini\\a.ini", "mid-a" }, { "data\\ini\\c.ini", "mid-c" } });
	writeFile(mods / "Mid" / "mod.txt", "Title = Mid");
	writeBig(mods / "High.big", { { "data\\ini\\c.ini", "high-c" } });

	std::vector<ModOperand> ops;
	std::vector<std::string> missing;
	std::string error;
	REQUIRE_MESSAGE(ModsFolderOperands(mods.u8string(), { "Low.big", "Mid", "High.big" }, ops, missing, &error), error);
	Win32BIGFileSystem fsys;
	mountBase(fsys);
	const ModMountReport report = MountRetailMods(fsys, ops, optionsIn(tmp));
	REQUIRE_MESSAGE(report.ok, joined(report.errors));

	CHECK(readVirtual(fsys, "data\\ini\\a.ini") == "mid-a");   // Mid is mounted after Low
	CHECK(readVirtual(fsys, "data\\ini\\b.ini") == "low-b");   // only Low has it: Low beats retail
	CHECK(readVirtual(fsys, "data\\ini\\c.ini") == "high-c");  // High is mounted last
	CHECK(readVirtual(fsys, "data\\ini\\d.ini") == "retail-d");
	CHECK(readVirtual(fsys, "mod.txt") == "Title = Mid");      // a folder mod's loose files are the game's files (retail: "<modDir>\<file>")
	CHECK(fsys.sourcesOf("data\\ini\\a.ini") ==
		std::vector<std::string>{ (mods / "Mid" / "m1.big").u8string(), (mods / "Low.big").u8string(), "rotwk/INI.big" });

	REQUIRE(report.archives.size() == 3);
	CHECK(report.archives[0].canonicalPath == "Low.big");
	CHECK(report.archives[1].canonicalPath == "m1.big");
	CHECK(report.archives[2].canonicalPath == "High.big");
	CHECK(report.order == std::vector<std::string>{ "1 of 3: Low.big (archive)", "2 of 3: Mid (folder, 1 archive, 2 files)", "3 of 3: High.big (archive)" });
	REQUIRE(report.identity.size() == 4);
	CHECK(report.identity[0] == "mod archive Low.big");
	CHECK(report.identity[1] == "mod folder Mid");
	CHECK(report.identity[2] == "mod archive High.big");
	CHECK(report.identity[3].rfind("modcontent 3 archives 2 files ", 0) == 0);
	CHECK(report.folderName == "Mid");
	CHECK(report.loose.root == (mods / "Mid").u8string() + "/");

	// another order is another game: the identity changes with it
	REQUIRE(ModsFolderOperands(mods.u8string(), { "High.big", "Mid", "Low.big" }, ops, missing, &error));
	Win32BIGFileSystem other;
	mountBase(other);
	const ModMountReport swapped = MountRetailMods(other, ops, optionsIn(tmp));
	REQUIRE_MESSAGE(swapped.ok, joined(swapped.errors));
	CHECK(readVirtual(other, "data\\ini\\a.ini") == "low-a");
	CHECK(readVirtual(other, "data\\ini\\c.ini") == "mid-c");
	CHECK(swapped.identity[0] == "mod archive High.big");
	CHECK(swapped.identity[3] != report.identity[3]);
}

TEST_CASE("IOS-28: two folder mods make one loose layer: the later folder wins a path (noted), and loose files answer before every archive")
{
	TempDir tmp;
	const fs::path mods = tmp.path / "Mods";
	writeFile(mods / "First" / "data" / "ini" / "a.ini", "first-a");
	writeFile(mods / "First" / "data" / "ini" / "b.ini", "first-b");
	writeFile(mods / "Second" / "data" / "ini" / "a.ini", "second-a");
	writeBig(mods / "Second" / "s.big", { { "data\\ini\\b.ini", "second-big-b" } });

	std::vector<ModOperand> ops;
	std::vector<std::string> missing;
	std::string error;
	REQUIRE(ModsFolderOperands(mods.u8string(), { "First", "Second" }, ops, missing, &error));
	Win32BIGFileSystem fsys;
	mountBase(fsys);
	const ModMountReport report = MountRetailMods(fsys, ops, optionsIn(tmp));
	REQUIRE_MESSAGE(report.ok, joined(report.errors));
	CHECK(readVirtual(fsys, "data\\ini\\a.ini") == "second-a");
	// retail's prefer-local-files rule for its one folder, kept for all: First's loose b.ini answers before Second's archive (documented, ModMount.h)
	CHECK(readVirtual(fsys, "data\\ini\\b.ini") == "first-b");
	CHECK(report.notes == std::vector<std::string>{ "mods: Second's data\\ini\\a.ini replaces First's" });
	REQUIRE(report.loose.files.size() == 3); // a.ini (Second's), b.ini (First's), s.big
	CHECK(report.loose.files[0].diskPath == (mods / "Second" / "data" / "ini" / "a.ini").u8string());
	CHECK(report.loose.root == (mods / "Second").u8string() + "/");
}

TEST_CASE("IOS-28: one operand mounts and identifies exactly as MountRetailMod; a bad mod in the list mounts nothing")
{
	TempDir tmp;
	const fs::path mods = tmp.path / "Mods";
	writeBig(mods / "Only" / "o.big", { { "data\\ini\\a.ini", "only-a" } });
	writeFile(mods / "Only" / "readme.txt", "r");
	writeFile(mods / "Broken.big", "not an archive");
	writeBig(mods / "Good.big", { { "data\\ini\\d.ini", "good-d" } });

	std::vector<ModOperand> ops;
	std::vector<std::string> missing;
	std::string error;
	REQUIRE(ModsFolderOperands(mods.u8string(), { "Only" }, ops, missing, &error));
	Win32BIGFileSystem a, b;
	mountBase(a);
	mountBase(b);
	const ModMountReport list = MountRetailMods(a, ops, optionsIn(tmp));
	const ModMountReport single = MountRetailMod(b, ops[0], optionsIn(tmp));
	REQUIRE(list.ok);
	REQUIRE(single.ok);
	CHECK(list.identity == single.identity);
	CHECK(list.manifest == single.manifest);
	CHECK(list.identity == std::vector<std::string>{ "mod folder Only", list.identity[1] });
	CHECK(list.order == std::vector<std::string>{ "1 of 1: Only (folder, 1 archive, 2 files)" });

	REQUIRE(ModsFolderOperands(mods.u8string(), { "Good.big", "Broken.big" }, ops, missing, &error));
	Win32BIGFileSystem c;
	mountBase(c);
	const ModMountReport bad = MountRetailMods(c, ops, optionsIn(tmp));
	CHECK_FALSE(bad.ok);
	REQUIRE(bad.errors.size() == 1);
	CHECK(bad.errors[0].rfind("mod: Broken.big is not a valid archive: ", 0) == 0);
	CHECK(readVirtual(c, "data\\ini\\d.ini") == "retail-d"); // Good.big was not mounted either
	CHECK_FALSE(c.preferLocalFiles());

	CHECK_FALSE(MountRetailMods(c, {}, optionsIn(tmp)).ok); // an empty list is the caller's business (RetailFileSystem mounts nothing then)
}
