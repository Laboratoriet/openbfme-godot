// OpenBFME. GPL-3.0.
//
// Lane IOS-34: Md5Cache::portable keys a file inside the cache's own folder by its path relative to that folder, so the cache
// survives iOS moving the app's data container on an update or reinstall; a file elsewhere keeps its absolute key.

#include "doctest.h"

#include "Common/Md5Cache.h"

TEST_CASE("ios34 md5 cache: keys relative to the cache's folder survive a moved container")
{
	Md5Cache before;
	before.path = "/var/mobile/Containers/Data/Application/AAAA/Documents/retail-md5-cache.tsv";
	Md5Cache after;
	after.path = "/var/mobile/Containers/Data/Application/BBBB/Documents/retail-md5-cache.tsv";
	const std::string a = Md5Cache::key("/var/mobile/Containers/Data/Application/AAAA/Documents/RotWK/ini.big", 42, 7);
	const std::string b = Md5Cache::key("/private/var/mobile/Containers/Data/Application/BBBB/Documents/RotWK/ini.big", 42, 7);
	CHECK(before.portable(a) == "42\t7\t./RotWK/ini.big");
	CHECK(after.portable(b) == before.portable(a));
	// a file outside the cache's folder (a desktop install) keeps its absolute key
	Md5Cache desktop;
	desktop.path = "/Users/x/Library/Application Support/Godot/app_userdata/OpenBFME/retail-md5-cache.tsv";
	const std::string d = Md5Cache::key("/Games/RotWK/ini.big", 42, 7);
	CHECK(desktop.portable(d) == d);
	// size and time still decide: a changed file is a different key
	CHECK(after.portable(Md5Cache::key("/var/mobile/Containers/Data/Application/BBBB/Documents/RotWK/ini.big", 43, 7)) != before.portable(a));
	// no cache path: unchanged
	Md5Cache none;
	CHECK(none.portable(a) == a);
}
