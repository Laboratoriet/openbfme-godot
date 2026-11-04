"""Lanes IOS-28 / IOS-30: what the INI mod generators share (make_sauron_mod.py, make_ini_mods.py): the RotWK 2.01 archives read in the
game's own order, a BIGF writer, small INI text edits that keep every other byte, and the mod folder (<name>.big + mod.txt) they write.

Nothing here holds game data: the generators read YOUR OWN install at run time and write their output outside the repository.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
POLICY = ROOT / "engine" / "data" / "retail-archives" / "rotwk-201-english-archives.json"
# a folder of the Object folder that sorts after every retail one: the game loads data\ini\object\ recursively in case-insensitive name order, so
# a new file here is read after the retail objects (a ChildObject after its parent) and after data\ini\playertemplate.ini (its own subsystem)
MOD_OBJECT_FOLDER = "data\\ini\\object\\zzmods\\"


class ModError(RuntimeError):
    pass


# ---------------------------------------------------------------------------------------------------------------------------------
# BIG archives
# ---------------------------------------------------------------------------------------------------------------------------------
def read_big_index(path: Path) -> list[tuple[str, int, int]]:
    """[(name, offset, size)] of a BIGF / BIG4 archive (count and offsets big-endian, as Win32BIGFileSystem reads them)"""
    with open(path, "rb") as f:
        head = f.read(16)
        if len(head) < 16 or head[:4] not in (b"BIGF", b"BIG4"):
            raise ModError(f"{path}: not a .big archive")
        count = struct.unpack(">I", head[8:12])[0]
        index_end = struct.unpack(">I", head[12:16])[0]
        index = f.read(max(0, index_end - 16))
    out, at = [], 0
    for _ in range(count):
        if at + 8 > len(index):
            raise ModError(f"{path}: the index is cut short")
        off, size = struct.unpack(">II", index[at:at + 8])
        end = index.find(b"\0", at + 8)
        if end < 0:
            raise ModError(f"{path}: an index name has no end")
        out.append((index[at + 8:end].decode("latin-1"), off, size))
        at = end + 1
    return out


def write_big(path: Path, files: list[tuple[str, bytes]]) -> None:
    """a BIGF archive: magic, the archive's size (little-endian, as the 2.01 patch archives), count and the first data offset
    (big-endian), the index {offset, size, NUL-terminated name}, then the data in index order"""
    index_size = sum(8 + len(n.encode("latin-1")) + 1 for n, _ in files)
    at = 16 + index_size
    entries, body = b"", b""
    for name, data in files:
        entries += struct.pack(">II", at + len(body), len(data)) + name.encode("latin-1") + b"\0"
        body += data
    path.write_bytes(b"BIGF" + struct.pack("<I", 16 + len(entries) + len(body)) + struct.pack(">II", len(files), 16 + len(entries)) + entries + body)


def key(name: str) -> str:
    return name.replace("/", "\\").lower()


def find_case_insensitive(folder: Path, rel: str) -> Path:
    cur = folder
    for part in rel.replace("\\", "/").split("/"):
        hits = [x for x in os.listdir(cur) if x.lower() == part.lower()] if cur.is_dir() else []
        if not hits:
            raise ModError(f"{rel} is not in {folder}")
        cur = cur / hits[0]
    return cur


class RetailArchives:
    """the RotWK 2.01 archives in the pinned policy's order; the FIRST archive holding a path wins it (as the retail mount)"""

    def __init__(self, rotwk: Path, policy: Path = POLICY):
        self.files: dict[str, tuple[Path, str, int, int]] = {}
        names = [a["path"] for a in json.loads(policy.read_text())["archives"]]
        for rel in names:
            archive = find_case_insensitive(rotwk, rel)
            for name, off, size in read_big_index(archive):
                self.files.setdefault(key(name), (archive, name, off, size))

    def read(self, path: str) -> tuple[str, bytes, str]:
        """(the archive's own spelling of the path, the bytes, the archive's file name)"""
        hit = self.files.get(key(path))
        if hit is None:
            raise ModError(f"{path} is in none of the RotWK archives")
        archive, name, off, size = hit
        with open(archive, "rb") as f:
            f.seek(off)
            data = f.read(size)
        if len(data) != size:
            raise ModError(f"{archive.name}: {path} is cut short")
        return name, data, archive.name

    def text(self, path: str) -> tuple[str, str]:
        """(the archive's spelling, the text as latin-1: every byte maps to one character and back)"""
        name, data, _ = self.read(path)
        return name, data.decode("latin-1")

    def names_under(self, folder: str) -> list[str]:
        """the lower-case keys of every file under `folder` (a data\\ini\\object\\ style prefix)"""
        prefix = key(folder)
        return sorted(k for k in self.files if k.startswith(prefix))


