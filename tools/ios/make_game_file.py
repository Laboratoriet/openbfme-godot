#!/usr/bin/env python3
"""Lane IOS-9: packs the two game folders into ONE file for the iPhone / iPad: OpenBFME-GameData.obfme.

    python3 tools/ios/make_game_file.py [--rotwk DIR] [--bfme2 DIR] [--out FILE] [--store] [--no-verify] [--dry-run]

The folders come from --rotwk / --bfme2, else ROTWK_INSTALL / BFME2_INSTALL. The file goes to --out (default: OpenBFME-GameData.obfme in the
current folder). The player copies that one file into the app (Finder > the device > Files > drag onto OpenBFME, or the Files app's
On My iPhone > OpenBFME); the first-run screen offers to install it (godot/scripts/release/game_file_import.gd), checks every file's MD5
against this file's manifest, and removes it afterwards. The install folders are only read, never changed.

What goes in (only what the game reads; everything else is listed as skipped with its reason and size):
  * every *.big archive, checked like the game's mount checks it (engine/src/Common/RetailArchivePolicy.h): its path, size and MD5
    against engine/data/retail-archives (the 2.01 / 1.06 policies, their other layouts, the known language archives); Data1.big by its
    entries when it is not the All In One copy; an archive of the exclusion lists (2.02, HD edition) is skipped, as the game never mounts it;
    any other archive stops the packer, as it stops the game's mount;
  * gi.dat (UserDataFolder.cpp: the user data folder's name), data/ (data/movies/*.vp6: VideoPlayer.cpp; data/cursors: GodotMouse.cpp),
    everything under lang/ (localized movies: VideoPlayer.cpp's Lang\\<language>\\Data\\Movies), and two small retail data files the engine
    does not read yet (livingworld.txt, S-1335; <Language>Splash.jpg). Pinned by tools/release/aio_package_files.json /
    aio_language_files.json (the launcher's download): a loose file whose MD5 differs, or that no pin lists, is copied with a warning (the
    game does not check loose files; the warning says so).
What stays out: Windows programs and libraries (*.exe, *.dll, mss/, game.dat, game2.dat, patchget.dat), installer, copy-protection and
patch leftovers (00000000.256, *.lcf, *.dif, *.diff, *.dbgcmd, filelist.txt, launcher.txt, langdata.dat, patch.doc, profile-high.csv)
and asset.dat (docs/PLAN.md rule 11: never read). Any other file is skipped and listed.

The file is a standard ZIP (any unzip tool opens it), zip64, entries RotWK/<path> and BFME2/<path> with the folders' own case, and
manifest.json first: {format "openbfme.game-file", formatVersion 1, games [{folder, game, patch, language, layout, files, bytes}],
files [{path, size, md5, adler32, pin}], bytes, warnings}. Entries are DEFLATE (level 6, the default) or, with --store, STORED. Measured
on the English 2.01 + 1.06 (2026-11-03): 8.50 GB in, 6.46 GB out (the .big archives 5.64 -> 3.63 GB; the VP6 movies, 2.86 GB, do not shrink). Both are checked twice: every file's MD5 before anything is
written (a file that fails stops the packer and nothing is written), again while it is written (a file that changed in between stops it),
and, unless --no-verify, the finished file is read back with Python's zipfile and with the importer's own reading of the ZIP directory.

adler32 (the file's Adler-32): the importer inflates with Godot's StreamPeerGZIP, which takes zlib streams only (core/io/stream_peer_gzip.cpp:
windowBits 15), not ZIP's raw deflate. It puts zlib's two header bytes in front and the file's Adler-32 behind, so zlib ends the stream (and
hands out its last bytes) and checks it too.

Only names, sizes and hashes are written by this tool apart from the ZIP itself: the ZIP holds retail bytes and must never be committed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import struct
import sys
import time
import zipfile
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TABLES = REPO / "engine" / "data" / "retail-archives"
AIO_FILES = REPO / "tools" / "release" / "aio_package_files.json"
AIO_LANGUAGES = REPO / "tools" / "release" / "aio_language_files.json"

FORMAT = "openbfme.game-file"
FORMAT_VERSION = 1
CHUNK = 8 << 20
MARGIN = 256 << 20  # kept free on the output disk beyond the file itself

# (folder in the file, game key, policy id, AIO package, patch)
GAMES = [("RotWK", "rotwk", "rotwk-201", "original-RotWK", "2.01"), ("BFME2", "bfme2", "bfme2-106", "original-BFME2", "1.06")]

SKIP_NAMES = {
    "game.dat": "the Windows game program",
    "game2.dat": "a Windows game program",
    "patchget.dat": "the Windows patch program",
    "asset.dat": "never read (docs/PLAN.md rule 11)",
    "00000000.256": "copy-protection data",
    "filelist.txt": "installer list",
    "launcher.txt": "installer leftover",
    "langdata.dat": "installer language data",
    "patch.doc": "patch notes",
    "profile-high.csv": "Windows graphics profile",
}
SKIP_EXTENSIONS = {
    ".exe": "Windows program", ".dll": "Windows library", ".asi": "Windows sound driver", ".m3d": "Windows sound driver",
    ".flt": "Windows sound driver", ".lcf": "installer leftover", ".dif": "patch leftover", ".diff": "patch leftover",
    ".dbgcmd": "Worldbuilder debug file",
}


class PackError(Exception):
    pass


def human(n: int) -> str:
    return f"{n / 1e9:.2f} GB" if n >= 1e8 else f"{n / 1e6:.1f} MB"


def file_hashes(path: Path) -> tuple[str, int, int]:
    """md5 hex, Adler-32 and size of a file, read in chunks"""
    md5, adler, size = hashlib.md5(), 1, 0
    with open(path, "rb") as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            md5.update(b)
            adler = zlib.adler32(b, adler)
            size += len(b)
    return md5.hexdigest(), adler, size


# ---- pins ---------------------------------------------------------------------------------------------------------------------------------

class Pins:
    """Every path / size / md5 the game and the launcher pin for one game (lower-case relative paths with '/')"""

    def __init__(self, game: str, policy_id: str, package: str):
        policy = json.loads((TABLES / f"{policy_id}-english-archives.json").read_text(encoding="utf-8"))
        excluded = json.loads((TABLES / f"{policy_id}-excluded-archives.json").read_text(encoding="utf-8"))
        self.patch = policy["patch"]
        self.archives = {a["path"].lower(): a for a in policy["archives"]}  # the base layout
        self.excluded = {e["path"].lower(): e.get("reason", "") for e in excluded["archives"]}
        self.big: dict[str, list[tuple[str, int, str]]] = {}  # path -> [(md5, size or 0, what)]
        for a in policy["archives"]:
            self.big.setdefault(a["path"].lower(), []).append((a["md5"], a["size"], "policy"))
        self.base_layout = policy.get("layouts", {}).get("base", {}).get("id", "base")
        self.layouts = policy.get("layouts", {}).get("others", [])
        for layout in self.layouts:
            for r in layout.get("replace", []):
                self.big.setdefault(r["path"].lower(), []).append((r["md5"], r["size"], "layout " + layout["id"]))
        languages = json.loads((TABLES / "language-archives.json").read_text(encoding="utf-8"))
        for lang in languages["languages"]:
            if lang["game"] == game:
                for a in lang["archives"]:
                    self.big.setdefault(a["path"].lower(), []).append((a["md5"], a["size"], "language " + lang["code"]))
        self.entry_checked = {e["path"].lower(): e for e in policy.get("entryChecked", [])}
        # loose files: the launcher's download (English) and its language additions
        self.loose: dict[str, list[tuple[str, int]]] = {}
        for path, md5, size in json.loads(AIO_FILES.read_text(encoding="utf-8"))[package]:
            self.loose.setdefault(path.lower(), []).append((md5, size))
        for lang in json.loads(AIO_LANGUAGES.read_text(encoding="utf-8")).get(package, {}).values():
            for path, md5, size in lang.get("add", []):
                self.loose.setdefault(path.lower(), []).append((md5, size))


def big_entries_problem(data: bytes, check: dict, label: str) -> str:
    """Engine's CheckArchiveEntries (Common/System/RetailArchivePolicy.cpp) for an entry-checked archive; "" when every entry is known"""
    what = f"{label}: {check['path']}"
    if len(data) < 16 or data[:4] not in (b"BIGF", b"BIG4"):
        return what + " is not a BIG archive"
    count = struct.unpack(">I", data[8:12])[0]
    if count > 4096 or count * 9 > len(data) - 16:
        return f"{what} declares {count} entries, more than it can hold"
    versions: dict[str, set[tuple[int, str]]] = {}
    for e in check["entries"]:
        versions.setdefault(e["name"], set()).add((e["size"], e["md5"]))
    seen: dict[str, str] = {}
    pos, hashed, problems = 16, 0, []
    for i in range(count):
        if pos + 8 > len(data):
            return f"{what}: its directory is cut short at entry {i}"
        offset, length = struct.unpack(">II", data[pos:pos + 8])
        pos += 8
        end = data.find(b"\0", pos, min(len(data), pos + 261))
        if end < 0:
            return f"{what}: the name of entry {i} is cut short or too long"
        name = data[pos:end].decode("latin-1").lower().replace("/", "\\")
        pos = end + 1
        if offset + length > len(data):
            return f"{what}: entry '{name}' runs past the end of the archive"
        hashed += length
        if hashed > len(data):
            return f"{what}: its entries overlap"
        md5 = hashlib.md5(data[offset:offset + length]).hexdigest()
        if name in seen:
            if seen[name] != md5:
                problems.append(f"'{name}' is stored twice with different contents")
            continue
        seen[name] = md5
        if name not in versions:
            problems.append(f"it holds '{name}', which no known copy has")
        elif (length, md5) not in versions[name]:
            problems.append(f"its '{name}' ({length} bytes, md5 {md5}) is not a version OpenBFME knows")
    for name in versions:
        if name not in seen:
            problems.append(f"'{name}' is missing")
    return "" if not problems else f"{what}: " + "; ".join(problems)


