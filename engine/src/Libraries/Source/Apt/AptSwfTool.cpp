// OpenBFME. GPL-3.0.
//
// openbfme_apt_swf: the APT <-> SWF converter's command line (docs/APT-SWF.md).  `openbfme_apt_swf --help` lists the commands,
// `openbfme_apt_swf help COMMAND` explains one.
//
// --game mounts the retail archives the way the game does (RetailArchivePolicy, ROTWK_INSTALL / BFME2_INSTALL) and converts
// every movie of the mount, each from the archive that provides it.  --big converts every movie in the given archives (a mod's
// apt archives), with the game mount (--game, default rotwk when the installs are set) behind them for textures.
// Without --game, --big reads the archives alone: the movies, and their textures (art/Textures/apt_<movie>_<n>.tga, which each
// movie's BIG carries) from the archives given.  
// The game files are read at run time and written only to --out; nothing of them belongs in the repository.

#include "Common/ArchiveFile.h"
#include "Common/RetailArchivePolicy.h"
#include "GameClient/AptCanvas.h"
#include "GameClient/GameText.h"
#include "GameEngineDevice/Win32Device/Common/Win32BIGFileSystem.h"
#include "Libraries/Source/Apt/AptLoad.h"
#include "GameClient/TGAFile.h"
#include "Libraries/Source/Apt/AptSwfAvm1.h"
#include "Libraries/Source/Apt/AptSwfExport.h"
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
	bool help = false;           // --help / -h after the command
};

// ---- the commands and their help -------------------------------------------------------------------------------------------------
struct Command
{
	const char *name;
	const char *synopsis; // the arguments
	const char *summary;  // one line
	const char *details;  // the options and an example
};

#define OPENBFME_APTSWF_SOURCES                                                                                                     \
	"  Where the movies come from:\n"                                                                                                \
	"    --game rotwk|bfme2   the game's archives, mounted as the game mounts them (rotwk needs ROTWK_INSTALL and BFME2_INSTALL,\n"     \
	"                         bfme2 needs BFME2_INSTALL); each movie is read from the archive that provides it\n"                     \
	"    --big ARCHIVE        the movies in this BIG archive (repeatable: later archives win, file by file).  With the game\n"       \
	"                         installs set, the game is mounted behind them for textures and for files the archives lack; without\n" \
	"                         them, the archives are read alone (each movie's BIG carries its textures)\n"                           \
	"    --movie NAME         only this movie (repeatable; any case)\n"

const Command kCommands[] = {
	{ "export", "(--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR [--no-embed] [--resolve-strings]",
		"APT -> SWF: one DIR/<movie>.swf per movie, and DIR/report.md",
		OPENBFME_APTSWF_SOURCES
		"  Options:\n"
		"    --out DIR            where the SWF files and report.md go\n"
		"    --no-embed           leave the private tags out (a smaller SWF that cannot go back to APT)\n"
		"    --resolve-strings    a preview: \"$Label\" texts replaced by the game's strings (needs the game; cannot go back to APT)\n"
		"  Example:\n"
		"    openbfme_apt_swf export --game rotwk --movie Options --out out/options\n" },
	{ "info", "FILE.swf [--all]", "what a SWF holds: its tags, text fields and named placements",
		"  Options:\n"
		"    --all                every placement, not only the named ones\n"
		"  Frames count from 1, as JPEXS and recipes count them; sprite 0 is the root timeline.\n" },
};

const Command *findCommand(const std::string &name)
{
	for (const Command &c : kCommands)
	{
		if (name == c.name)
		{
			return &c;
		}
	}
	return nullptr;
}

void printOverview(std::FILE *out)
{
	std::fprintf(out,
		"openbfme_apt_swf: the game's Apt menu movies as standard SWF files, and back (docs/APT-SWF.md)\n"
		"\n"
		"usage: openbfme_apt_swf COMMAND [ARGUMENTS]\n"
		"       openbfme_apt_swf help [COMMAND]\n"
		"\n"
		"Commands:\n");
	for (const Command &c : kCommands)
	{
		std::fprintf(out, "  %-11s %s\n", c.name, c.summary);
	}
	std::fprintf(out,
		"\n"
		"`openbfme_apt_swf help COMMAND` shows a command's arguments and options.  The game's files are read at run time and\n"
		"written only to the folder given with --out.\n");
}

