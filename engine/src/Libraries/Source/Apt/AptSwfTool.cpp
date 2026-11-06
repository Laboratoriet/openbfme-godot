// OpenBFME. GPL-3.0.
//
// openbfme_apt_swf: the APT <-> SWF converter's command line (docs/APT-SWF.md).
//
//   openbfme_apt_swf export    (--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR [--no-embed] [--resolve-strings]
//   openbfme_apt_swf roundtrip (--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR
//   openbfme_apt_swf import    FILE.swf --out DIR
//   openbfme_apt_swf reassemble (--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR [--write]   (every action program
//                              back to APT; --write: also the movies with every program replaced by its re-assembled copy, in DIR/files)
//   openbfme_apt_swf info      FILE.swf [--all]
//   openbfme_apt_swf apply     RECIPE.txt (--dir FOLDER | --big ARCHIVE... | --game rotwk|bfme2 | --swf FILE.swf) --out DIR [--pack OUT.big]
//   openbfme_apt_swf set-text  IN.swf OUT.swf CHARACTER_ID TEXT
//   openbfme_apt_swf move      IN.swf OUT.swf SPRITE_ID FRAME DEPTH DX DY   (SPRITE_ID 0 = the root timeline; pixels)
//   openbfme_apt_swf pack-big  DIR OUT.big
//
// --game mounts the retail archives the way the game does (RetailArchivePolicy, ROTWK_INSTALL / BFME2_INSTALL) and converts
// every movie of the mount, each from the archive that provides it.  --big converts every movie in the given archives (a mod's
// apt archives), with the game mount (--game, default rotwk when the installs are set) behind them for textures.
// Without --game, --big reads the archives alone: the movies, and their textures (art/Textures/apt_<movie>_<n>.tga, which each
// movie's BIG carries) from the archives given.  The standalone build (OPENBFME_APTSWF_STANDALONE, the Windows command line for
// modders: engine/cmake/AptSwf.cmake) has only that mode: no retail mount, no --resolve-strings.
// The game files are read at run time and written only to --out; nothing of them belongs in the repository.

#ifndef OPENBFME_APTSWF_STANDALONE
#include "Common/ArchiveFile.h"
#include "Common/RetailArchivePolicy.h"
#include "GameClient/AptCanvas.h"
#include "GameClient/GameText.h"
#include "GameEngineDevice/Win32Device/Common/Win32BIGFileSystem.h"
#include "Libraries/Source/Apt/AptLoad.h"
#endif
#include "GameClient/TGAFile.h"
#include "Libraries/Source/Apt/AptSwfAssemble.h"
#include "Libraries/Source/Apt/AptSwfAvm1.h"
#include "Libraries/Source/Apt/AptSwfExport.h"
#include "Libraries/Source/Apt/AptSwfImport.h"
#include "Libraries/Source/Apt/AptSwfRecipe.h"
#include "Libraries/Source/Apt/AptSwfTags.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <set>
#include <sstream>

namespace fs = std::filesystem;
using namespace aptswf;

namespace
{

bool readFile(const fs::path &p, std::vector<std::uint8_t> &out)
{
	std::ifstream in(p, std::ios::binary);
	if (!in)
	{
		return false;
	}
	out.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
	return true;
}

bool writeFile(const fs::path &p, const std::vector<std::uint8_t> &bytes)
{
	std::error_code ec;
	fs::create_directories(p.parent_path(), ec);
	std::ofstream out(p, std::ios::binary);
	out.write((const char *)bytes.data(), (std::streamsize)bytes.size());
	return (bool)out;
}

std::string lower(std::string s)
{
	for (char &c : s)
	{
		c = (char)std::tolower((unsigned char)c);
	}
	return s;
}

std::string normalSlash(std::string s)
{
	std::replace(s.begin(), s.end(), '\\', '/');
	return s;
}

// ---- BIG archives (the layout Win32BIGFileSystem.cpp documents), read with their stored names ----------------------------------
struct BigEntry
{
	std::string name;
	std::uint32_t offset = 0, size = 0;
};

struct BigArchive
{
	fs::path path;
	std::vector<BigEntry> entries;

	bool open(const fs::path &p, std::string *error)
	{
		path = p;
		std::vector<std::uint8_t> head;
		std::ifstream in(p, std::ios::binary);
		if (!in)
		{
			*error = "cannot open " + p.string();
			return false;
		}
		char h[16];
		in.read(h, 16);
		if (!in || (std::memcmp(h, "BIGF", 4) != 0 && std::memcmp(h, "BIG4", 4) != 0))
		{
			*error = p.string() + " is not a BIG archive";
			return false;
		}
		auto be = [](const char *b) {
			return ((std::uint32_t)(std::uint8_t)b[0] << 24) | ((std::uint32_t)(std::uint8_t)b[1] << 16) | ((std::uint32_t)(std::uint8_t)b[2] << 8) |
				(std::uint32_t)(std::uint8_t)b[3];
		};
		const std::uint32_t count = be(h + 8);
		for (std::uint32_t i = 0; i < count; ++i)
		{
			char e[8];
			in.read(e, 8);
			BigEntry entry;
			entry.offset = be(e);
			entry.size = be(e + 4);
			std::getline(in, entry.name, '\0');
			if (!in)
			{
				*error = p.string() + ": directory truncated";
				return false;
			}
			entries.push_back(entry);
		}
		return true;
	}

	bool read(const BigEntry &e, std::vector<std::uint8_t> &out) const
	{
		std::ifstream in(path, std::ios::binary);
		in.seekg(e.offset);
		out.resize(e.size);
		in.read((char *)out.data(), e.size);
		return (bool)in;
	}

	// the movies at the archive root (X.apt)
	std::vector<std::string> movies() const
	{
		std::vector<std::string> out;
		for (const BigEntry &e : entries)
		{
			const std::string n = normalSlash(e.name);
			if (n.find('/') == std::string::npos && n.size() > 4 && lower(n.substr(n.size() - 4)) == ".apt")
			{
				out.push_back(n.substr(0, n.size() - 4));
			}
		}
		return out;
	}