# ---- the plan -----------------------------------------------------------------------------------------------------------------------------

def classify(rel: str) -> tuple[bool, str]:
    """(included, reason when skipped) for a relative path with '/'"""
    low = rel.lower()
    name = low.rsplit("/", 1)[-1]
    if name.startswith("."):
        return False, "hidden file (folder metadata)"
    if low.endswith(".big"):
        return True, ""
    top = low.split("/", 1)[0] if "/" in low else ""
    if top in ("data", "lang"):
        return True, ""
    if top == "mss":
        return False, "Windows sound driver (mss/)"
    if not top:
        if name == "gi.dat" or name == "livingworld.txt" or name.endswith("splash.jpg"):
            return True, ""
        if name in SKIP_NAMES:
            return False, SKIP_NAMES[name]
        ext = os.path.splitext(name)[1]
        if ext in SKIP_EXTENSIONS:
            return False, SKIP_EXTENSIONS[ext]
    return False, "not a file the game reads"


def walk(root: Path) -> list[str]:
    out = []
    for d, dirs, files in os.walk(root):
        dirs.sort(key=str.lower)
        for f in files:
            out.append((Path(d) / f).relative_to(root).as_posix())
    return sorted(out, key=lambda p: (p.lower(), p))


def text_language(rels: list[str]) -> str:
    """the stem of the folder's single lang/<language>.big (no 'audio'/'patch' in it), as the engine's DetectRetailLanguage; "" otherwise"""
    stems = [r.split("/", 1)[1][:-4] for r in rels if r.lower().startswith("lang/") and r.lower().endswith(".big") and r.count("/") == 1
             and "audio" not in r.lower() and "patch" not in r.lower()]
    if any(s.lower() == "english" for s in stems):
        return "English"
    return stems[0] if len(stems) == 1 else ""


