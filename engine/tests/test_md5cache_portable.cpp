// OpenBFME unit tests: the md5 cache's keys (Common/Md5Cache.h) for files inside the cache's own folder. GPL-3.0.
//
// Md5Cache::portable keys a file inside the cache's folder by its path relative to that folder, so the cache still hits when the whole
// folder moves (iOS moves an app's data container on every update or reinstall); a file elsewhere keeps its absolute key. Every archive
// here is written by the test at runtime (BigTestUtil): no retail bytes.

#include "doctest.h"
#include "BigTestUtil.h"

#include "Common/MD5.h"
#include "Common/Md5Cache.h"
#include "Common/ModMount.h"
#include "Common/RetailArchivePolicy.h"
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
		path = fs::temp_directory_path() / ("openbfme-md5cache-" + std::to_string(rng()));
		fs::create_directories(path);
	}
	~TempDir()
	{
		std::error_code ec;
		fs::remove_all(path, ec);
	}
};

void writeFile(const fs::path &p, const std::vector<std::uint8_t> &bytes)
{
	fs::create_directories(p.parent_path());
	std::ofstream out(p, std::ios::binary);
	out.write(reinterpret_cast<const char *>(bytes.data()), (std::streamsize)bytes.size());
}

RetailArchiveEntry entryFor(const std::string &canonical, const std::vector<std::uint8_t> &bytes)
{
	RetailArchiveEntry e;
	e.path = canonical;
	e.size = bytes.size();
	e.md5 = MD5::ofBytes(bytes.data(), bytes.size());
	return e;
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

} // namespace

TEST_CASE("md5 cache: a file inside the cache's folder is keyed relative to it, a file elsewhere keeps its absolute key")
{
	Md5Cache before;
	before.path = "/var/mobile/Containers/Data/Application/AAAA/Documents/retail-md5-cache.tsv";
	Md5Cache after;
	after.path = "/var/mobile/Containers/Data/Application/BBBB/Documents/retail-md5-cache.tsv";
	const std::string a = Md5Cache::key("/var/mobile/Containers/Data/Application/AAAA/Documents/RotWK/ini.big", 42, 7);
	// iOS reports the same folder as /private/var/... or /var/...
	const std::string b = Md5Cache::key("/private/var/mobile/Containers/Data/Application/BBBB/Documents/RotWK/ini.big", 42, 7);
	CHECK(before.portable(a) == "42\t7\t./RotWK/ini.big");
	CHECK(after.portable(b) == "42\t7\t./RotWK/ini.big");
	// a file outside the cache's folder (a desktop install) keeps its absolute key
	Md5Cache desktop;
	desktop.path = "/data/godot/app_userdata/OpenBFME/retail-md5-cache.tsv";
	const std::string d = Md5Cache::key("/games/RotWK/ini.big", 42, 7);
	CHECK(desktop.portable(d) == d);
	// a sibling folder whose name only starts like the cache's folder is outside it
	const std::string sibling = Md5Cache::key("/var/mobile/Containers/Data/Application/AAAA/Documents2/RotWK/ini.big", 42, 7);
	CHECK(before.portable(sibling) == sibling);
	// size and modification time stay in the key: a changed file is a different key
	CHECK(after.portable(Md5Cache::key("/var/mobile/Containers/Data/Application/BBBB/Documents/RotWK/ini.big", 43, 7)) == "43\t7\t./RotWK/ini.big");
	// no cache path: unchanged
	Md5Cache none;
	CHECK(none.portable(a) == a);
}

TEST_CASE("md5 cache: the retail mount and a -mod mount hash nothing again after their whole folder moved")
{
	TempDir tmp;
	const fs::path before = tmp.path / "container-a";
	const fs::path after = tmp.path / "container-b";

	auto rIni = makeBig("BIGF", { { "data\\ini\\weapon.ini", "rotwk-base" }, { "data\\ini\\armor.ini", "rotwk-armor" } });
	auto rPatch = makeBig("BIG4", { { "data\\ini\\weapon.ini", "rotwk-201" } });
	auto bIni = makeBig("BIGF", { { "data\\ini\\weapon.ini", "bfme2" } });
	auto mod = makeBig("BIGF", { { "data\\ini\\a.ini", "mod-a" } });
	writeFile(before / "RotWK" / "ini.big", rIni);
	writeFile(before / "RotWK" / "_patch201ini.big", rPatch);
	writeFile(before / "BFME2" / "ini.big", bIni);
	writeFile(before / "MyMod" / "m.big", mod);

	auto installs = [&](const fs::path &root) {
		RetailInstall rotwk;
		rotwk.label = "rotwk";
		rotwk.root = (root / "RotWK").u8string();
		rotwk.policy.game = "rotwk";
		rotwk.policy.patch = "2.01";
		rotwk.policy.archives = { entryFor("INI.big", rIni), entryFor("_patch201ini.big", rPatch) };
		RetailInstall bfme2;
		bfme2.label = "bfme2";
		bfme2.root = (root / "BFME2").u8string();
		bfme2.policy.game = "bfme2";
		bfme2.policy.patch = "1.06";
		bfme2.policy.archives = { entryFor("ini.big", bIni) };
		return std::vector<RetailInstall>{ rotwk, bfme2 };
	};
	auto mountRetail = [&](const fs::path &root) {
		RetailMountOptions options;
		options.md5CachePath = (root / "retail-md5-cache.tsv").u8string();
		Win32BIGFileSystem fsys;
		return MountRetailArchives(fsys, installs(root), options);
	};
	auto mountMod = [&](const fs::path &root) {
		ModOperand op;
		op.dir = (root / "MyMod").u8string() + "/";
		ModMountOptions options;
		options.rotwkInstallRoot = (root / "RotWK").u8string();
		options.md5CachePath = (root / "mod-md5-cache.tsv").u8string();
		Win32BIGFileSystem fsys;
		return MountRetailMod(fsys, op, options);
	};

	const RetailMountReport first = mountRetail(before);
	REQUIRE_MESSAGE(first.ok, joined(first.errors));
	CHECK(first.archivesHashed == 3);
	CHECK(first.md5CacheHits == 0);
	const ModMountReport firstMod = mountMod(before);
	REQUIRE_MESSAGE(firstMod.ok, joined(firstMod.errors));
	CHECK(firstMod.filesHashed == 1);
	CHECK(firstMod.md5CacheHits == 0);

	// the whole folder moves, as an app's data container does on an update: same files, same sizes and times, another absolute path
	fs::rename(before, after);
	const RetailMountReport moved = mountRetail(after);
	REQUIRE_MESSAGE(moved.ok, joined(moved.errors));
	CHECK(moved.archivesHashed == 0);
	CHECK(moved.md5CacheHits == 3);
	const ModMountReport movedMod = mountMod(after);
	REQUIRE_MESSAGE(movedMod.ok, joined(movedMod.errors));
	CHECK(movedMod.filesHashed == 0);
	CHECK(movedMod.md5CacheHits == 2); // m.big as the folder's archive and as one of its loose files (hashed once in the first mount)
	CHECK(movedMod.identity == firstMod.identity);
}
