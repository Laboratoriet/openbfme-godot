## Lane IOS-9: installs the game files from ONE file, OpenBFME-GameData.obfme, made on a Mac by tools/ios/make_game_file.py.
##
## An iPhone / iPad app reads only its own folder (lane IOS-4), so the player copies that one file into it (Finder's Files tab, AirDrop + Save
## to Files, or the Files app's On My iPhone > OpenBFME). This finds it in user:// (the app's Documents) or user://Inbox (where "Open in" and
## some AirDrop deliveries land), and extracts it into user://RotWK and user://BFME2, the folders IOS-4's discovery finds (InstallLocator.h
## "iOS"); the first-run screen (first_run.gd) then checks and mounts them as it does copied folders.
##
## The file is a ZIP (the packer's docstring has the format): manifest.json, then RotWK/<path> and BFME2/<path>, STORED or DEFLATE, zip64.
## The central directory is read here with FileAccess (the end record, the zip64 locator and record, the zip64 extra fields); every entry is
## streamed in CHUNK pieces (never a whole entry in memory) into <target>.part, MD5'd while it is written (HashingContext), compared with the
## manifest and only then renamed into place. DEFLATE: Godot's StreamPeerGZIP inflates zlib streams only (core/io/stream_peer_gzip.cpp:
## windowBits 15), so each raw ZIP stream gets zlib's two header bytes in front and the manifest's Adler-32 of the file behind: zlib then ends
## the stream, hands out its last bytes and checks the Adler-32 as well.
##
## Resumable: every file written and checked is added to user://.openbfme-import.tsv (the archive's size and the manifest's MD5 head it); a
## file listed there and present with its size is not written again. A file already in place but not listed (copied by hand) is hashed and
## kept when its MD5 is the manifest's. When every file is in place the .obfme file and the list are deleted. Nothing is guessed: every
## problem ends the run with `error` set to what happened and what to do.
##
## Lane IOS-36: open() takes any absolute path, so the welcome screen also hands it a file the player picked where it is with Files' document
## picker (iCloud Drive, Downloads, a drive: engine IOSDocumentPickerBridge.mm holds the item's security scope while this reads it). Such a file
## is read in place, with no copy into the app first, and keep_file leaves it there afterwards: it is the player's, maybe in iCloud for another
## device, and the screen says it can be deleted.
##
## The md5 cache of the game's own check (user://retail-md5-cache.tsv, engine Common/Md5Cache.h) is not filled here: its key is the file's
## absolute path, size and last-write time in nanoseconds (std::filesystem::last_write_time), and GDScript reads modification times in whole
## seconds only (FileAccess.get_modified_time). The first start after the install hashes every archive once (lane PERF-2: on the job pool).
extends RefCounted

signal progress(done_bytes: int, total_bytes: int, file_index: int, file_count: int, file_path: String)

const EXTENSION := "obfme"
const FORMAT := "openbfme.game-file"
const FORMAT_VERSION := 1
const FOLDERS := ["RotWK", "BFME2"]
const JOURNAL := ".openbfme-import.tsv"
const CHUNK := 4 << 20             # bytes read per step of a stored entry, and the size of zlib's output ring
const DEFLATE_CHUNK := 1 << 20     # compressed bytes fed to zlib per step (they unpack to about twice that)
const FRAME_BUDGET_USEC := 25000   # work per frame before the screen gets a frame (about 40 frames a second while installing)
const SPACE_MARGIN := 256 << 20    # kept free beyond the files themselves (the game's logs, saves and md5 cache)
const MANIFEST_MAX := 16 << 20

var root := "user://"     # the app's Documents (a test may point it elsewhere)
var path := ""            # the .obfme file being installed (absolute)
var file_name := ""
var archive_size := 0
var games: Array = []     # the manifest's games: [{folder, game, patch, language, ...}]
var files: Array = []     # [{path, size, md5, adler32, method, csize, data, target}] in the file's order
var total := 0            # bytes of every file
var remaining := 0        # bytes still to write (files not listed as done)
var resuming := false     # an earlier run's list matches this file
var error := ""           # set when open() or run() returns false: what happened and what to do
var keep_file := false    # lane IOS-36: the file was picked where it is (Files' document picker, first_run.gd): read in place, not deleted after