def plan_game(folder: str, root: Path, pins: Pins) -> dict:
    """checks one install; returns {files: [...], skipped: [...], errors, warnings, language, layout}"""
    label = folder
    rels = walk(root)
    files, skipped, errors, warnings = [], [], [], []
    present = {r.lower(): r for r in rels}
    language = text_language(rels)
    matched_layout = None
    for rel in rels:
        path = root / rel
        size = path.stat().st_size
        included, why = classify(rel)
        low = rel.lower()
        if included and low.endswith(".big") and low in pins.excluded:
            included, why = False, "not pure " + pins.patch + ", the game never mounts it: " + pins.excluded[low]
        if not included:
            skipped.append((rel, size, why))
            continue
        files.append({"rel": rel, "path": f"{folder}/{rel}", "size": size, "disk": path})

    total = sum(f["size"] for f in files)
    done = 0
    t0 = time.time()
    for f in files:
        md5, adler, size = file_hashes(f["disk"])
        done += size
        if size != f["size"]:
            errors.append(f"{label}/{f['rel']} changed while it was read (size {f['size']} then {size})")
        f.update(md5=md5, adler32=adler)
        low = f["rel"].lower()
        if low.endswith(".big"):
            cands = pins.big.get(low, [])
            hit = next((c for c in cands if c[0] == md5 and (c[1] in (0, size))), None)
            if hit:
                f["pin"] = hit[2]
                if hit[2].startswith("layout "):
                    matched_layout = hit[2][7:]
            elif low in pins.entry_checked:
                with open(f["disk"], "rb") as fh:
                    problem = big_entries_problem(fh.read(), pins.entry_checked[low], label)
                if problem:
                    errors.append(problem + " (the game refuses this archive)")
                f["pin"] = "entries"
            elif cands:
                errors.append(f"{label}/{f['rel']}: {size} bytes, md5 {md5}; {pins.patch} has "
                              + " or ".join(f"{c[1]} bytes, md5 {c[0]} ({c[2]})" for c in cands)
                              + ": a damaged, modified or other version of the file (the game refuses it)")
            elif low.startswith("lang/") and low.count("/") == 1:
                f["pin"] = "none"
                warnings.append(f"{label}/{f['rel']}: a language OpenBFME has not checked yet (md5 {md5}); the game plays it with a warning")
            else:
                errors.append(f"{label}/{f['rel']}: not a {pins.patch} archive (the game refuses a folder with an unknown .big; "
                              "move it out of the folder)")
        else:
            cands = pins.loose.get(low, [])
            if any(c[0] == md5 and c[1] in (0, size) for c in cands):
                f["pin"] = "aio"
            else:
                f["pin"] = "none"
                warnings.append(f"{label}/{f['rel']}: " + ("differs from the launcher download's copy" if cands else "no pin lists it")
                                + f" (md5 {md5}); copied as it is (the game does not check this file)")
        if sys.stdout.isatty():
            rate = done / max(time.time() - t0, 1e-6)
            print(f"\r  checking {label}: {human(done)} of {human(total)} ({rate / 1e6:.0f} MB/s)   ", end="", flush=True)
    if sys.stdout.isatty():
        print()

    # every archive the chosen layout needs (the language archives only for an English folder: another language's own are checked above)
    layout = next((l for l in pins.layouts if l["id"] == matched_layout), None)
    needed = dict(pins.archives)
    if layout:
        for gone in layout.get("absent", []):
            needed.pop(gone.lower(), None)
    for path, a in needed.items():
        if a.get("language", "ALL") != "ALL" and language != "English":
            continue
        if path not in present:
            errors.append(f"{label}: {a['path']} is missing (the game needs it)")
    return {"files": files, "skipped": skipped, "errors": errors, "warnings": warnings,
            "language": language, "layout": matched_layout or pins.base_layout}