	// a movie's APT-side files in archive order: X.apt, X.const, X.dat, X_geometry/*.ru
	AptMovieFiles movieFiles(const std::string &movie) const
	{
		AptMovieFiles m;
		m.name = movie;
		const std::string base = lower(movie);
		for (const BigEntry &e : entries)
		{
			const std::string n = lower(normalSlash(e.name));
			const bool own = n == base + ".apt" || n == base + ".const" || n == base + ".dat" ||
				(n.rfind(base + "_geometry/", 0) == 0 && n.size() > 3 && n.substr(n.size() - 3) == ".ru");
			if (own)
			{
				AptMovieFile f;
				f.path = e.name;
				read(e, f.bytes);
				m.files.push_back(std::move(f));
			}
		}
		return m;
	}
};

bool writeBig(const fs::path &dir, const fs::path &outPath, std::string *error)
{
	std::vector<std::pair<std::string, fs::path>> files;
	for (const auto &e : fs::recursive_directory_iterator(dir))
	{
		if (e.is_regular_file())
		{
			std::string rel = fs::relative(e.path(), dir).generic_string();
			std::replace(rel.begin(), rel.end(), '/', '\\');
			files.push_back({ rel, e.path() });
		}
	}
	std::sort(files.begin(), files.end());
	std::uint32_t headerSize = 16;
	for (const auto &f : files)
	{
		headerSize += 8 + (std::uint32_t)f.first.size() + 1;
	}
	headerSize += 8; // "L253" + 4 zero bytes, as EA's tools write
	std::vector<std::uint8_t> out;
	auto be = [&](std::uint32_t v) {
		out.push_back((std::uint8_t)(v >> 24));
		out.push_back((std::uint8_t)(v >> 16));
		out.push_back((std::uint8_t)(v >> 8));
		out.push_back((std::uint8_t)v);
	};
	std::vector<std::vector<std::uint8_t>> data;
	std::uint32_t total = headerSize;
	for (const auto &f : files)
	{
		data.emplace_back();
		if (!readFile(f.second, data.back()))
		{
			*error = "cannot read " + f.second.string();
			return false;
		}
		total += (std::uint32_t)data.back().size();
	}
	out.insert(out.end(), { 'B', 'I', 'G', 'F' });
	for (int i = 0; i < 4; ++i)
	{
		out.push_back((std::uint8_t)(total >> (8 * i)));
	}
	be((std::uint32_t)files.size());
	be(headerSize);
	std::uint32_t offset = headerSize;
	for (std::size_t i = 0; i < files.size(); ++i)
	{
		be(offset);
		be((std::uint32_t)data[i].size());
		out.insert(out.end(), files[i].first.begin(), files[i].first.end());
		out.push_back(0);
		offset += (std::uint32_t)data[i].size();
	}
	out.insert(out.end(), { 'L', '2', '5', '3', 0, 0, 0, 0 });
	for (const auto &d : data)
	{
		out.insert(out.end(), d.begin(), d.end());
	}
	if (!writeFile(outPath, out))
	{
		*error = "cannot write " + outPath.string();
		return false;
	}
	return true;
}

// ---- archives alone: movies and their textures from the BIGs given (later archives over earlier ones, file by file) ------------
struct ArchiveSet
{
	std::vector<std::unique_ptr<BigArchive>> bigs;

	bool open(const std::vector<std::string> &paths, std::string *error)
	{
		for (const std::string &p : paths)
		{
			auto big = std::make_unique<BigArchive>();
			if (!big->open(p, error))
			{
				return false;
			}
			bigs.push_back(std::move(big));
		}
		return true;
	}

	// every movie of the archives, in first-seen order
	std::vector<std::string> movies() const
	{
		std::vector<std::string> out;
		std::set<std::string> seen;
		for (const auto &b : bigs)
		{
			for (const std::string &m : b->movies())
			{
				if (seen.insert(lower(m)).second)
				{
					out.push_back(m);
				}
			}
		}
		return out;
	}

	std::string archiveOf(const std::string &movie) const
	{
		std::string out;
		for (const auto &b : bigs)
		{
			for (const std::string &m : b->movies())
			{
				out = lower(m) == lower(movie) ? b->path.filename().string() : out;
			}
		}
		return out;
	}

	AptMovieFiles movieFiles(const std::string &movie) const
	{
		AptMovieFiles files;
		files.name = movie;
		for (const auto &b : bigs)
		{
			for (AptMovieFile &f : b->movieFiles(movie).files)
			{
				bool replaced = false;
				for (AptMovieFile &have : files.files)
				{
					if (lower(normalSlash(have.path)) == lower(normalSlash(f.path)))
					{
						have = f;
						replaced = true;
					}
				}
				if (!replaced)
				{
					files.files.push_back(std::move(f));
				}
			}
		}
		return files;
	}

	bool readFile(const std::string &path, std::vector<std::uint8_t> &out) const
	{
		const std::string want = lower(normalSlash(path));
		for (auto b = bigs.rbegin(); b != bigs.rend(); ++b)
		{
			for (const BigEntry &e : (*b)->entries)
			{
				if (lower(normalSlash(e.name)) == want)
				{
					return (*b)->read(e, out);
				}
			}
		}
		return false;
	}

	// art/Textures/<name>, a TGA (bottom-up rows flipped so row 0 is the top, as AptCanvas.cpp's texture store does)
	AptTextureLookup lookup() const
	{
		return [this](const std::string &name, AptTexture &out, std::string *error) {
			std::vector<std::uint8_t> bytes;
			if (!readFile("art/Textures/" + name, bytes))
			{
				if (error)
				{
					*error = "art/Textures/" + name + " is not in the archives given";
				}
				return false;
			}
			TGAImage image;
			std::string e;
			if (!TGAFile::decode(bytes.data(), bytes.size(), image, &e, 4096, true))
			{
				if (error)
				{
					*error = name + ": " + e;
				}
				return false;
			}
			if (!image.topDownFlag)
			{
				const std::size_t row = (std::size_t)image.width * 4;
				for (int y = 0; y < image.height / 2; ++y)
				{
					std::swap_ranges(image.rgba.begin() + (std::ptrdiff_t)((std::size_t)y * row), image.rgba.begin() + (std::ptrdiff_t)((std::size_t)(y + 1) * row),
						image.rgba.begin() + (std::ptrdiff_t)((std::size_t)(image.height - 1 - y) * row));
				}
			}
			out.width = image.width;
			out.height = image.height;
			out.rgba = std::move(image.rgba);
			return true;
		};
	}
};

#ifndef OPENBFME_APTSWF_STANDALONE
// ---- the game mount -------------------------------------------------------------------------------------------------------------
struct GameMount
{
	std::unique_ptr<Win32BIGFileSystem> fs;
	std::unique_ptr<AptArchiveFileSource> source;
	std::unique_ptr<AptTextureStore> textures;

	bool mount(const std::string &game, const fs::path &cacheDir, std::string *error)
	{
		const char *rotwk = std::getenv("ROTWK_INSTALL");
		const char *bfme2 = std::getenv("BFME2_INSTALL");
		std::vector<std::pair<std::string, std::string>> wanted;
		if (game == "rotwk")
		{
			if (!rotwk || !bfme2)
			{
				*error = "--game rotwk needs ROTWK_INSTALL and BFME2_INSTALL";
				return false;
			}
			wanted = { { "rotwk", rotwk }, { "bfme2", bfme2 } };
		}
		else if (game == "bfme2")
		{
			if (!bfme2)
			{
				*error = "--game bfme2 needs BFME2_INSTALL";
				return false;
			}
			wanted = { { "bfme2", bfme2 } };
		}
		else
		{
			*error = "unknown --game " + game + " (rotwk or bfme2)";
			return false;
		}
		std::vector<RetailInstall> installs;
		for (const auto &w : wanted)
		{
			RetailInstall inst;
			inst.label = w.first;
			inst.root = w.second;
			if (!RetailArchivePolicy::loadBuiltin(w.first == "rotwk" ? "rotwk-201" : "bfme2-106", inst.policy, error))
			{
				return false;
			}
			installs.push_back(inst);
		}
		fs = std::make_unique<Win32BIGFileSystem>();
		RetailMountOptions options;
		std::error_code ec;
		fs::create_directories(cacheDir, ec);
		options.md5CachePath = (cacheDir / ("md5-" + game + ".cache")).string();
		RetailMountReport report = MountRetailArchives(*fs, installs, options);
		if (!report.ok)
		{
			*error = "mount failed:";
			for (const std::string &e : report.errors)
			{
				*error += " " + e;
			}
			return false;
		}
		source = std::make_unique<AptArchiveFileSource>(*fs);
		textures = std::make_unique<AptTextureStore>(*source);
		return true;
	}