void printCommand(std::FILE *out, const Command &c)
{
	std::fprintf(out, "usage: openbfme_apt_swf %s %s\n\n  %s\n", c.name, c.synopsis, c.summary);
	if (*c.details)
	{
		std::fprintf(out, "\n%s", c.details);
	}
}

// Wrong arguments: the reason and the command's synopsis (or the overview) on stderr, exit code 2.
int usage(const std::string &command, const std::string &why = std::string())
{
	if (!why.empty())
	{
		std::fprintf(stderr, "openbfme_apt_swf: %s\n", why.c_str());
	}
	const Command *c = findCommand(command);
	if (c)
	{
		std::fprintf(stderr, "usage: openbfme_apt_swf %s %s\n(`openbfme_apt_swf help %s` explains the options)\n", c->name, c->synopsis, c->name);
	}
	else
	{
		printOverview(stderr);
	}
	return 2;
}

bool parseArgs(int argc, char **argv, Options &o, std::string *error)
{
	if (argc < 2)
	{
		*error = "no command";
		return false;
	}
	o.command = argv[1];
	for (int i = 2; i < argc; ++i)
	{
		const std::string a = argv[i];
		bool missing = false;
		auto next = [&]() -> std::string {
			if (i + 1 >= argc)
			{
				missing = true;
				return std::string();
			}
			return argv[++i];
		};
		if (a == "--help" || a == "-h")
		{
			o.help = true;
		}
		else if (a == "--game")
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
		else if (a.size() > 2 && a.compare(0, 2, "--") == 0)
		{
			*error = "unknown option " + a;
			return false;
		}
		else
		{
			o.positional.push_back(a);
		}
		if (missing)
		{
			*error = a + " needs a value";
			return false;
		}
	}
	return true;
}

// One movie to convert: its files, where they came from.
struct Job
{
	std::string archive;
	AptMovieFiles files;
};

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

int runExport(Options &o)
{
	if (o.out.empty())
	{
		return usage(o.command, "--out is required");
	}
	std::string error;
	std::vector<Job> jobs;
	ExportOptions options;
	options.embedOriginal = o.embed && !o.resolveStrings;
	ArchiveSet archives;
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
	std::size_t moviesOk = 0, moviesFailed = 0;
	ExportStats total;
	std::ostringstream table;
	table << "| movie | archive | SWF bytes | shapes | bitmaps | sprites | buttons | texts | programs | EA ops | files |\n";
	table << "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n";
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
		++moviesOk;
		table << "| " << job.files.name << " | " << job.archive << " | " << swf.size() << " | " << r.stats.shapes << " | " << r.stats.bitmaps << " | "
			  << r.stats.sprites << " | " << r.stats.buttons << " | " << r.stats.texts << " | " << r.stats.programs << " | " << r.stats.eaOpcodes << " | "
			  << job.files.files.size() << " |\n";
		std::printf("%-32s %9zu bytes  exported\n", job.files.name.c_str(), swf.size());
	}
	std::ostringstream report;
	report << "# APT -> SWF export: " << (o.bigs.empty() ? game : std::string(archiveOnly ? "archives" : "mod archives")) << "\n\n";
	report << "Movies: " << jobs.size() << ", converted " << moviesOk << ", failed " << moviesFailed << "\n";
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

int runInfo(Options &o)
{
	if (o.positional.size() != 1)
	{
		return usage(o.command);
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

} // namespace

int main(int argc, char **argv)
{
	const std::string first = argc > 1 ? argv[1] : std::string();
	if (first == "--help" || first == "-h" || first == "help")
	{
		const Command *c = argc > 2 ? findCommand(argv[2]) : nullptr;
		if (argc > 2 && !c)
		{
			return usage(std::string(), std::string("unknown command ") + argv[2]);
		}
		c ? printCommand(stdout, *c) : printOverview(stdout);
		return 0;
	}
	Options o;
	std::string error;
	if (!parseArgs(argc, argv, o, &error))
	{
		return usage(o.command, error);
	}
	if (!findCommand(o.command))
	{
		return usage(std::string(), "unknown command " + o.command);
	}
	if (o.help)
	{
		printCommand(stdout, *findCommand(o.command));
		return 0;
	}
	if (o.command == "export")
	{
		return runExport(o);
	}
	return runInfo(o);
}