# ---- writing ------------------------------------------------------------------------------------------------------------------------------

def zip_time(path: Path) -> tuple:
    t = time.localtime(max(path.stat().st_mtime, 315532800 + 86400))  # ZIP times start in 1980
    return t[:6]


def write_file(out: Path, manifest: dict, files: list[dict], method: int) -> None:
    partial = out.with_name(out.name + ".partial")
    total = sum(f["size"] for f in files)
    done = 0
    t0 = time.time()
    try:
        with zipfile.ZipFile(partial, "w", allowZip64=True) as zf:
            zi = zipfile.ZipInfo("manifest.json", time.localtime()[:6])
            zi.compress_type = zipfile.ZIP_STORED
            zi.external_attr = 0o644 << 16
            zf.writestr(zi, json.dumps(manifest, indent=1, ensure_ascii=False).encode("utf-8"))
            for f in files:
                zi = zipfile.ZipInfo(f["path"], zip_time(f["disk"]))
                zi.compress_type = method
                zi.external_attr = 0o644 << 16
                md5, adler, size = hashlib.md5(), 1, 0
                with open(f["disk"], "rb") as src, zf.open(zi, "w", force_zip64=True) as dst:
                    while True:
                        b = src.read(CHUNK)
                        if not b:
                            break
                        md5.update(b)
                        adler = zlib.adler32(b, adler)
                        size += len(b)
                        dst.write(b)
                        done += len(b)
                        if sys.stdout.isatty():
                            rate = done / max(time.time() - t0, 1e-6)
                            print(f"\r  writing: {human(done)} of {human(total)} ({rate / 1e6:.0f} MB/s)   ", end="", flush=True)
                if (md5.hexdigest(), adler, size) != (f["md5"], f["adler32"], f["size"]):
                    raise PackError(f"{f['path']} changed while the file was written: run the packer again")
        if sys.stdout.isatty():
            print()
        os.replace(partial, out)
    except BaseException:
        partial.unlink(missing_ok=True)
        raise