	AptTextureLookup lookup()
	{
		return [this](const std::string &name, AptTexture &out, std::string *error) {
			const AptTextureStore::Entry &e = textures->get(name);
			if (!e.ok || e.rgba.empty())
			{
				if (error)
				{
					*error = e.error.empty() ? "no pixels" : e.error;
				}
				return false;
			}
			out.width = e.width;
			out.height = e.height;
			out.rgba = e.rgba;
			textures->releasePixels(name);
			return true;
		};
	}
};
#endif // OPENBFME_APTSWF_STANDALONE (the game mount)

struct Options
{
	std::string command;
	std::vector<std::string> positional;
	std::string game;
	std::vector<std::string> bigs;
	std::set<std::string> movies; // lower case
	fs::path out;
	bool embed = true;
	bool resolveStrings = false; // export only: a preview with the game's strings in place of "$Label" texts (no private tags)
	bool all = false;            // info: every placement, not only the named ones
	bool write = false;          // reassemble: write the movies with every program re-assembled
	fs::path dir;                // apply: a folder with the movie's loose files
	std::string swfIn;           // apply: an exported SWF
	fs::path pack;               // apply: also pack the files as this BIG
};

bool parseArgs(int argc, char **argv, Options &o)
{
	if (argc < 2)
	{
		return false;
	}
	o.command = argv[1];
	for (int i = 2; i < argc; ++i)
	{
		std::string a = argv[i];
		auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : std::string(); };
		if (a == "--game")
		{
			o.game = next();
		}
		else if (a == "--big")
		{
			o.bigs.push_back(next());
		}
		else if (a == "--movie")
		{
			o.movies.insert(lower(next()));
		}
		else if (a == "--out")
		{
			o.out = next();
		}
		else if (a == "--no-embed")
		{
			o.embed = false;
		}
		else if (a == "--resolve-strings")
		{
			o.resolveStrings = true;
		}
		else if (a == "--all")
		{
			o.all = true;
		}
		else if (a == "--write")
		{
			o.write = true;
		}
		else if (a == "--dir")
		{
			o.dir = next();
		}
		else if (a == "--swf")
		{
			o.swfIn = next();
		}
		else if (a == "--pack")
		{
			o.pack = next();
		}
		else
		{
			o.positional.push_back(a);
		}
	}
	return true;
}

int usage()
{
	std::fprintf(stderr,
		"usage:\n"
		"  openbfme_apt_swf export    (--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR [--no-embed] [--resolve-strings]\n"
		"  openbfme_apt_swf roundtrip (--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR\n"
		"  openbfme_apt_swf import    FILE.swf --out DIR\n"
		"  openbfme_apt_swf reassemble (--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR [--write]\n"
		"  openbfme_apt_swf info      FILE.swf [--all]\n"
		"  openbfme_apt_swf apply     RECIPE.txt (--dir FOLDER | --big ARCHIVE... | --game rotwk|bfme2 | --swf FILE.swf) --out DIR [--pack OUT.big]\n"
		"  openbfme_apt_swf set-text  IN.swf OUT.swf CHARACTER_ID TEXT\n"
		"  openbfme_apt_swf move      IN.swf OUT.swf SPRITE_ID FRAME DEPTH DX DY\n"
		"  openbfme_apt_swf pack-big  DIR OUT.big\n");
	return 2;
}

// One movie to convert: its files, where they came from.
struct Job
{
	std::string archive;
	AptMovieFiles files;
};

#ifndef OPENBFME_APTSWF_STANDALONE
bool collectJobs(Options &o, GameMount &mount, std::vector<Job> &jobs, std::string *error)
{
	if (!o.bigs.empty())
	{
		for (const std::string &b : o.bigs)
		{
			BigArchive big;
			if (!big.open(b, error))
			{
				return false;
			}
			// the mod archive goes over the game mount, so its textures are found first
			std::string e;
			std::unique_ptr<ArchiveFile> af = mount.fs->openArchiveFile(b, &e);
			if (!af)
			{
				*error = e;
				return false;
			}
			mount.fs->mountArchive(std::move(af), b, true);
			for (const std::string &m : big.movies())
			{
				if (o.movies.empty() || o.movies.count(lower(m)))
				{
					AptMovieFiles files = big.movieFiles(m);
					// a mod may ship only some of a movie's files (Edain's LoadScreen.apt without its .const): the rest come from
					// the mount, as the game reads them
					for (const char *ext : { ".apt", ".const" })
					{
						if (!files.find(m + ext))
						{
							AptMovieFile f;
							f.path = m + ext;
							if (!mount.fs->readFile(f.path, f.bytes, &e))
							{
								*error = m + ": " + e;
								return false;
							}
							files.files.push_back(std::move(f));
						}
					}
					jobs.push_back({ fs::path(b).filename().string(), std::move(files) });
				}
			}
		}
		return true;
	}
	std::map<std::string, std::unique_ptr<BigArchive>> opened;
	for (const std::string &m : mount.source->listMovies())
	{
		if (!o.movies.empty() && !o.movies.count(lower(m)))
		{
			continue;
		}
		const std::string archive = mount.fs->getArchiveFilenameForFile(m + ".apt");
		auto it = opened.find(archive);
		if (it == opened.end())
		{
			auto big = std::make_unique<BigArchive>();
			if (!big->open(archive, error))
			{
				return false;
			}
			it = opened.emplace(archive, std::move(big)).first;
		}
		// the archive's own spelling of the movie name
		std::string name = m;
		for (const std::string &own : it->second->movies())
		{
			if (lower(own) == lower(m))
			{
				name = own;
			}
		}
		jobs.push_back({ fs::path(archive).filename().string(), it->second->movieFiles(name) });
	}
	return true;
}

#endif // OPENBFME_APTSWF_STANDALONE

std::string extOf(const std::string &path)
{
	const std::size_t dot = path.rfind('.');
	return dot == std::string::npos ? std::string() : lower(path.substr(dot));
}