# ---------------------------------------------------------------------------------------------------------------------------------
# INI text: line edits that keep every other byte (CRLF, tabs, comments)
# ---------------------------------------------------------------------------------------------------------------------------------
def split_comment(value: str) -> tuple[str, str]:
    """(the value, the comment with its marker) of an INI value; ';' and '//' start a comment"""
    cut = len(value)
    for marker in (";", "//"):
        i = value.find(marker)
        if 0 <= i < cut:
            cut = i
    return value[:cut], value[cut:]


def lines_of(text: str) -> list[str]:
    """the lines with their own line ends (join them back with '')"""
    return text.splitlines(keepends=True)


def body_eol(line: str) -> tuple[str, str]:
    body = line.rstrip("\r\n")
    return body, line[len(body):]


def find_block(lines: list[str], kind: str, name: str) -> tuple[int, int]:
    """(first, end) line indices of a FLAT block "<kind> <name>" .. "End" (end = the first End after it: CommandButton, PlayerTemplate,
    GameData, CommandSet, which hold no nested blocks)"""
    head = re.compile(r"^\s*" + re.escape(kind) + r"\s+" + re.escape(name) + r"\s*(?:;.*|//.*)?$", re.IGNORECASE)
    for i, line in enumerate(lines):
        if head.match(line.rstrip("\r\n")):
            for j in range(i + 1, len(lines)):
                if re.match(r"^\s*End\b", lines[j], re.IGNORECASE):
                    return i, j
            raise ModError(f"{kind} {name} has no End")
    raise ModError(f"there is no {kind} {name}")


def find_unnamed_block(lines: list[str], kind: str) -> tuple[int, int]:
    """(first, end) of the first flat block "<kind>" .. "End" with no name (GameData)"""
    for i, line in enumerate(lines):
        if re.match(r"^\s*" + re.escape(kind) + r"\s*(?:;.*|//.*)?$", line.rstrip("\r\n"), re.IGNORECASE):
            for j in range(i + 1, len(lines)):
                if re.match(r"^\s*End\b", lines[j], re.IGNORECASE):
                    return i, j
            raise ModError(f"{kind} has no End")
    raise ModError(f"there is no {kind} block")


_OBJECT_HEAD = re.compile(r"^\s*(Object|ChildObject|ObjectReskin)\s+([A-Za-z_][\w]*)(?:\s+([A-Za-z_][\w]*))?\s*(?:;.*|//.*)?$", re.IGNORECASE)


def object_heads(lines: list[str]) -> list[tuple[int, str, str, str]]:
    """[(line index, keyword, name, parent or '')] of every Object / ChildObject / ObjectReskin header of an object file"""
    out = []
    for i, line in enumerate(lines):
        m = _OBJECT_HEAD.match(line.rstrip("\r\n"))
        if m:
            out.append((i, m.group(1), m.group(2), m.group(3) or ""))
    return out