# ---- verifying (Python's zipfile, then the importer's own reading of the directory) ---------------------------------------------------

def read_directory(path: Path) -> list[dict]:
    """The ZIP's central directory read the way godot/scripts/release/game_file_import.gd reads it (EOCD, zip64 locator and record, zip64
    extra fields, the local header's name / extra lengths for the data offset). A disagreement with zipfile means the importer would fail."""
    with open(path, "rb") as f:
        f.seek(0, 2)
        length = f.tell()
        tail = min(length, 65557)
        f.seek(length - tail)
        buf = f.read(tail)
        at = buf.rfind(b"PK\x05\x06")
        if at < 0:
            raise PackError("no end of central directory")
        eocd = length - tail + at
        count, cd_size, cd_offset = struct.unpack("<HII", buf[at + 10:at + 20])
        if eocd >= 20:
            f.seek(eocd - 20)
            loc = f.read(20)
            if loc[:4] == b"PK\x06\x07":
                f.seek(struct.unpack("<Q", loc[8:16])[0])
                rec = f.read(56)
                if rec[:4] != b"PK\x06\x06":
                    raise PackError("bad zip64 end of central directory")
                count, cd_size, cd_offset = struct.unpack("<QQQ", rec[32:56])
        f.seek(cd_offset)
        cd = f.read(cd_size)
        out, pos = [], 0
        for _ in range(count):
            if cd[pos:pos + 4] != b"PK\x01\x02":
                raise PackError(f"bad central directory entry at {pos}")
            flags, method = struct.unpack("<HH", cd[pos + 8:pos + 12])
            csize, usize = struct.unpack("<II", cd[pos + 20:pos + 28])
            nlen, xlen, clen = struct.unpack("<HHH", cd[pos + 28:pos + 34])
            offset = struct.unpack("<I", cd[pos + 42:pos + 46])[0]
            name = cd[pos + 46:pos + 46 + nlen].decode("utf-8" if flags & 0x800 else "cp437")
            x = pos + 46 + nlen
            xend = x + xlen
            while x + 4 <= xend:
                tag, size = struct.unpack("<HH", cd[x:x + 4])
                if tag == 1:
                    y = x + 4
                    if usize == 0xFFFFFFFF:
                        usize = struct.unpack("<Q", cd[y:y + 8])[0]; y += 8
                    if csize == 0xFFFFFFFF:
                        csize = struct.unpack("<Q", cd[y:y + 8])[0]; y += 8
                    if offset == 0xFFFFFFFF:
                        offset = struct.unpack("<Q", cd[y:y + 8])[0]; y += 8
                x += 4 + size
            pos = xend + clen
            f.seek(offset)
            local = f.read(30)
            if local[:4] != b"PK\x03\x04":
                raise PackError(f"{name}: bad local header")
            name_len, extra_len = struct.unpack("<HH", local[26:30])
            data = offset + 30 + name_len + extra_len
            out.append({"name": name, "method": method, "flags": flags, "csize": csize, "usize": usize, "data": data})
        return out