int runConvert(Options &o, bool roundtrip)
{
	if (o.out.empty() || (roundtrip && o.resolveStrings))
	{
		return usage();
	}
	std::string error;
	std::vector<Job> jobs;
	ExportOptions options;
	options.embedOriginal = o.embed && !o.resolveStrings;
	ArchiveSet archives;
#ifdef OPENBFME_APTSWF_STANDALONE
	const bool archiveOnly = true;
	if (!o.game.empty() || o.bigs.empty() || o.resolveStrings)
	{
		std::fprintf(stderr, "this build reads the archives given with --big (no --game, no --resolve-strings)\n");
		return 2;
	}
	const std::string game;
#else
	const bool archiveOnly = o.game.empty() && !o.bigs.empty() && !std::getenv("ROTWK_INSTALL") && !std::getenv("BFME2_INSTALL");
	GameMount mount;
	const std::string game = o.game.empty() ? "rotwk" : o.game;
	GameTextTable strings;
	if (!archiveOnly)
	{
		if (!mount.mount(game, o.out / ".cache", &error) || !collectJobs(o, mount, jobs, &error))
		{
			std::fprintf(stderr, "%s\n", error.c_str());
			return 1;
		}
		options.textures = mount.lookup();
		if (o.resolveStrings && !strings.loadRetail(*mount.fs, &error))
		{
			std::fprintf(stderr, "--resolve-strings: %s\n", error.c_str());
			return 1;
		}
	}
	else if (o.resolveStrings)
	{
		std::fprintf(stderr, "--resolve-strings needs the game (--game, ROTWK_INSTALL / BFME2_INSTALL)\n");
		return 2;
	}
#endif
	if (archiveOnly)
	{
		if (!archives.open(o.bigs, &error))
		{
			std::fprintf(stderr, "%s\n", error.c_str());
			return 1;
		}
		for (const std::string &m : archives.movies())
		{
			if (o.movies.empty() || o.movies.count(lower(m)))
			{
				jobs.push_back({ archives.archiveOf(m), archives.movieFiles(m) });
			}
		}
		options.textures = archives.lookup();
	}
	std::map<std::string, std::size_t> noteMovies;
	std::map<std::string, std::pair<std::size_t, std::size_t>> perExt; // ext -> (identical, total)
	std::size_t moviesOk = 0, moviesFailed = 0, moviesIdentical = 0;
	ExportStats total;
	std::ostringstream table;
	table << "| movie | archive | SWF bytes | shapes | bitmaps | sprites | buttons | texts | programs | EA ops | files | identical |\n";
	table << "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n";
	std::ostringstream failures;
	for (const Job &job : jobs)
	{
		std::vector<std::uint8_t> swf;
		ExportResult r;
		if (!exportSwf(job.files, options, swf, r, &error))
		{
			++moviesFailed;
			failures << "- " << job.files.name << " (" << job.archive << "): export failed: " << error << "\n";
			std::fprintf(stderr, "FAIL %s: %s\n", job.files.name.c_str(), error.c_str());
			continue;
		}
#ifndef OPENBFME_APTSWF_STANDALONE
		if (o.resolveStrings)
		{
			// a preview: "$Label" texts replaced by the game's strings (GameText.h ResolveAptText), no private tags (it is not
			// meant to go back to APT: the importer would take the strings for edits)
			for (SwfTag *t : flattenTagsMutable(r.tags))
			{
				SwfEditText et;
				if (t->code == SWF_TAG_DEFINEEDITTEXT && decodeEditText(t->body, et))
				{
					const AptTextResolution res = ResolveAptText(et.initialText, strings);
					if (res.wasLabel && res.found)
					{
						et.initialText = res.text;
						t->body = encodeEditText(et);
					}
				}
			}
			swf = swfWriteFile(r.header, r.tags);
		}
#endif
		writeFile(o.out / (job.files.name + ".swf"), swf);
		for (const std::string &n : r.notes)
		{
			++noteMovies[n];
		}
		total.shapes += r.stats.shapes;
		total.bitmaps += r.stats.bitmaps;
		total.sprites += r.stats.sprites;
		total.buttons += r.stats.buttons;
		total.texts += r.stats.texts;
		total.fonts += r.stats.fonts;
		total.programs += r.stats.programs;
		total.instructions += r.stats.instructions;
		total.eaOpcodes += r.stats.eaOpcodes;
		total.triangles += r.stats.triangles;
		total.placeholders += r.stats.placeholders;
		std::size_t identical = 0;
		if (roundtrip)
		{
			ImportResult back;
			if (!importSwf(swf, back, &error))
			{
				++moviesFailed;
				failures << "- " << job.files.name << ": import failed: " << error << "\n";
				std::fprintf(stderr, "FAIL import %s: %s\n", job.files.name.c_str(), error.c_str());
				continue;
			}
			for (const AptMovieFile &orig : job.files.files)
			{
				const AptMovieFile *again = nullptr;
				for (const AptMovieFile &f : back.files)
				{
					if (f.path == orig.path)
					{
						again = &f;
					}
				}
				const bool same = again && again->bytes == orig.bytes;
				identical += same ? 1 : 0;
				auto &pe = perExt[extOf(orig.path)];
				pe.first += same ? 1 : 0;
				pe.second += 1;
				if (!same)
				{
					failures << "- " << job.files.name << ": " << orig.path << " differs after the round trip\n";
				}
			}
			if (identical == job.files.files.size() && back.files.size() == job.files.files.size())
			{
				++moviesIdentical;
			}
		}
		++moviesOk;
		table << "| " << job.files.name << " | " << job.archive << " | " << swf.size() << " | " << r.stats.shapes << " | " << r.stats.bitmaps << " | "
			  << r.stats.sprites << " | " << r.stats.buttons << " | " << r.stats.texts << " | " << r.stats.programs << " | " << r.stats.eaOpcodes << " | "
			  << job.files.files.size() << " | " << (roundtrip ? std::to_string(identical) : std::string("-")) << " |\n";
		std::printf("%-32s %9zu bytes  %s\n", job.files.name.c_str(), swf.size(),
			roundtrip ? (identical == job.files.files.size() ? "round trip identical" : "ROUND TRIP DIFFERS") : "exported");
	}
	std::ostringstream report;
	report << "# APT -> SWF " << (roundtrip ? "round trip" : "export") << ": " << (o.bigs.empty() ? game : std::string(archiveOnly ? "archives" : "mod archives")) << "\n\n";
	report << "Movies: " << jobs.size() << ", converted " << moviesOk << ", failed " << moviesFailed << "\n";
	if (roundtrip)
	{
		report << "Movies byte-identical after SWF -> APT: " << moviesIdentical << " / " << jobs.size() << "\n\n";
		report << "| file type | byte-identical | total |\n|---|---:|---:|\n";
		std::size_t a = 0, b = 0;
		for (const auto &kv : perExt)
		{
			report << "| " << kv.first << " | " << kv.second.first << " | " << kv.second.second << " |\n";
			a += kv.second.first;
			b += kv.second.second;
		}
		report << "| all | " << a << " | " << b << " |\n";
	}
	report << "\nTotals: " << total.shapes << " shapes (" << total.triangles << " triangles), " << total.bitmaps << " bitmaps, " << total.sprites
		   << " sprites, " << total.buttons << " buttons, " << total.texts << " text fields, " << total.fonts << " fonts, " << total.placeholders
		   << " placeholders, " << total.programs << " action programs (" << total.instructions << " APT instructions, " << total.eaOpcodes
		   << " EA opcodes expanded)\n\n";
	report << "## Notes (what the SWF cannot express exactly; number of movies)\n\n";
	for (const auto &kv : noteMovies)
	{
		report << "- (" << kv.second << ") " << kv.first << "\n";
	}
	if (!failures.str().empty())
	{
		report << "\n## Failures\n\n" << failures.str();
	}
	report << "\n## Movies\n\n" << table.str();
	const std::string text = report.str();
	writeFile(o.out / "report.md", std::vector<std::uint8_t>(text.begin(), text.end()));
	std::printf("\n%s", text.substr(0, text.find("## Notes")).c_str());
	return moviesFailed == 0 ? 0 : 1;
}

