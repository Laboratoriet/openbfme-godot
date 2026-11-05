// OpenBFME. GPL-3.0.
//
// openbfme_apt_swf: the APT <-> SWF converter's command line (docs/APT-SWF.md).
//
//   openbfme_apt_swf export    (--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR [--no-embed] [--resolve-strings]
//   openbfme_apt_swf roundtrip (--game rotwk|bfme2 | --big ARCHIVE...) [--movie NAME]... --out DIR
//   openbfme_apt_swf import    FILE.swf --out DIR
//   openbfme_apt_swf info      FILE.swf
//   openbfme_apt_swf set-text  IN.swf OUT.swf CHARACTER_ID TEXT
//   openbfme_apt_swf move      IN.swf OUT.swf SPRITE_ID FRAME DEPTH DX DY   (SPRITE_ID 0 = the root timeline; pixels)
//   openbfme_apt_swf pack-big  DIR OUT.big
//
// --game mounts the retail archives the way the game does (RetailArchivePolicy, ROTWK_INSTALL / BFME2_INSTALL) and converts
// every movie of the mount, each from the archive that provides it.  --big converts every movie in the given archives (a mod's
// apt archives), with the game mount (--game, default rotwk when the installs are set) behind them for textures.
// The game files are read at run time and written only to --out; nothing of them belongs in the repository.

#include "Common/ArchiveFile.h"
#include "Common/RetailArchivePolicy.h"
#include "GameClient/AptCanvas.h"
#include "GameClient/GameText.h"
#include "GameEngineDevice/Win32Device/Common/Win32BIGFileSystem.h"
#include "Libraries/Source/Apt/AptLoad.h"
#include "Libraries/Source/Apt/AptSwfExport.h"
#include "Libraries/Source/Apt/AptSwfImport.h"
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
		"  openbfme_apt_swf info      FILE.swf\n"
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
	GameMount mount;
	std::string game = o.game.empty() ? "rotwk" : o.game;
	if (!mount.mount(game, o.out / ".cache", &error))
	{
		std::fprintf(stderr, "%s\n", error.c_str());
		return 1;
	}
	std::vector<Job> jobs;
	if (!collectJobs(o, mount, jobs, &error))
	{
		std::fprintf(stderr, "%s\n", error.c_str());
		return 1;
	}
	ExportOptions options;
	options.textures = mount.lookup();
	options.embedOriginal = o.embed && !o.resolveStrings;
	GameTextTable strings;
	if (o.resolveStrings && !strings.loadRetail(*mount.fs, &error))
	{
		std::fprintf(stderr, "--resolve-strings: %s\n", error.c_str());
		return 1;
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
	report << "# APT -> SWF " << (roundtrip ? "round trip" : "export") << ": " << (o.bigs.empty() ? game : std::string("mod archives")) << "\n\n";
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
	auto placements = [](const std::vector<SwfTag> &timeline, unsigned sprite) {
		int frame = 0;
		for (const SwfTag &t : timeline)
		{
			SwfPlaceObject2 po;
			if (t.code == SWF_TAG_SHOWFRAME)
			{
				++frame;
			}
			else if (t.code == SWF_TAG_PLACEOBJECT2 && decodePlaceObject2(t.body, po) && (po.flags & 0x20))
			{
				std::printf("  place sprite %u frame %d depth %u character %u '%s' at (%g, %g)\n", sprite, frame, po.depth, po.characterId,
					po.name.c_str(), po.matrix.translateX / 20.0, po.matrix.translateY / 20.0);
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