def verify(out: Path, manifest: dict) -> None:
    files = {f["path"]: f for f in manifest["files"]}
    t0 = time.time()
    with zipfile.ZipFile(out) as zf:
        infos = zf.infolist()
        if not infos or infos[0].filename != "manifest.json":
            raise PackError("manifest.json is not the first entry")
        if json.loads(zf.read("manifest.json")) != manifest:
            raise PackError("manifest.json does not read back the same")
        names = [i.filename for i in infos[1:]]
        if sorted(names) != sorted(files):
            raise PackError("the entries are not the manifest's files")
        done = 0
        for i in infos[1:]:
            f = files[i.filename]
            md5 = hashlib.md5()
            with zf.open(i) as src:
                while True:
                    b = src.read(CHUNK)
                    if not b:
                        break
                    md5.update(b)
            if i.file_size != f["size"] or md5.hexdigest() != f["md5"]:
                raise PackError(f"{i.filename} reads back wrong (zipfile)")
            done += i.file_size
            if sys.stdout.isatty():
                print(f"\r  verifying with zipfile: {human(done)} of {human(manifest['bytes'])}   ", end="", flush=True)
    if sys.stdout.isatty():
        print()
    entries = read_directory(out)
    by_name = {e["name"]: e for e in entries}
    if len(entries) != len(files) + 1 or set(by_name) != set(files) | {"manifest.json"}:
        raise PackError("the importer's reading of the directory disagrees with zipfile's")
    with open(out, "rb") as fh:
        for name, f in files.items():
            e = by_name[name]
            if e["usize"] != f["size"] or e["method"] not in (0, 8) or e["flags"] & 1:
                raise PackError(f"{name}: the importer's reading disagrees (size {e['usize']}, method {e['method']})")
        # spot-check: the importer's inflate (zlib header + raw deflate + the manifest's Adler-32 as the trailer) on the smallest and
        # largest entries, from the data offsets it computes
        for f in (min(files.values(), key=lambda f: f["size"]), max(files.values(), key=lambda f: f["size"])):
            e = by_name[f["path"]]
            fh.seek(e["data"])
            md5, size, left = hashlib.md5(), 0, e["csize"]
            inflater = zlib.decompressobj(15) if e["method"] == 8 else None
            if inflater:
                md5.update(inflater.decompress(b"\x78\x9c"))
            while left:
                b = fh.read(min(CHUNK, left))
                left -= len(b)
                b = inflater.decompress(b) if inflater else b
                md5.update(b); size += len(b)
            if inflater:
                b = inflater.decompress(struct.pack(">I", f["adler32"])) + inflater.flush()
                md5.update(b); size += len(b)
                if not inflater.eof:
                    raise PackError(f"{f['path']}: the Adler-32 trailer did not end the zlib stream")
            if size != f["size"] or md5.hexdigest() != f["md5"]:
                raise PackError(f"{f['path']}: the importer's reading of its data gives other bytes")
    print(f"  verified: {len(files)} files read back with zipfile and the importer's directory reading ({time.time() - t0:.0f} s)")