int runImport(Options &o)
{
	if (o.positional.size() != 1 || o.out.empty())
	{
		return usage();
	}
	std::vector<std::uint8_t> swf;
	if (!readFile(o.positional[0], swf))
	{
		std::fprintf(stderr, "cannot read %s\n", o.positional[0].c_str());
		return 1;
	}
	ImportResult r;
	std::string error;
	if (!importSwf(swf, r, &error))
	{
		std::fprintf(stderr, "%s\n", error.c_str());
		return 1;
	}
	for (const AptMovieFile &f : r.files)
	{
		writeFile(o.out / normalSlash(f.path), f.bytes);
	}
	std::printf("%s: %zu files written, %zu of %zu standard tags edited\n", r.movieName.c_str(), r.files.size(), r.editedTags, r.standardTags);
	for (const std::string &e : r.edits)
	{
		std::printf("  edit: %s\n", e.c_str());
	}
	for (const std::string &e : r.ignored)
	{
		std::printf("  ignored: %s\n", e.c_str());
	}
	return 0;
}

int runInfo(Options &o)
{
	if (o.positional.size() != 1)
	{
		return usage();
	}
	std::vector<std::uint8_t> bytes;
	SwfFile swf;
	std::string error;
	if (!readFile(o.positional[0], bytes) || !swfReadFile(bytes, swf, &error))
	{
		std::fprintf(stderr, "cannot read %s %s\n", o.positional[0].c_str(), error.c_str());
		return 1;
	}
	std::map<std::uint16_t, std::size_t> counts;
	for (const SwfTag *t : flattenTags(swf.tags))
	{
		++counts[t->code];
	}
	std::printf("SWF %u, %d x %d px, %.2f fps, %u frames\n", swf.header.version, swf.header.frameWidthTwips / 20, swf.header.frameHeightTwips / 20,
		swf.header.frameRate8_8 / 256.0, swf.header.frameCount);
	for (const auto &kv : counts)
	{
		std::printf("  tag %4u: %zu\n", kv.first, kv.second);
	}
	// the editable things: text fields and named placements (sprite 0 = the root timeline)
	for (const SwfTag *t : flattenTags(swf.tags))
	{
		SwfEditText et;
		if (t->code == SWF_TAG_DEFINEEDITTEXT && decodeEditText(t->body, et))
		{
			std::printf("  text %u: '%s' (variable '%s')\n", et.id, et.initialText.c_str(), et.variableName.c_str());
		}
	}
	const bool all = o.all;
	auto placements = [all](const std::vector<SwfTag> &timeline, unsigned sprite) {
		int frame = 0;
		for (const SwfTag &t : timeline)
		{
			SwfPlaceObject2 po;
			if (t.code == SWF_TAG_SHOWFRAME)
			{
				++frame;
			}
			else if (t.code == SWF_TAG_PLACEOBJECT2 && decodePlaceObject2(t.body, po) && ((po.flags & 0x20) || (all && (po.flags & 0x02))))
			{
				// frames count from 1 here, as in recipes and JPEXS
				std::printf("  place sprite %u frame %d depth %u character %u '%s' at (%g, %g)", sprite, frame + 1, po.depth, po.characterId,
					po.name.c_str(), po.matrix.translateX / 20.0, po.matrix.translateY / 20.0);
				if (po.matrix.hasScale)
				{
					std::printf(" scale %g,%g", po.matrix.scaleX / 65536.0, po.matrix.scaleY / 65536.0);
				}
				std::printf("\n");
			}
		}
	};
	placements(swf.tags, 0);
	for (const SwfTag &t : swf.tags)
	{
		if (t.code == SWF_TAG_DEFINESPRITE && t.body.size() >= 2)
		{
			placements(t.children, (unsigned)(t.body[0] | (t.body[1] << 8)));
		}
	}
	return 0;
}

// The editor the round trip is tested with: it changes standard tags only, re-encoded with the same tag encoders an external
// tool would use, and leaves the private tags alone.
int runEdit(Options &o, bool text)
{
	if ((text && o.positional.size() != 4) || (!text && o.positional.size() != 7))
	{
		return usage();
	}
	std::vector<std::uint8_t> bytes;
	SwfFile swf;
	std::string error;
	if (!readFile(o.positional[0], bytes) || !swfReadFile(bytes, swf, &error))
	{
		std::fprintf(stderr, "cannot read %s %s\n", o.positional[0].c_str(), error.c_str());
		return 1;
	}
	bool done = false;
	if (text)
	{
		const std::uint16_t id = (std::uint16_t)std::stoul(o.positional[2]);
		for (SwfTag *t : flattenTagsMutable(swf.tags))
		{
			SwfEditText et;
			if (t->code == SWF_TAG_DEFINEEDITTEXT && decodeEditText(t->body, et) && et.id == id)
			{
				std::printf("text field %u: '%s' -> '%s'\n", id, et.initialText.c_str(), o.positional[3].c_str());
				et.initialText = o.positional[3];
				t->body = encodeEditText(et);
				done = true;
			}
		}
	}
	else
	{
		const std::uint16_t sprite = (std::uint16_t)std::stoul(o.positional[2]);
		const int frame = std::stoi(o.positional[3]);
		const std::uint16_t depth = (std::uint16_t)std::stoul(o.positional[4]);
		const double dx = std::stod(o.positional[5]), dy = std::stod(o.positional[6]);
		std::vector<SwfTag> *timeline = sprite == 0 ? &swf.tags : nullptr;
		for (SwfTag &t : swf.tags)
		{
			if (t.code == SWF_TAG_DEFINESPRITE && t.body.size() >= 2 && (t.body[0] | (t.body[1] << 8)) == sprite)
			{
				timeline = &t.children;
			}
		}
		int f = 0;
		for (SwfTag &t : timeline ? *timeline : swf.tags)
		{
			if (!timeline)
			{
				break;
			}
			if (t.code == SWF_TAG_SHOWFRAME)
			{
				++f;
				continue;
			}
			SwfPlaceObject2 po;
			if (f == frame && t.code == SWF_TAG_PLACEOBJECT2 && decodePlaceObject2(t.body, po) && po.depth == depth && (po.flags & 0x04))
			{
				std::printf("place object depth %u '%s': (%g, %g) -> (%g, %g)\n", depth, po.name.c_str(), po.matrix.translateX / 20.0,
					po.matrix.translateY / 20.0, po.matrix.translateX / 20.0 + dx, po.matrix.translateY / 20.0 + dy);
				po.matrix.translateX += (std::int32_t)std::lround(dx * 20);
				po.matrix.translateY += (std::int32_t)std::lround(dy * 20);
				t.body = encodePlaceObject2(po);
				done = true;
			}
		}
	}
	if (!done)
	{
		std::fprintf(stderr, "nothing matched\n");
		return 1;
	}
	if (!writeFile(o.positional[1], swfWriteFile(swf.header, swf.tags)))
	{
		std::fprintf(stderr, "cannot write %s\n", o.positional[1].c_str());
		return 1;
	}
	return 0;
}