var _journal_head := ""
var _done := {}           # path -> true: written and checked by an earlier run (the journal)


# Every *.obfme file in the app's Documents and its Inbox, newest first (absolute paths).
static func find(in_root := "user://") -> PackedStringArray:
	var found: Array = []
	for dir in [in_root, in_root.path_join("Inbox")]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if f.get_extension().to_lower() == EXTENSION and not f.begins_with("."):
				var p := ProjectSettings.globalize_path(dir.path_join(f))
				found.append([FileAccess.get_modified_time(p), p])
	found.sort_custom(func(a, b): return a[0] > b[0])
	var out := PackedStringArray()
	for f in found:
		out.push_back(f[1])
	return out


# An install was started and not finished (its list is there): the start must not mount the half-written folders (release.gd).
static func pending(in_root := "user://") -> bool:
	return FileAccess.file_exists(in_root.path_join(JOURNAL))


static func gb(bytes: int) -> String:
	return "%.1f GB" % (bytes / 1e9)


# Reads the file's directory and manifest and what an earlier run finished. No file is written. false: `error` says why.
func open(file: String) -> bool:
	error = ""
	path = file
	file_name = file.get_file()
	files.clear()
	games.clear()
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return _fail("%s cannot be opened (%s). Copy it into OpenBFME's folder again." % [file_name, error_string(FileAccess.get_open_error())])
	archive_size = f.get_length()
	var entries := _read_directory(f)
	if entries.is_empty():
		return false
	var by_name := {}
	for e in entries:
		by_name[e["name"]] = e
	if not by_name.has("manifest.json"):
		return _fail("%s is not an OpenBFME game file (it has no manifest.json). Make it with tools/ios/make_game_file.py on the Mac." % file_name)
	var m: Dictionary = by_name["manifest.json"]
	if m["method"] != 0 or m["size"] > MANIFEST_MAX:
		return _fail("%s: its manifest.json is not stored as tools/ios/make_game_file.py stores it. Make the file again." % file_name)
	f.seek(m["data"])
	var manifest_bytes := f.get_buffer(m["size"])
	if manifest_bytes.size() != m["size"]:
		return _fail("%s is cut short (its manifest cannot be read): the copy did not finish. Copy it again." % file_name)
	var manifest = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if typeof(manifest) != TYPE_DICTIONARY or manifest.get("format", "") != FORMAT:
		return _fail("%s is not an OpenBFME game file (its manifest is not one). Make it with tools/ios/make_game_file.py on the Mac." % file_name)
	if int(manifest.get("formatVersion", 0)) != FORMAT_VERSION:
		return _fail("%s was made by another version of OpenBFME's packer (format %s; this app reads %d). Make it again with this version's tools/ios/make_game_file.py, or update the app." % [file_name, str(manifest.get("formatVersion", "?")), FORMAT_VERSION])
	games = manifest.get("games", [])
	var listed: Array = manifest.get("files", [])
	if listed.is_empty() or by_name.size() != listed.size() + 1:
		return _fail("%s: its manifest lists %d files, the file holds %d. Make the file again." % [file_name, listed.size(), by_name.size() - 1])
	total = 0
	for item in listed:
		var p: String = str(item.get("path", ""))
		if not _safe_path(p):
			return _fail("%s lists a file outside RotWK / BFME2 (%s). Make the file again with tools/ios/make_game_file.py." % [file_name, p])
		if not by_name.has(p):
			return _fail("%s: %s is in its manifest but not in the file. Make the file again." % [file_name, p])
		var entry: Dictionary = by_name[p]
		var md5 := str(item.get("md5", ""))
		if int(item.get("size", -1)) != entry["size"] or md5.length() != 32 or not md5.is_valid_hex_number():
			return _fail("%s: %s does not match its manifest. Make the file again." % [file_name, p])
		files.append({"path": p, "size": entry["size"], "md5": md5.to_lower(), "adler32": int(item.get("adler32", 0)),
			"method": entry["method"], "csize": entry["csize"], "data": entry["data"], "target": _target(p)})
		total += entry["size"]
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	hashing.update(manifest_bytes)
	_journal_head = "openbfme-import\t%s\t%d\t%s" % [file_name, archive_size, hashing.finish().hex_encode()]
	_read_journal()
	remaining = 0
	for item in files:
		if not _is_done(item):
			remaining += item["size"]
	return true