# ---- main ---------------------------------------------------------------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Pack the RotWK 2.01 and BFME2 1.06 folders into one file for OpenBFME on iPhone / iPad.")
    ap.add_argument("--rotwk", default=os.environ.get("ROTWK_INSTALL", ""), help="The Rise of the Witch-king 2.01 folder (ROTWK_INSTALL)")
    ap.add_argument("--bfme2", default=os.environ.get("BFME2_INSTALL", ""), help="The Battle for Middle-earth II 1.06 folder (BFME2_INSTALL)")
    ap.add_argument("--out", default="OpenBFME-GameData.obfme", help="the file to write (default: OpenBFME-GameData.obfme here)")
    ap.add_argument("--store", action="store_true", help="store the files uncompressed (a bigger file, faster to make and to install)")
    ap.add_argument("--no-verify", action="store_true", help="do not read the finished file back")
    ap.add_argument("--dry-run", action="store_true", help="list what would go in and what stays out, without reading the files")
    a = ap.parse_args()

    roots = {"RotWK": a.rotwk, "BFME2": a.bfme2}
    for folder, root in roots.items():
        if not root:
            print(f"error: no {folder} folder: pass --{folder.lower()} DIR or set {folder.upper()}_INSTALL", file=sys.stderr)
            return 2
        if not Path(root).is_dir():
            print(f"error: the {folder} folder does not exist: {root}", file=sys.stderr)
            return 2
    out = Path(a.out).expanduser().resolve()
    for root in roots.values():
        if Path(root).resolve() in out.parents:
            print(f"error: write the file outside the game folders, not into {root}", file=sys.stderr)
            return 2

    if a.dry_run:
        for folder, game, policy_id, package, _patch in GAMES:
            root = Path(roots[folder])
            excluded = Pins(game, policy_id, package).excluded
            inc, skip = [], {}
            for rel in walk(root):
                size = (root / rel).stat().st_size
                ok, why = classify(rel)
                if ok and rel.lower() in excluded:
                    ok, why = False, "excluded archive (2.02 / HD)"
                if ok:
                    inc.append(size)
                else:
                    skip.setdefault(why, []).append((rel, size))
            print(f"{folder}: {len(inc)} files, {human(sum(inc))} go in")
            for why, items in sorted(skip.items()):
                print(f"  skipped {len(items):3d} files, {human(sum(s for _, s in items)):>9}: {why}: "
                      + ", ".join(r for r, _ in items[:4]) + (" ..." if len(items) > 4 else ""))
        return 0

    print("OpenBFME game file (lane IOS-9): checking the folders")
    plans, files, errors, warnings, skipped = [], [], [], [], []
    for folder, game, policy_id, package, patch in GAMES:
        plan = plan_game(folder, Path(roots[folder]), Pins(game, policy_id, package))
        plans.append((folder, game, patch, plan))
        files += plan["files"]
        errors += plan["errors"]
        warnings += plan["warnings"]
        skipped += [(folder, *s) for s in plan["skipped"]]
    for folder, game, patch, plan in plans:
        print(f"  {folder}: {len(plan['files'])} files, {human(sum(f['size'] for f in plan['files']))} "
              f"({plan['language'] or 'no language found'}, layout {plan['layout']}); skipped {len(plan['skipped'])} files, "
              f"{human(sum(s[1] for s in plan['skipped']))}")
    reasons: dict[str, list] = {}
    for folder, rel, size, why in skipped:
        reasons.setdefault(why, []).append((f"{folder}/{rel}", size))
    for why, items in sorted(reasons.items()):
        print(f"  skipped {len(items):3d} files, {human(sum(s for _, s in items)):>9}: {why}")
    for w in warnings:
        print("  warning: " + w)
    if errors:
        for e in errors:
            print("error: " + e, file=sys.stderr)
        print(f"Nothing written: {len(errors)} problem(s) above. These folders would not work on the phone either.", file=sys.stderr)
        return 1

    total = sum(f["size"] for f in files)
    out.parent.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(out.parent).free
    if free < total + MARGIN:  # the compressed size is not known before; the uncompressed size is the bound
        print(f"error: {out.parent} has {human(free)} free; the file can take up to {human(total + MARGIN)}", file=sys.stderr)
        return 1
    manifest = {
        "format": FORMAT,
        "formatVersion": FORMAT_VERSION,
        "tool": "tools/ios/make_game_file.py (lane IOS-9)",
        "created": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "method": "stored" if a.store else "deflate",
        "games": [{"folder": folder, "game": game, "patch": patch, "language": plan["language"], "layout": plan["layout"],
                   "files": len(plan["files"]), "bytes": sum(f["size"] for f in plan["files"])} for folder, game, patch, plan in plans],
        "bytes": total,
        "files": [{"path": f["path"], "size": f["size"], "md5": f["md5"], "adler32": f["adler32"], "pin": f["pin"]} for f in files],
        "warnings": warnings,
    }
    print(f"Writing {out} ({len(files)} files, {human(total)}, {'stored' if a.store else 'deflate'})")
    t0 = time.time()
    try:
        write_file(out, manifest, files, zipfile.ZIP_STORED if a.store else zipfile.ZIP_DEFLATED)
    except PackError as e:
        print("error: " + str(e), file=sys.stderr)
        return 1
    size = out.stat().st_size
    print(f"  wrote {human(size)} ({100 * size / total:.0f} % of {human(total)}) in {time.time() - t0:.0f} s")
    if not a.no_verify:
        try:
            verify(out, manifest)
        except (PackError, zipfile.BadZipFile) as e:
            print(f"error: the finished file does not read back: {e}", file=sys.stderr)
            return 1
    print(f"Done: {out}\nCopy this one file to OpenBFME on the iPhone / iPad (Finder > the device > Files > drag it onto OpenBFME); "
          "the app installs it and removes it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