fs::path g_reassembleOut; // reassemble --write: where the files go

// ---- reassemble: every action program of the movies, assembled back into APT and checked (AptSwfAssemble.h) ------------------
// The programs are the exporter's AVM1: frame and init actions, clip actions, button actions.  Each is appended to a copy of its
// movie's .apt, decoded with the game's decoder, converted to AVM1 again and compared action by action with the original AVM1.
void collectPrograms(const std::vector<SwfTag> &tags, std::vector<std::vector<std::uint8_t>> &out)
{
	for (const SwfTag *t : flattenTags(tags))
	{
		if (t->code == SWF_TAG_DOACTION)
		{
			out.push_back(t->body);
		}
		else if (t->code == SWF_TAG_DOINITACTION && t->body.size() > 2)
		{
			out.emplace_back(t->body.begin() + 2, t->body.end());
		}
		else if (t->code == SWF_TAG_PLACEOBJECT2)
		{
			SwfPlaceObject2 p;
			if (!decodePlaceObject2(t->body, p) || !(p.flags & 0x80) || p.clipActions.size() < 6)
			{
				continue;
			}
			// CLIPACTIONS: reserved u16, all event flags u32, then (event flags u32, record size u32, [key code u8], actions) until flags 0
			std::size_t at = 6;
			while (at + 8 <= p.clipActions.size())
			{
				const std::uint32_t flags = (std::uint32_t)p.clipActions[at] | ((std::uint32_t)p.clipActions[at + 1] << 8) |
					((std::uint32_t)p.clipActions[at + 2] << 16) | ((std::uint32_t)p.clipActions[at + 3] << 24);
				if (flags == 0)
				{
					break;
				}
				std::size_t size = (std::size_t)p.clipActions[at + 4] | ((std::size_t)p.clipActions[at + 5] << 8) |
					((std::size_t)p.clipActions[at + 6] << 16) | ((std::size_t)p.clipActions[at + 7] << 24);
				std::size_t code = at + 8;
				if (flags & APT_CLIP_KEYPRESS)
				{
					++code;
					--size;
				}
				if (code + size > p.clipActions.size())
				{
					break;
				}
				out.emplace_back(p.clipActions.begin() + (std::ptrdiff_t)code, p.clipActions.begin() + (std::ptrdiff_t)(code + size));
				at = code + size;
			}
		}
		else if (t->code == SWF_TAG_DEFINEBUTTON2)
		{
			SwfButton2 b;
			if (!decodeButton2(t->body, b))
			{
				continue;
			}
			// BUTTONCONDACTION: size u16 (0 for the last), conditions u16, actions
			std::size_t at = 0;
			while (at + 4 <= b.condActions.size())
			{
				const std::size_t size = (std::size_t)b.condActions[at] | ((std::size_t)b.condActions[at + 1] << 8);
				const std::size_t end = size ? at + size : b.condActions.size();
				if (end > b.condActions.size() || end < at + 4)
				{
					break;
				}
				out.emplace_back(b.condActions.begin() + (std::ptrdiff_t)(at + 4), b.condActions.begin() + (std::ptrdiff_t)end);
				if (!size)
				{
					break;
				}
				at = end;
			}
		}
	}
}

// --write: every program reference of the movie (frame and init actions, clip events, button actions) pointed at a re-assembled
// copy of its program, so the game runs only assembled code; the files go to <out>/files.
bool rewritePrograms(const AptMovieFiles &files, const AptFile &movie, std::size_t &repointed, std::ostringstream &failures)
{
	const AptMovieFile *apt = files.find(files.name + ".apt");
	const AptMovieFile *cst = files.find(files.name + ".const");
	std::vector<std::uint8_t> bytes = apt->bytes;
	AptConstWriter consts;
	std::string error;
	if (!consts.load(cst->bytes, &error))
	{
		failures << "- " << files.name << ": " << error << "\n";
		return false;
	}
	std::map<std::uint32_t, std::uint32_t> done; // old program -> new program (a program shared by several references once)
	auto u32 = [&](std::uint32_t at) {
		return (std::uint32_t)bytes[at] | ((std::uint32_t)bytes[at + 1] << 8) | ((std::uint32_t)bytes[at + 2] << 16) | ((std::uint32_t)bytes[at + 3] << 24);
	};
	auto put = [&](std::uint32_t at, std::uint32_t v) {
		for (int i = 0; i < 4; ++i)
		{
			bytes[at + i] = (std::uint8_t)(v >> (8 * i));
		}
	};
	auto repoint = [&](std::uint32_t pointerAt) -> bool {
		const std::uint32_t old = u32(pointerAt);
		auto it = done.find(old);
		if (it == done.end())
		{
			Avm1Result avm1;
			std::uint32_t offset = 0;
			AssembleStats stats;
			if (!programAvm1(movie, old, avm1, &error))
			{
				return true; // a program the decoder refuses stays as it was
			}
			if (!assembleChecked(avm1.bytes, files.name, movie.version, bytes, consts, offset, stats, &error))
			{
				failures << "- " << files.name << " program at " << old << ": " << error << "\n";
				return false;
			}
			it = done.emplace(old, offset).first;
		}
		put(pointerAt, it->second);
		++repointed;
		return true;
	};
	auto frames = [&](const std::vector<AptFrame> &list) -> bool {
		for (const AptFrame &f : list)
		{
			for (const AptFrameItem &it : f.items)
			{
				if ((it.type == APT_ITEM_ACTION && !repoint(it.offset + 4)) || (it.type == APT_ITEM_INITACTION && !repoint(it.offset + 8)))
				{
					return false;
				}
				if (it.type == APT_ITEM_PLACEOBJECT && it.place && !it.place->clipEvents.empty())
				{
					const std::uint32_t list = u32(it.offset + 60);
					const std::uint32_t table = u32(list + 4);
					for (std::size_t e = 0; e < it.place->clipEvents.size(); ++e)
					{
						if (!repoint(table + (std::uint32_t)e * 12 + 8))
						{
							return false;
						}
					}
				}
			}
		}
		return true;
	};
	if (!frames(movie.frames))
	{
		return false;
	}
	for (const AptCharacter &c : movie.characters)
	{
		if (c.type == APT_CHAR_SPRITE && !frames(c.frames))
		{
			return false;
		}
		if (c.type == APT_CHAR_BUTTON && c.button)
		{
			const std::uint32_t table = u32(c.offset + 56);
			for (std::size_t a = 0; a < c.button->actions.size(); ++a)
			{
				if (!repoint(table + (std::uint32_t)a * 8 + 4))
				{
					return false;
				}
			}
		}
	}
	// the result parses, and goes out with the movie's other files
	AptConstFile parsedConsts;
	AptFile check;
	if (!AptConstFile::parse(consts.bytes(), parsedConsts, &error) ||
		!AptFile::parse(files.name, std::make_shared<const std::vector<std::uint8_t>>(bytes), parsedConsts, check, &error))
	{
		failures << "- " << files.name << ": the rewritten movie does not parse: " << error << "\n";
		return false;
	}
	for (const AptMovieFile &f : files.files)
	{
		const bool isApt = &f == apt, isConst = &f == cst;
		writeFile(g_reassembleOut / "files" / normalSlash(f.path), isApt ? bytes : isConst ? consts.bytes() : f.bytes);
	}
	return true;
}

