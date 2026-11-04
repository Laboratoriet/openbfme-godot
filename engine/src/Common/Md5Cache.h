// OpenBFME. GPL-3.0.
//
// The md5 cache of mounted files (lane INI-1's RetailArchivePolicy mount; shared with the -mod mount, Common/ModMount.h, lane MODS-1):
// md5 by "size, last-write time, path" (the path absolute, or relative to the cache's folder for a file inside it: portable(), lane IOS-34).
// A missing or damaged cache only costs a rehash.

#pragma once

#include <algorithm>
#include "Common/PathIO.h"

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <map>
#include <string>
#include <system_error>

// Threat model: the md5 check (and this cache) detects wrong or modified game files, such as a
// mod, a patch or a damaged copy. A cache hit trusts "same absolute path + size + last-write time",
// so it does not stop deliberate tampering by someone who edits a file and then restores its
// timestamp (or who edits the cache). That is accepted: cross-play integrity comes from the
// retail INI/logic CRCs exchanged between players, not from this cache.
struct Md5Cache
{
	std::map<std::string, std::string> entries; // "size\tmtime\tpath" -> md5
	std::string path;
	bool dirty = false;

	static std::string key(const std::string &file, std::uint64_t size, long long mtime)
	{
		return std::to_string(size) + "\t" + std::to_string(mtime) + "\t" + file;
	}

	// lane IOS-34: the key as the cache stores it. A file inside the cache's own folder keeps its path relative to that folder
	// ("./RotWK/..."): iOS moves an app's data container (.../Containers/Data/Application/<UUID>) when the app is updated or
	// reinstalled, and absolute keys then missed every file (the iPhone Duo re-hashed its 8.5 GB of archives, 14.7 s, on the first
	// start after each install). A file anywhere else keeps its absolute path, as before. /private/var and /var are one folder on iOS.
	std::string portable(const std::string &key) const
	{
		const size_t t1 = key.find('\t');
		const size_t t2 = t1 == std::string::npos ? std::string::npos : key.find('\t', t1 + 1);
		if (t2 == std::string::npos || path.empty())
		{
			return key;
		}
		auto strip = [](std::string s) {
			std::replace(s.begin(), s.end(), '\\', '/');
			if (s.rfind("/private/var/", 0) == 0)
			{
				s.erase(0, 8);
			}
			return s;
		};
		const std::string root = strip(std::filesystem::path(PathIO::native(path)).parent_path().u8string()) + "/";
		const std::string file = strip(key.substr(t2 + 1));
		if (root.size() < 2 || file.compare(0, root.size(), root) != 0)
		{
			return key;
		}
		return key.substr(0, t2 + 1) + "./" + file.substr(root.size());
	}

	static bool isMd5Hex(const std::string &s)
	{
		if (s.size() != 32)
		{
			return false;
		}
		for (char c : s)
		{
			if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
			{
				return false;
			}
		}
		return true;
	}

	// A missing or damaged cache is only a lost speed-up (every key mismatch rehashes), so lines
	// that do not parse are dropped here; they never reach a verification decision.
	void load()
	{
		if (path.empty())
		{
			return;
		}
		std::ifstream in(PathIO::native(path));
		std::string line;
		while (std::getline(in, line))
		{
			if (!line.empty() && line.back() == '\r')
			{
				line.pop_back();
			}
			size_t tab = line.find('\t');
			if (tab == std::string::npos || !isMd5Hex(line.substr(0, tab)))
			{
				continue;
			}
			entries[line.substr(tab + 1)] = line.substr(0, tab);
		}
	}

	// Writes to a sibling temp file and renames over the cache, so a crash or a second process
	// never leaves a half-written cache. Returns an empty string or a warning text.
	std::string save()
	{
		if (path.empty() || !dirty)
		{
			return std::string();
		}
		std::error_code ec;
		std::filesystem::path target = PathIO::native(path);
		std::filesystem::create_directories(target.parent_path(), ec);
		std::filesystem::path temp = target;
		temp += ".tmp";
		{
			std::ofstream out(temp, std::ios::trunc);
			for (const auto &e : entries)
			{
				out << e.second << '\t' << e.first << '\n';
			}
			out.flush();
			if (!out)
			{
				return "could not write the md5 cache " + temp.u8string() + "; every mount will rehash";
			}
		}
		std::filesystem::rename(temp, target, ec);
		if (ec)
		{
			std::filesystem::remove(temp, ec);
			return "could not replace the md5 cache " + path + ": " + ec.message() + "; every mount will rehash";
		}
		return std::string();
	}
};