# Bytes free where the files go (0: the system did not say).
func space_left() -> int:
	var d := DirAccess.open(root)
	return d.get_space_left() if d != null else 0


func space_needed() -> int:
	return remaining + SPACE_MARGIN


# Writes every file not done yet, then deletes the .obfme file and the list. Awaits a frame whenever FRAME_BUDGET_USEC of work is done, so the
# screen keeps drawing. false: `error` says what happened and what to do (the files written so far are kept; running again continues).
func run() -> bool:
	error = ""
	var tree := Engine.get_main_loop() as SceneTree
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null:
		return _fail("%s cannot be opened (%s). Copy it into OpenBFME's folder again." % [file_name, error_string(FileAccess.get_open_error())])
	if src.get_length() != archive_size:
		return _fail("%s changed since it was read. Tap Look again." % file_name)
	if not _start_journal():
		return false
	var done_bytes := 0
	var tick := Time.get_ticks_usec()
	for i in files.size():
		var item: Dictionary = files[i]
		progress.emit(done_bytes, total, i + 1, files.size(), item["path"])
		if _is_done(item):
			done_bytes += item["size"]
			continue
		# already in place (copied by hand, or written before the list was): kept when it is the manifest's file
		if _size_of(item["target"]) == item["size"]:
			var have := await _hash_file(item["target"], tree)
			if have.is_empty():
				return false
			if have == item["md5"]:
				if not _journal_add(item):
					return false
				done_bytes += item["size"]
				continue
		var dir: String = item["target"].get_base_dir()
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return _fail("The folder %s cannot be made (%s). Restart OpenBFME and tap Install again." % [_shown(dir), error_string(made)])
		var part: String = item["target"] + ".part"
		var dst := FileAccess.open(part, FileAccess.WRITE)
		if dst == null:
			return _fail("%s cannot be written (%s). Check that the %s has space, then tap Install again." % [_shown(part), error_string(FileAccess.get_open_error()), _device()])
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		var written := 0
		src.seek(item["data"])
		var gz: StreamPeerGZIP = null
		if item["method"] == 8:
			gz = StreamPeerGZIP.new()
			if gz.start_decompression(true, CHUNK) != OK:
				return _abandon(dst, part, "OpenBFME could not start unpacking %s. Restart OpenBFME and tap Install again." % item["path"])
			written = _feed(gz, PackedByteArray([0x78, 0x9C]), ctx, dst, item, written) # zlib's header: 32 KB window, default level
			if written < 0:
				return _abandon(dst, part, error)
		var left: int = item["csize"]
		while left > 0:
			var n := mini(CHUNK if gz == null else DEFLATE_CHUNK, left)
			var buf := src.get_buffer(n)
			if buf.size() != n:
				return _abandon(dst, part, "%s is cut short at %s: the copy did not finish. Copy it again." % [file_name, item["path"]])
			left -= n
			if gz == null:
				ctx.update(buf)
				if not dst.store_buffer(buf):
					return _abandon(dst, part, _write_error(item))
				written += n
			else:
				written = _feed(gz, buf, ctx, dst, item, written)
				if written < 0:
					return _abandon(dst, part, error)
			if Time.get_ticks_usec() - tick > FRAME_BUDGET_USEC:
				progress.emit(done_bytes + mini(written, item["size"]), total, i + 1, files.size(), item["path"])
				await tree.process_frame
				tick = Time.get_ticks_usec()
		if gz != null:
			var a: int = item["adler32"]
			written = _feed(gz, PackedByteArray([(a >> 24) & 0xFF, (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF]), ctx, dst, item, written)
			if written < 0:
				return _abandon(dst, part, error)
		dst.flush()
		var write_error := dst.get_error()
		dst.close()
		if write_error != OK:
			return _abandon(null, part, _write_error(item))
		var md5 := ctx.finish().hex_encode()
		if written != item["size"] or md5 != item["md5"]:
			return _abandon(null, part, "%s arrived damaged (%d bytes, md5 %s; the manifest says %d bytes, md5 %s). Make the file again on the Mac and copy it again." % [
				item["path"], written, md5, item["size"], item["md5"]])
		var moved := DirAccess.rename_absolute(part, item["target"])
		if moved != OK:
			return _abandon(null, part, "%s cannot be put in place (%s). Restart OpenBFME and tap Install again." % [_shown(item["target"]), error_string(moved)])
		if not _journal_add(item):
			return false
		done_bytes += item["size"]
	progress.emit(total, total, files.size(), files.size(), "")
	src = null # closed before it is deleted
	if not keep_file:
		var removed := DirAccess.remove_absolute(path)
		if removed != OK:
			return _fail("The game files are installed, but %s could not be deleted (%s): delete it in the Files app to get its space back." % [file_name, error_string(removed)])
	DirAccess.remove_absolute(root.path_join(JOURNAL))
	return true


# ---- the ZIP directory ---------------------------------------------------------------------------------------------------------------------

# [{name, method, size, csize, data}] from the central directory (APPNOTE 4.3.12-4.3.16, zip64 4.3.14 / 4.5.3); [] with `error` set.
func _read_directory(f: FileAccess) -> Array:
	var length := f.get_length()
	var tail := mini(length, 65557) # the end record (22 bytes) and a comment of at most 65535
	f.seek(length - tail)
	var buf := f.get_buffer(tail)
	var at := -1
	for i in range(buf.size() - 22, -1, -1):
		if buf[i] == 0x50 and buf[i + 1] == 0x4B and buf[i + 2] == 0x05 and buf[i + 3] == 0x06:
			at = i
			break
	if at < 0:
		_fail("%s is not a ZIP file, or it is cut short (the copy did not finish). Copy it again." % file_name)
		return []
	var eocd := length - tail + at
	var count := buf.decode_u16(at + 10)
	var cd_size := buf.decode_u32(at + 12)
	var cd_offset := buf.decode_u32(at + 16)
	if eocd >= 20:
		f.seek(eocd - 20)
		var loc := f.get_buffer(20)
		if loc.decode_u32(0) == 0x07064b50:
			f.seek(loc.decode_u64(8))
			var rec := f.get_buffer(56)
			if rec.size() != 56 or rec.decode_u32(0) != 0x06064b50:
				_fail("%s: its zip64 directory record is damaged. Make the file again." % file_name)
				return []
			count = rec.decode_u64(32)
			cd_size = rec.decode_u64(40)
			cd_offset = rec.decode_u64(48)
	if cd_offset + cd_size > eocd or count == 0 or cd_size > (64 << 20):
		_fail("%s: its directory is damaged or cut short. Copy it again." % file_name)
		return []
	f.seek(cd_offset)
	var cd := f.get_buffer(cd_size)
	var out: Array = []
	var pos := 0
	for n in count:
		if pos + 46 > cd.size() or cd.decode_u32(pos) != 0x02014b50:
			_fail("%s: its directory is damaged at entry %d. Make the file again." % [file_name, n])
			return []
		var flags := cd.decode_u16(pos + 8)
		var method := cd.decode_u16(pos + 10)
		var csize := cd.decode_u32(pos + 20)
		var usize := cd.decode_u32(pos + 24)
		var name_len := cd.decode_u16(pos + 28)
		var extra_len := cd.decode_u16(pos + 30)
		var comment_len := cd.decode_u16(pos + 32)
		var offset := cd.decode_u32(pos + 42)
		if pos + 46 + name_len + extra_len + comment_len > cd.size():
			_fail("%s: its directory is damaged at entry %d. Make the file again." % [file_name, n])
			return []
		var name := cd.slice(pos + 46, pos + 46 + name_len).get_string_from_utf8()
		var x := pos + 46 + name_len
		var x_end := x + extra_len
		while x + 4 <= x_end:
			var tag := cd.decode_u16(x)
			var tag_size := cd.decode_u16(x + 2)
			if tag == 0x0001: # zip64: the 64-bit values of the fields that hold 0xFFFFFFFF, in this order
				var y := x + 4
				if usize == 0xFFFFFFFF:
					usize = cd.decode_u64(y)
					y += 8
				if csize == 0xFFFFFFFF:
					csize = cd.decode_u64(y)
					y += 8
				if offset == 0xFFFFFFFF:
					offset = cd.decode_u64(y)
			x += 4 + tag_size
		pos = x_end + comment_len
		if name.ends_with("/"):
			continue # a folder entry
		if flags & 1:
			_fail("%s: %s is encrypted. Make the file with tools/ios/make_game_file.py, which does not encrypt." % [file_name, name])
			return []
		if method != 0 and method != 8:
			_fail("%s: %s is compressed with method %d; OpenBFME reads stored and deflate entries only. Make the file with tools/ios/make_game_file.py." % [file_name, name, method])
			return []
		if method == 0 and csize != usize:
			_fail("%s: %s is damaged (stored, but its sizes differ). Make the file again." % [file_name, name])
			return []
		# the data starts after the local header, whose name and extra field lengths can differ from the directory's
		f.seek(offset)
		var local := f.get_buffer(30)
		if local.size() != 30 or local.decode_u32(0) != 0x04034b50:
			_fail("%s: %s is damaged or cut short. Copy the file again." % [file_name, name])
			return []
		var data := offset + 30 + local.decode_u16(26) + local.decode_u16(28)
		if data + csize > cd_offset:
			_fail("%s: %s runs past the end of the data: the copy did not finish. Copy it again." % [file_name, name])
			return []
		out.append({"name": name, "method": method, "size": usize, "csize": csize, "data": data})
	return out


# ---- writing ------------------------------------------------------------------------------------------------------------------------------

# Feeds compressed bytes to zlib and writes what comes out; the new count of bytes written, or -1 with `error` set.
func _feed(gz: StreamPeerGZIP, data: PackedByteArray, ctx: HashingContext, dst: FileAccess, item: Dictionary, written: int) -> int:
	var off := 0
	while off < data.size():
		var r: Array = gz.put_partial_data(data if off == 0 else data.slice(off))
		if r[0] != OK:
			_fail("%s: %s is damaged (its compressed data does not unpack). Make the file again on the Mac and copy it again." % [file_name, item["path"]])
			return -1
		var sent: int = r[1]
		off += sent
		var before := written
		while gz.get_available_bytes() > 0:
			var got: Array = gz.get_partial_data(gz.get_available_bytes())
			if got[0] != OK:
				_fail("%s: %s could not be unpacked (%s). Restart OpenBFME and tap Install again." % [file_name, item["path"], error_string(got[0])])
				return -1
			var out: PackedByteArray = got[1]
			written += out.size()
			if written > item["size"]:
				_fail("%s: %s unpacks to more than its manifest's %d bytes. Make the file again." % [file_name, item["path"], item["size"]])
				return -1
			ctx.update(out)
			if not dst.store_buffer(out):
				_fail(_write_error(item))
				return -1
		if sent == 0 and written == before:
			# zlib took nothing and gave nothing: the stream ended before its data did
			_fail("%s: %s is damaged (data after the end of its compressed stream). Make the file again." % [file_name, item["path"]])
			return -1
	return written


# The file's MD5, read in chunks with a frame now and then; "" with `error` set.
func _hash_file(file: String, tree: SceneTree) -> String:
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		_fail("%s cannot be read (%s). Delete it in the Files app, then tap Install again." % [_shown(file), error_string(FileAccess.get_open_error())])
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var tick := Time.get_ticks_usec()
	var left := f.get_length()
	while left > 0:
		var buf := f.get_buffer(mini(CHUNK, left))
		if buf.is_empty():
			_fail("%s cannot be read. Delete it in the Files app, then tap Install again." % _shown(file))
			return ""
		left -= buf.size()
		ctx.update(buf)
		if Time.get_ticks_usec() - tick > FRAME_BUDGET_USEC:
			await tree.process_frame
			tick = Time.get_ticks_usec()
	return ctx.finish().hex_encode()


# A file that cannot be finished: its .part is removed (the next run writes it again from the start).
func _abandon(dst: FileAccess, part: String, why: String) -> bool:
	if dst != null:
		dst.close()
	DirAccess.remove_absolute(part)
	return false if why == error else _fail(why) # _feed has said it already


func _write_error(item: Dictionary) -> String:
	return "%s could not be written: the %s may be full. Free some space (Settings > General > %s Storage), then tap Install again; the files done so far are kept." % [
		item["path"], _device(), _device()]


# ---- where the files go, and the list of the files done --------------------------------------------------------------------------------------

# "RotWK/apt/x.big" -> <root>/RotWK/apt/x.big, using a game folder already there under another case ("rotwk"), as the discovery would
func _target(p: String) -> String:
	var folder := p.get_slice("/", 0)
	for d in DirAccess.get_directories_at(root):
		if d.to_lower() == folder.to_lower():
			folder = d
			break
	return ProjectSettings.globalize_path(root.path_join(folder).path_join(p.substr(p.find("/") + 1)))


func _safe_path(p: String) -> bool:
	var parts := p.split("/")
	if parts.size() < 2 or not FOLDERS.has(parts[0]) or p.contains("\\") or p.contains(":"):
		return false
	for part in parts:
		if part.is_empty() or part == "." or part == "..":
			return false
	return true


func _size_of(file: String) -> int:
	if not FileAccess.file_exists(file):
		return -1
	var f := FileAccess.open(file, FileAccess.READ)
	return f.get_length() if f != null else -1


func _is_done(item: Dictionary) -> bool:
	return _done.has(item["path"]) and _size_of(item["target"]) == item["size"]


func _read_journal() -> void:
	_done.clear()
	resuming = false
	var f := FileAccess.open(root.path_join(JOURNAL), FileAccess.READ)
	if f == null or f.get_line() != _journal_head:
		return # none, or another file's: every file is checked again
	resuming = true
	var wanted := {}
	for item in files:
		wanted[item["path"]] = "%s\t%d" % [item["md5"], item["size"]]
	while not f.eof_reached():
		var cols := f.get_line().split("\t")
		if cols.size() == 3 and wanted.get(cols[2], "") == cols[0] + "\t" + cols[1]:
			_done[cols[2]] = true


func _start_journal() -> bool:
	var file := root.path_join(JOURNAL)
	var keep := FileAccess.file_exists(file) and resuming
	var f := FileAccess.open(file, FileAccess.READ_WRITE if keep else FileAccess.WRITE)
	if f == null:
		return _fail("OpenBFME cannot write its list of installed files (%s). Check that the %s has space, then tap Install again." % [error_string(FileAccess.get_open_error()), _device()])
	if keep:
		f.seek_end()
	else:
		f.store_line(_journal_head)
	return true


func _journal_add(item: Dictionary) -> bool:
	var f := FileAccess.open(root.path_join(JOURNAL), FileAccess.READ_WRITE)
	if f == null:
		return _fail("OpenBFME cannot write its list of installed files (%s). Check that the %s has space, then tap Install again." % [error_string(FileAccess.get_open_error()), _device()])
	f.seek_end()
	f.store_line("%s\t%d\t%s" % [item["md5"], item["size"], item["path"]])
	_done[item["path"]] = true
	return true


func _shown(p: String) -> String:
	# the container path means nothing to the player: from the game folder on
	var docs := ProjectSettings.globalize_path(root)
	return p.trim_prefix(docs).trim_prefix("/")


func _device() -> String:
	return "iPad" if OS.get_model_name().begins_with("iPad") else "iPhone"


func _fail(why: String) -> bool:
	error = why
	printerr("GAME FILE ", why)
	return false