int runReassemble(Options &o)
{
	g_reassembleOut = o.out;
	if (o.out.empty())
	{
		return usage();
	}
	std::string error;
	std::vector<Job> jobs;
	ArchiveSet archives;
#ifndef OPENBFME_APTSWF_STANDALONE
	GameMount mount;
	if (!o.game.empty() || o.bigs.empty())
	{
		if (!mount.mount(o.game.empty() ? "rotwk" : o.game, o.out / ".cache", &error) || !collectJobs(o, mount, jobs, &error))
		{
			std::fprintf(stderr, "%s\n", error.c_str());
			return 1;
		}
	}
	else
#endif
	{
		if (!archives.open(o.bigs, &error))
		{
			std::fprintf(stderr, "%s\n", error.c_str());
			return 1;
		}
		for (const std::string &m : archives.movies())
		{
			if (o.movies.empty() || o.movies.count(lower(m)))
			{
				jobs.push_back({ archives.archiveOf(m), archives.movieFiles(m) });
			}
		}
	}
	std::size_t programs = 0, ok = 0, moviesOk = 0, instructions = 0, rounded = 0, written = 0;
	std::ostringstream failures;
	for (const Job &job : jobs)
	{
		ExportResult r;
		if (!exportStandardTags(job.files, ExportOptions(), r, &error))
		{
			failures << "- " << job.files.name << ": export failed: " << error << "\n";
			continue;
		}
		const AptMovieFile *apt = job.files.find(job.files.name + ".apt");
		const AptMovieFile *cst = job.files.find(job.files.name + ".const");
		std::vector<std::uint8_t> bytes = apt->bytes;
		AptConstWriter consts;
		if (!consts.load(cst->bytes, &error))
		{
			failures << "- " << job.files.name << ": " << error << "\n";
			continue;
		}
		std::vector<std::vector<std::uint8_t>> list;
		collectPrograms(r.tags, list);
		std::size_t movieOk = 0;
		for (std::size_t i = 0; i < list.size(); ++i)
		{
			std::uint32_t offset = 0;
			AssembleStats stats;
			++programs;
			if (!assembleChecked(list[i], job.files.name, r.movie->version, bytes, consts, offset, stats, &error))
			{
				failures << "- " << job.files.name << " program " << i << ": " << error << "\n";
				continue;
			}
			++ok;
			++movieOk;
			instructions += stats.instructions;
			rounded += stats.roundedDoubles;
		}
		moviesOk += movieOk == list.size() ? 1 : 0;
		std::printf("%-32s %5zu / %5zu programs re-assembled\n", job.files.name.c_str(), movieOk, list.size());
		if (o.write)
		{
			std::size_t repointed = 0;
			if (!rewritePrograms(job.files, *r.movie, repointed, failures))
			{
				continue;
			}
			written += repointed;
		}
	}
	std::ostringstream report;
	report << "# SWF actions -> APT: every program re-assembled and checked\n\n";
	report << "Movies: " << jobs.size() << ", every program re-assembled in " << moviesOk << "\n";
	report << "Programs: " << ok << " / " << programs << " (" << instructions << " APT instructions written, " << rounded
		   << " numbers rounded to float32)\n";
	if (o.write)
	{
		report << "Written: " << written << " program references re-pointed to re-assembled copies, in " << (o.out / "files").string() << "\n";
	}
	report << "\n";
	if (!failures.str().empty())
	{
		report << "## Failures\n\n" << failures.str();
	}
	const std::string text = report.str();
	writeFile(o.out / "reassemble.md", std::vector<std::uint8_t>(text.begin(), text.end()));
	std::printf("\n%s", text.c_str());
	return ok == programs ? 0 : 1;
}

// ---- apply: a recipe on the user's own copy of a movie ----------------------------------------------------------------------------
// The movie comes from --swf (an exported SWF), --dir (loose files: NAME.apt, NAME.const, NAME.dat, NAME_geometry/*.ru), --big (archives,
// later ones over earlier ones, file by file) or --game (the retail mount).  The recipe edits the exported SWF; the importer writes the
// edits into the .apt (the same path as an edit made in a SWF editor).
std::string recipeMovie(const std::string &text)
{
	std::istringstream in(text);
	std::string line;
	while (std::getline(in, line))
	{
		if (!line.empty() && line.back() == '\r')
		{
			line.pop_back();
		}
		const std::size_t at = line.find_first_not_of(" \t");
		if (at != std::string::npos && line.compare(at, 6, "movie ") == 0)
		{
			std::string name = line.substr(at + 6);
			name.erase(0, name.find_first_not_of(" \t"));
			while (!name.empty() && (name.back() == ' ' || name.back() == '\t'))
			{
				name.pop_back();
			}
			return name;
		}
	}
	return std::string();
}

bool loadMovieFromDir(const fs::path &dir, const std::string &movie, AptMovieFiles &files, std::string *error)
{
	files = AptMovieFiles();
	files.name = movie;
	std::error_code ec;
	for (const auto &e : fs::directory_iterator(dir, ec))
	{
		const std::string n = e.path().filename().string();
		if (!e.is_regular_file() || lower(n.substr(0, movie.size() + 1)) != lower(movie + "."))
		{
			continue;
		}
		const std::string ext = lower(n.substr(movie.size()));
		if (ext == ".apt" || ext == ".const" || ext == ".dat")
		{
			AptMovieFile f;
			f.path = n;
			readFile(e.path(), f.bytes);
			files.files.push_back(std::move(f));
		}
	}
	for (const auto &e : fs::directory_iterator(dir, ec))
	{
		const std::string n = e.path().filename().string();
		if (e.is_directory() && lower(n) == lower(movie + "_geometry"))
		{
			std::vector<fs::path> ru;
			for (const auto &g : fs::directory_iterator(e.path(), ec))
			{
				if (g.is_regular_file() && lower(g.path().extension().string()) == ".ru")
				{
					ru.push_back(g.path());
				}
			}
			std::sort(ru.begin(), ru.end());
			for (const fs::path &p : ru)
			{
				AptMovieFile f;
				f.path = n + "\\" + p.filename().string();
				readFile(p, f.bytes);
				files.files.push_back(std::move(f));
			}
		}
	}
	if (!files.find(movie + ".apt") || !files.find(movie + ".const"))
	{
		*error = dir.string() + " has no " + movie + ".apt and " + movie + ".const";
		return false;
	}
	return true;
}