# the other top-level blocks an object file may hold ("<keyword> <name>", no '='); inside an object these words only start `field = value` lines
_TOP_LEVEL = re.compile(r"^\s*(Weapon|Armor|Locomotor|FXList|ObjectCreationList|CommandSet|CommandButton|Upgrade|SpecialPower|ExperienceLevel|"
                        r"ModifierList|PlayerTemplate|GameData|AudioEvent|DialogEvent|MusicTrack|ParticleSystem|FXParticleSystem|MappedImage|"
                        r"Science|StanceTemplate|CrateData|DamageFX|EmotionNugget|Rank)\s+[^=\s]+\s*(?:;.*|//.*)?$", re.IGNORECASE)


def find_object_block(lines: list[str], name: str) -> tuple[int, int, str, str]:
    """(header, end, keyword, parent) of an object's top-level block. Objects nest blocks (Draw, Behavior, WeaponSet ...), so the block's End is
    the LAST End before the next object header (or the end of the file). Anything but blank or comment lines between that End and the next
    header, or another top-level block inside the range, is an error (the file holds something this reader does not understand)."""
    heads = object_heads(lines)
    for n, (i, kw, nm, parent) in enumerate(heads):
        if nm.lower() != name.lower():
            continue
        stop = heads[n + 1][0] if n + 1 < len(heads) else len(lines)
        for j in range(stop - 1, i, -1):
            body = split_comment(lines[j].rstrip("\r\n"))[0].strip()
            if not body:
                continue
            if not re.match(r"^End\b", body, re.IGNORECASE):
                raise ModError(f"{kw} {name}: line {j + 1} ('{body}') stands between its End and the next object")
            for k in range(i + 1, j):
                if _TOP_LEVEL.match(lines[k].rstrip("\r\n")):
                    raise ModError(f"{kw} {name}: line {k + 1} ('{lines[k].strip()}') starts a block of its own before the object's End")
            return i, j, kw, parent
        raise ModError(f"{kw} {name} has no End")
    raise ModError(f"there is no Object {name}")


def field_value(lines: list[str], first: int, end: int, field: str) -> tuple[int, str]:
    """(line index, the value without its comment) of the first `field = value` line inside (first, end)"""
    for i in range(first + 1, end):
        m = re.match(r"^\s*" + re.escape(field) + r"\s*=(.*)$", lines[i].rstrip("\r\n"), re.IGNORECASE)
        if m:
            return i, split_comment(m.group(1))[0].strip()
    raise ModError(f"line {first + 1}: the block has no {field}")


def list_field(text: str, kind: str, name: str, field: str) -> list[str]:
    lines = lines_of(text)
    first, end = find_block(lines, kind, name)
    return field_value(lines, first, end, field)[1].split()


def set_value(line: str, new_value: str) -> str:
    """`line` (a `field = value ; comment` line with its end) with the value replaced; the key, the spacing before the value, the comment and
    the line end stay"""
    body, eol = body_eol(line)
    m = re.match(r"^(\s*[^=]+=\s*)(.*)$", body)
    if not m:
        raise ModError(f"'{body}' is not a field line")
    value, comment = split_comment(m.group(2))
    return m.group(1) + new_value + value[len(value.rstrip()):] + comment + eol


# ---------------------------------------------------------------------------------------------------------------------------------
# the mod folder
# ---------------------------------------------------------------------------------------------------------------------------------
def write_mod_folder(out: Path, name: str, files: list[tuple[str, bytes]], title: str, description: str) -> dict:
    """<out>/<name>/{<name>.big (the files, in the given order), mod.txt (the Mods tab's title and description)}"""
    if not files:
        raise ModError(f"{name}: no files")
    seen = set()
    for path, _ in files:
        if key(path) in seen:
            raise ModError(f"{name}: {path} twice")
        seen.add(key(path))
    folder = out / name
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    big = folder / (name + ".big")
    write_big(big, files)
    (folder / "mod.txt").write_text(f"Title = {title}\nDescription = {description}\n", encoding="utf-8")
    return {"folder": folder, "archive": big, "files": [p for p, _ in files]}


def inside_repository(path: Path) -> bool:
    p = path.resolve()
    return p == ROOT or ROOT in p.parents


def copy_mod(folder: Path, mods_folder: Path) -> Path:
    target = mods_folder / folder.name
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(folder, target)
    return target