bool loadMovieFromBigs(const std::vector<std::string> &bigs, const std::string &movie, AptMovieFiles &files, std::string *error)
{
	files = AptMovieFiles();
	files.name = movie;
	for (const std::string &b : bigs)
	{
		BigArchive big;
		if (!big.open(b, error))
		{
			return false;
		}
		for (AptMovieFile &f : big.movieFiles(movie).files)
		{
			bool replaced = false;
			for (AptMovieFile &have : files.files)
			{
				if (lower(normalSlash(have.path)) == lower(normalSlash(f.path)))
				{
					have = f;
					replaced = true;
				}
			}
			if (!replaced)
			{
				files.files.push_back(std::move(f));
			}
		}
	}
	if (!files.find(movie + ".apt") || !files.find(movie + ".const"))
	{
		*error = "the archives given have no " + movie + ".apt and " + movie + ".const (give the archive with the .const too, e.g. the game's apt\\" +
			movie + ".big first)";
		return false;
	}
	return true;
}

int runApply(Options &o)
{
	if (o.positional.size() != 1 || o.out.empty())
	{
		return usage();
	}
	std::vector<std::uint8_t> recipeBytes;
	if (!readFile(o.positional[0], recipeBytes))
	{
		std::fprintf(stderr, "cannot read the recipe %s\n", o.positional[0].c_str());
		return 1;
	}
	const std::string recipe(recipeBytes.begin(), recipeBytes.end());
	const std::string movie = recipeMovie(recipe);
	if (movie.empty())
	{
		std::fprintf(stderr, "%s has no 'movie' line\n", o.positional[0].c_str());
		return 1;
	}
	std::string error;
	std::vector<std::uint8_t> swfBytes;
	if (!o.swfIn.empty())
	{
		if (!readFile(o.swfIn, swfBytes))
		{
			std::fprintf(stderr, "cannot read %s\n", o.swfIn.c_str());
			return 1;
		}
	}
	else
	{
		AptMovieFiles files;
		ExportOptions options;
		ArchiveSet archives;
#ifndef OPENBFME_APTSWF_STANDALONE
		GameMount mount;
#endif
		if (!o.dir.empty())
		{
			if (!loadMovieFromDir(o.dir, movie, files, &error))
			{
				std::fprintf(stderr, "%s\n", error.c_str());
				return 1;
			}
		}
		else if (!o.bigs.empty())
		{
			if (!loadMovieFromBigs(o.bigs, movie, files, &error) || !archives.open(o.bigs, &error))
			{
				std::fprintf(stderr, "%s\n", error.c_str());
				return 1;
			}
			options.textures = archives.lookup();
		}
#ifndef OPENBFME_APTSWF_STANDALONE
		else if (!o.game.empty())
		{
			o.movies = { lower(movie) };
			std::vector<Job> jobs;
			if (!mount.mount(o.game, o.out / ".cache", &error) || !collectJobs(o, mount, jobs, &error))
			{
				std::fprintf(stderr, "%s\n", error.c_str());
				return 1;
			}
			if (jobs.empty())
			{
				std::fprintf(stderr, "the game has no movie %s\n", movie.c_str());
				return 1;
			}
			files = jobs[0].files;
			options.textures = mount.lookup();
		}
#endif
		else
		{
			std::fprintf(stderr, "apply needs the movie: --dir FOLDER, --big ARCHIVE, --game rotwk|bfme2 or --swf FILE.swf\n");
			return 2;
		}
		ExportResult r;
		if (!exportSwf(files, options, swfBytes, r, &error))
		{
			std::fprintf(stderr, "%s: %s\n", movie.c_str(), error.c_str());
			return 1;
		}
	}
	SwfFile swf;
	if (!swfReadFile(swfBytes, swf, &error))
	{
		std::fprintf(stderr, "%s\n", error.c_str());
		return 1;
	}
	RecipeResult rr;
	if (!applyRecipe(recipe, swf, movie, rr, &error))
	{
		std::fprintf(stderr, "%s: %s\n", o.positional[0].c_str(), error.c_str());
		return 1;
	}
	for (const std::string &n : rr.notes)
	{
		std::printf("note: %s\n", n.c_str());
	}
	for (const std::string &l : rr.log)
	{
		std::printf("  %s\n", l.c_str());
	}
	const std::vector<std::uint8_t> edited = swfWriteFile(swf.header, swf.tags);
	ImportResult ir;
	if (!importSwf(edited, ir, &error))
	{
		std::fprintf(stderr, "writing the edits into the APT failed: %s\n", error.c_str());
		return 1;
	}
	const fs::path filesDir = o.out / "files";
	std::error_code ec;
	fs::remove_all(filesDir, ec);
	for (const AptMovieFile &f : ir.files)
	{
		if (!writeFile(filesDir / normalSlash(f.path), f.bytes))
		{
			std::fprintf(stderr, "cannot write %s\n", (filesDir / normalSlash(f.path)).string().c_str());
			return 1;
		}
	}
	writeFile(o.out / (movie + ".swf"), edited);
	std::printf("%s: %zu files written to %s, %zu edits\n", movie.c_str(), ir.files.size(), filesDir.string().c_str(), ir.edits.size());
	for (const std::string &e : ir.edits)
	{
		std::printf("  edit: %s\n", e.c_str());
	}
	for (const std::string &e : ir.ignored)
	{
		std::printf("  ignored: %s\n", e.c_str());
	}
	std::printf("  the edited SWF (for a look in JPEXS): %s\n", (o.out / (movie + ".swf")).string().c_str());
	if (!o.pack.empty())
	{
		if (!writeBig(filesDir, o.pack, &error))
		{
			std::fprintf(stderr, "%s\n", error.c_str());
			return 1;
		}
		std::printf("  packed: %s\n", o.pack.string().c_str());
	}
	return 0;
}

} // namespace

int main(int argc, char **argv)
{
	Options o;
	if (!parseArgs(argc, argv, o))
	{
		return usage();
	}
	if (o.command == "export")
	{
		return runConvert(o, false);
	}
	if (o.command == "roundtrip")
	{
		return runConvert(o, true);
	}
	if (o.command == "import")
	{
		return runImport(o);
	}
	if (o.command == "info")
	{
		return runInfo(o);
	}
	if (o.command == "set-text")
	{
		return runEdit(o, true);
	}
	if (o.command == "move")
	{
		return runEdit(o, false);
	}
	if (o.command == "reassemble")
	{
		return runReassemble(o);
	}
	if (o.command == "apply")
	{
		return runApply(o);
	}
	if (o.command == "pack-big")
	{
		std::string error;
		if (o.positional.size() != 2 || !writeBig(o.positional[0], o.positional[1], &error))
		{
			std::fprintf(stderr, "%s\n", error.c_str());
			return o.positional.size() != 2 ? usage() : 1;
		}
		return 0;
	}
	return usage();
}
