## Lane IOS-24: "Prepare for iPhone / iPad" on the desktop. Writes OpenBFME-GameData.obfme from the game folders this game already uses, in
## the format the app's importer reads (game_file_import.gd; the format is tools/ios/make_game_file.py's, which stays as the command-line way).
##
## What goes in: every .big archive the game's own mount took (Release.last_mount: RetailFileSystem's report, so every archive is the one the
## game checked by md5 against the 2.01 / 1.06 policies; an excluded or unknown archive never reaches it), plus the loose files the game reads:
## gi.dat, data/, lang/, livingworld.txt and <Language>Splash.jpg (make_game_file.py's classify(), the same rules). Everything else is
## listed as skipped with its reason. The folders are only read.
##
## The file is a standard ZIP (zip64): entries RotWK/<path> and BFME2/<path> in the folders' own case, sorted as make_game_file.py sorts them,
## and manifest.json FIRST in the central directory (what every reader, the importer included, goes by). Its bytes are written last: the
## manifest holds every file's md5 and Adler-32, known only once the file is read, and reading 8.5 GB twice to put them physically first
## buys nothing. Every file is DEFLATE at zlib's default level, as the Python packer's (the movies too: storing them would need a CRC-32
## outside zlib, see _write_entry).
##
## How, without native code: every file is read once in CHUNK pieces (bounded memory). Each piece goes to
##   * HashingContext (md5, native),
##   * StreamPeerGZIP in gzip mode (native deflate; its 10-byte header is dropped and its 8-byte trailer gives the CRC-32 and size ZIP needs,
##     so the rest is exactly ZIP's raw deflate),
##   * the Adler-32 the manifest needs for the importer (Godot has no native Adler-32): computed in GDScript, split over WorkerThreadPool
##     threads and combined (zlib's adler32_combine), while this thread compresses the same piece.
## It runs on a Thread of its own; status() is safe to read from the main thread every frame, cancel() stops it within a piece, and a stop
## for any reason deletes the half-written file (<out>.partial). Nothing is guessed: a problem ends the run with `error` saying what to do.
extends RefCounted

const GameFileImport := preload("res://scripts/release/game_file_import.gd")

const FILE_NAME := "OpenBFME-GameData.obfme"
const CHUNK := 4 << 20                 # bytes read, hashed and compressed per step
const SPACE_MARGIN := 256 << 20        # kept free beyond the file (make_game_file.py's MARGIN)
const ADLER_BASE := 65521
const ADLER_RUN := 5552                # bytes summed before the modulo (zlib's NMAX: the sums stay below 2^32)
const GZIP_HEADER := 10                # zlib's gzip header without a name or an extra field
const STREAM_FROM := 1 << 20           # a file this big or bigger is compressed as a stream; a smaller one in one go (_write_small)
const TOOL := "OpenBFME Prepare for iPhone / iPad (lane IOS-24)"

# (folder in the file, install label of the mount report, patch)
const GAMES := [["RotWK", "rotwk", "2.01"], ["BFME2", "bfme2", "1.06"]]

# make_game_file.py's SKIP_NAMES / SKIP_EXTENSIONS: what stays out, with the reason the skipped list gives
const SKIP_NAMES := {
	"game.dat": "the Windows game program", "game2.dat": "a Windows game program", "patchget.dat": "the Windows patch program",
	"asset.dat": "never read (docs/PLAN.md rule 11)", "00000000.256": "copy-protection data", "filelist.txt": "installer list",
	"launcher.txt": "installer leftover", "langdata.dat": "installer language data", "patch.doc": "patch notes",
	"profile-high.csv": "Windows graphics profile",
}
const SKIP_EXTENSIONS := {
	"exe": "Windows program", "dll": "Windows library", "asi": "Windows sound driver", "m3d": "Windows sound driver",
	"flt": "Windows sound driver", "lcf": "installer leftover", "dif": "patch leftover", "diff": "patch leftover",
	"dbgcmd": "Worldbuilder debug file",
}

# ---- what plan() found (read-only once start() ran) ---------------------------------------------------------------------------------------
var roots := {}            # "RotWK" / "BFME2" -> the folder
var files: Array = []      # [{path: "RotWK/<rel>", disk, size}] in the file's order
var skipped: Array = []    # [{path, size, why}]
var games: Array = []      # the manifest's games
var total := 0             # bytes of every file
var out_path := ""

# ---- the run (written by the worker thread, read through status()) ------------------------------------------------------------------------
var _mutex := Mutex.new()
var _thread: Thread
var _phase := "idle"       # idle, writing, done, failed, cancelled
var _error := ""
var _done := 0             # bytes of the files read so far
var _index := 0            # the file being written (1-based)
var _written := 0          # the finished file's size
var _started := 0          # Time.get_ticks_msec() at start
var _cancel := false

# the Adler-32 of one piece, split over the worker threads (_adler_part)
var _adler_buf: PackedByteArray
var _adler_parts: Array = []
var _adler_seg := 0
var _adler_workers := 2


## Where the file goes by default: the Desktop, else Documents (a system without either: the user data folder).
static func default_output() -> String:
	for dir in [OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)]:
		if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
			return dir.path_join(FILE_NAME)
	return ProjectSettings.globalize_path("user://").path_join(FILE_NAME)


## The folders and archives of the game's own mount (RetailFileSystem.mount_retail*'s report, Release.last_mount). false: `error` says why.
func plan(mount: Dictionary) -> bool:
	_error = ""
	files.clear()
	skipped.clear()
	games.clear()
	total = 0
	if not mount.get("ok", false):
		return _fail("The game folders are not in use yet. Start a game of OpenBFME once, then try again.")
	roots = {"RotWK": str(mount.get("rotwk_install", "")), "BFME2": str(mount.get("bfme2_install", ""))}
	if roots.RotWK.is_empty() or roots.BFME2.is_empty():
		return _fail("OpenBFME is not running on The Rise of the Witch-king and Battle for Middle-earth II folders (BFME1 mode?). Start it without --game=bfme1, then try again.")
	var languages := {}
	for l in mount.get("languages", PackedStringArray()):
		languages[str(l).get_slice(":", 0)] = str(l).get_slice(":", 1)
	for game in GAMES:
		var folder: String = game[0]
		var label: String = game[1]
		var root: String = roots[folder]
		if not DirAccess.dir_exists_absolute(root):
			return _fail("The %s folder is gone (%s). Start OpenBFME again to choose it." % [folder, root])
		# the archives the mount took from this folder, as paths below it (lower case: the mount finds them case-insensitively)
		var archives := {}
		for a in mount.get("mounted", []):
			if str(a.get("install", "")) != label:
				continue
			var rel := _below(str(a.get("disk_path", "")), root)
			if rel.is_empty():
				return _fail("The game took %s from outside its %s folder; OpenBFME cannot pack it. Report this with your log." % [a.get("path", "?"), folder])
			archives[rel.to_lower()] = false
		var count := 0
		var bytes := 0
		for rel in _walk(root):
			var disk := root.path_join(rel)
			var size := _size_of(disk)
			var why := ""
			if rel.get_extension().to_lower() == "big":
				if archives.has(rel.to_lower()):
					archives[rel.to_lower()] = true
				else:
					why = "an archive the game does not use (an excluded or other version's archive)"
			else:
				why = _classify(rel)
			if not why.is_empty():
				skipped.append({"path": folder + "/" + rel, "size": size, "why": why})
				continue
			files.append({"path": folder + "/" + rel, "disk": disk, "size": size})
			count += 1
			bytes += size
		for rel in archives:
			if not archives[rel]:
				return _fail("%s/%s, which the game uses, is not in the folder any more. Start OpenBFME again, then try again." % [folder, rel])
		games.append({"folder": folder, "game": label, "patch": game[2], "language": languages.get(label, ""), "files": count, "bytes": bytes})
		total += bytes
	if files.is_empty():
		return _fail("No game files found in the folders.")
	return true


## Starts writing `out` (absolute) on a thread of its own. false: `error` says why (nothing was written).
func start(out: String) -> bool:
	if _thread != null:
		return _fail("A game file is being prepared already.")
	out_path = out
	for folder in roots:
		if not _below(out, roots[folder]).is_empty():
			return _fail("Write the game file outside the game folders, not into %s." % roots[folder])
	var dir := out.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return _fail("The folder %s does not exist." % dir)
	var free := _space_left(dir)
	if free > 0 and free < total + SPACE_MARGIN: # the compressed size is not known before; the uncompressed size is the bound
		return _fail("Not enough space on the disk of %s: %s free, the file can take up to %s. Free some space, then try again." % [
			dir, GameFileImport.gb(free), GameFileImport.gb(total + SPACE_MARGIN)])
	# Adler-32 sums at about 15 MB/s a thread and deflate runs at 20-50 MB/s: four keep up with it and leave the machine usable
	_adler_workers = clampi(OS.get_processor_count() / 2, 1, 4)
	_set_state("writing", "")
	_done = 0
	_index = 0
	_cancel = false
	_started = Time.get_ticks_msec()
	_thread = Thread.new()
	_thread.start(_work, Thread.PRIORITY_LOW)
	return true


func cancel() -> void:
	_mutex.lock()
	_cancel = true
	_mutex.unlock()


## {phase, done, total, index, count, file, seconds_left (-1: not known yet), error, out, size}: safe to call from any thread.
func status() -> Dictionary:
	_mutex.lock()
	var s := {"phase": _phase, "done": _done, "total": total, "index": _index, "count": files.size(), "error": _error, "out": out_path,
		"size": _written, "file": files[_index - 1].path if _index > 0 and _index <= files.size() else ""}
	var elapsed := (Time.get_ticks_msec() - _started) / 1000.0
	s["seconds_left"] = int((total - _done) * elapsed / _done) if _phase == "writing" and _done > 0 and elapsed > 3.0 else -1
	_mutex.unlock()
	return s


## Waits for the thread (tests, and before the object goes). true when the file was written.
func wait() -> bool:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	return _phase == "done"


func is_running() -> bool:
	return _phase == "writing"


var error: String:
	get:
		return _error


# ---- the thread ----------------------------------------------------------------------------------------------------------------------------

func _work() -> void:
	var partial := out_path + ".partial"
	var ok := _write(partial)
	if ok:
		DirAccess.remove_absolute(out_path) # an older file of the same name: replaced
		var moved := DirAccess.rename_absolute(partial, out_path)
		if moved != OK:
			ok = _fail("The finished file could not be named %s (%s)." % [out_path.get_file(), error_string(moved)])
	if not ok:
		DirAccess.remove_absolute(partial)
		if _cancelled():
			_set_state("cancelled", "")
		else:
			_set_state("failed", _error)
		return
	_written = _size_of(out_path)
	_set_state("done", "")


func _write(partial: String) -> bool:
	var f := FileAccess.open(partial, FileAccess.WRITE)
	if f == null:
		return _fail("%s cannot be written (%s). Choose another folder or free some space." % [partial.get_file(), error_string(FileAccess.get_open_error())])
	var central: Array = [] # [{name, method, crc, csize, size, offset, time}] in the file's order (the manifest is put first at the end)
	var listed: Array = []  # the manifest's files
	for i in files.size():
		var item: Dictionary = files[i]
		_mutex.lock()
		_index = i + 1
		_mutex.unlock()
		var entry := _write_entry(f, item)
		if entry.is_empty():
			return false
		central.append(entry)
		listed.append({"path": item.path, "size": item.size, "md5": entry.md5, "adler32": entry.adler32, "pin": "mount" if item.path.get_extension().to_lower() == "big" else "none"})
	# the manifest: make_game_file.py's keys (and order); its bytes go last, its entry first
	var manifest := {
		"format": GameFileImport.FORMAT, "formatVersion": GameFileImport.FORMAT_VERSION, "tool": TOOL,
		"created": Time.get_datetime_string_from_system(true) + "Z", "method": "deflate", "games": games, "bytes": total, "files": listed,
		"warnings": [],
	}
	var bytes := JSON.stringify(manifest, " ", false).to_utf8_buffer()
	var m := {"name": "manifest.json", "method": 0, "crc": _crc32_of(bytes), "csize": bytes.size(), "size": bytes.size(), "offset": f.get_position(),
		"time": _dos_time(int(Time.get_unix_time_from_system()))}
	_local_header(f, m)
	f.store_buffer(bytes)
	central.push_front(m)
	_central_directory(f, central)
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		return _fail("Writing %s failed (%s): the disk may be full. Free some space, then try again." % [partial.get_file(), error_string(write_error)])
	return true


# One file: its local header, its data (compressed while it is read), then the header's CRC-32 and sizes put in. {} with `error` set.
# Every file is deflated, the movies too (they shrink 0.7 %, at zlib's slowest): ZIP wants a CRC-32 for a stored entry as well, and the
# only native CRC-32 Godot offers is the trailer of a gzip stream, so storing would not save the compression.
func _write_entry(f: FileAccess, item: Dictionary) -> Dictionary:
	var src := FileAccess.open(item.disk, FileAccess.READ)
	if src == null:
		_fail("%s cannot be read (%s)." % [item.disk, error_string(FileAccess.get_open_error())])
		return {}
	var e := {"name": item.path, "method": 8, "crc": 0, "csize": 0, "size": item.size, "offset": f.get_position(),
		"time": _dos_time(FileAccess.get_modified_time(item.disk))}
	_local_header(f, e)
	var data_start := f.get_position()
	if item.size < STREAM_FROM:
		return _write_small(f, src, item, e, data_start)
	var md5 := HashingContext.new()
	md5.start(HashingContext.HASH_MD5)
	var adler := 1
	var gz := StreamPeerGZIP.new()
	if gz.start_compression(false, CHUNK) != OK:
		_fail("OpenBFME could not start compressing %s." % item.path)
		return {}
	var stream := {"tail": PackedByteArray(), "header_left": GZIP_HEADER} # the gzip header is dropped; the last 8 bytes held back
	var left: int = item.size
	while left > 0:
		if _cancelled():
			return {}
		var buf := src.get_buffer(mini(CHUNK, left))
		if buf.is_empty():
			_fail("%s could not be read to its end: it changed or the disk failed. Try again." % item.disk)
			return {}
		left -= buf.size()
		md5.update(buf)
		var group := _adler_start(buf) # the worker threads sum this piece while this thread compresses it
		stream = _deflate(gz, buf, f, stream)
		adler = _adler_finish(group, adler)
		if stream.is_empty():
			return {}
		_mutex.lock()
		_done += buf.size()
		_mutex.unlock()
	if src.get_length() != item.size:
		_fail("%s changed while it was read. Try again." % item.disk)
		return {}
	if gz.finish() != OK:
		_fail("Compressing %s failed." % item.path)
		return {}
	stream = _drain(gz, f, stream)
	if stream.is_empty():
		return {}
	var trailer: PackedByteArray = stream.tail # gzip's: CRC-32, then the size modulo 2^32
	if trailer.size() != 8 or trailer.decode_u32(4) != (item.size & 0xFFFFFFFF):
		_fail("Compressing %s gave a stream OpenBFME does not recognise." % item.path)
		return {}
	e.crc = trailer.decode_u32(0)
	e.md5 = md5.finish().hex_encode()
	e.adler32 = adler
	return _finish_entry(f, e, data_start)


# A file under STREAM_FROM in one go: StreamPeerGZIP.finish() deflates the stream's end into a buffer only as large as the largest piece
# put in (core/io/stream_peer_gzip.cpp), too small for a small file that does not shrink; PackedByteArray.compress makes the same gzip
# stream (zlib, the default level, 32 KB window) in one call. An empty file is zlib's empty raw stream, 03 00, with CRC-32 0.
func _write_small(f: FileAccess, src: FileAccess, item: Dictionary, e: Dictionary, data_start: int) -> Dictionary:
	var buf := src.get_buffer(item.size)
	if buf.size() != item.size or src.get_length() != item.size:
		_fail("%s changed while it was read. Try again." % item.disk)
		return {}
	var raw := PackedByteArray([0x03, 0x00])
	e.crc = 0
	if not buf.is_empty():
		var gz := buf.compress(FileAccess.COMPRESSION_GZIP)
		if gz.size() < GZIP_HEADER + 8 or gz[0] != 0x1F or gz[1] != 0x8B or gz[3] != 0 or gz.decode_u32(gz.size() - 4) != item.size:
			_fail("Compressing %s gave a stream OpenBFME does not recognise." % item.path)
			return {}
		raw = gz.slice(GZIP_HEADER, gz.size() - 8)
		e.crc = gz.decode_u32(gz.size() - 8)
	if not f.store_buffer(raw):
		_fail("Writing failed: the disk may be full. Free some space, then try again.")
		return {}
	var md5 := HashingContext.new()
	md5.start(HashingContext.HASH_MD5)
	if not buf.is_empty():
		md5.update(buf)
	e.md5 = md5.finish().hex_encode()
	e.adler32 = adler32(buf)
	_mutex.lock()
	_done += buf.size()
	_mutex.unlock()
	return _finish_entry(f, e, data_start)


# The entry's compressed size, and its local header's CRC-32 and zip64 sizes put in now that they are known.
func _finish_entry(f: FileAccess, e: Dictionary, data_start: int) -> Dictionary:
	var data_end := f.get_position()
	e.csize = data_end - data_start
	f.seek(e.offset + 14)
	f.store_32(e.crc)
	f.seek(e.offset + 30 + e.name.to_utf8_buffer().size() + 4)
	f.store_64(e.size)
	f.store_64(e.csize)
	f.seek(data_end)
	return e


# Feeds `buf` to the compressor and writes what comes out. `stream`: {tail: the last bytes seen, at most 8, held back as they may be the
# trailer; header_left: the gzip header's bytes still to drop}. The new state, or {} with `error` set.
func _deflate(gz: StreamPeerGZIP, buf: PackedByteArray, f: FileAccess, stream: Dictionary) -> Dictionary:
	var off := 0
	while off < buf.size():
		var r: Array = gz.put_partial_data(buf if off == 0 else buf.slice(off))
		if r[0] != OK:
			_fail("Compressing failed (%s)." % error_string(r[0]))
			return {}
		off += r[1]
		stream = _drain(gz, f, stream)
		if stream.is_empty():
			return {}
	return stream


func _drain(gz: StreamPeerGZIP, f: FileAccess, stream: Dictionary) -> Dictionary:
	var tail: PackedByteArray = stream.tail
	var header_left: int = stream.header_left
	while gz.get_available_bytes() > 0:
		var got: Array = gz.get_partial_data(gz.get_available_bytes())
		if got[0] != OK:
			_fail("Compressing failed (%s)." % error_string(got[0]))
			return {}
		var out: PackedByteArray = got[1]
		if header_left > 0:
			# zlib's plain gzip header (no name, no extra field: Godot sets none): 1F 8B 08 00 <time> <flags> <os>
			if header_left == GZIP_HEADER and out.size() >= 4 and (out[0] != 0x1F or out[1] != 0x8B or out[3] != 0):
				_fail("The compressor wrote a header OpenBFME does not recognise.")
				return {}
			var drop := mini(header_left, out.size())
			header_left -= drop
			out = out.slice(drop)
		var both := tail + out
		var keep := mini(8, both.size())
		if both.size() > keep and not f.store_buffer(both.slice(0, both.size() - keep)):
			_fail("Writing failed: the disk may be full. Free some space, then try again.")
			return {}
		tail = both.slice(both.size() - keep)
	return {"tail": tail, "header_left": header_left}


# ---- Adler-32 (the importer's zlib trailer), in parallel pieces ---------------------------------------------------------------------------

func _adler_start(buf: PackedByteArray) -> int:
	_adler_buf = buf
	var parts := _adler_workers if buf.size() >= (1 << 20) else 1
	_adler_seg = ceili(buf.size() / float(parts))
	_adler_parts.resize(parts)
	return WorkerThreadPool.add_group_task(_adler_part, parts, parts, false, "OpenBFME game file Adler-32")


func _adler_finish(group: int, adler: int) -> int:
	WorkerThreadPool.wait_for_group_task_completion(group)
	for i in _adler_parts.size():
		var from := i * _adler_seg
		var length := mini(_adler_seg, _adler_buf.size() - from)
		if length > 0:
			adler = adler32_combine(adler, _adler_parts[i], length)
	return adler


func _adler_part(i: int) -> void:
	var from := i * _adler_seg
	var to := mini(from + _adler_seg, _adler_buf.size())
	_adler_parts[i] = adler32(_adler_buf.slice(from, to)) if to > from else 1


static func adler32(buf: PackedByteArray, adler := 1) -> int:
	var a := adler & 0xFFFF
	var b := (adler >> 16) & 0xFFFF
	var n := buf.size()
	var i := 0
	while i < n:
		var end := mini(i + ADLER_RUN, n)
		for j in range(i, end):
			a += buf[j]
			b += a
		a %= ADLER_BASE
		b %= ADLER_BASE
		i = end
	return (b << 16) | a


# zlib's adler32_combine: the Adler-32 of A followed by B from theirs and B's length
static func adler32_combine(adler1: int, adler2: int, len2: int) -> int:
	var rem := len2 % ADLER_BASE
	var sum1 := adler1 & 0xFFFF
	var sum2 := (rem * sum1) % ADLER_BASE
	sum1 += (adler2 & 0xFFFF) + ADLER_BASE - 1
	sum2 += ((adler1 >> 16) & 0xFFFF) + ((adler2 >> 16) & 0xFFFF) + ADLER_BASE - rem
	if sum1 >= ADLER_BASE:
		sum1 -= ADLER_BASE
	if sum1 >= ADLER_BASE:
		sum1 -= ADLER_BASE
	if sum2 >= (ADLER_BASE << 1):
		sum2 -= (ADLER_BASE << 1)
	if sum2 >= ADLER_BASE:
		sum2 -= ADLER_BASE
	return sum1 | (sum2 << 16)


# ---- the manifest's CRC-32: zlib's, from a gzip stream's trailer (the compressed bytes are thrown away) -------------------------------------

static func _crc32_of(bytes: PackedByteArray) -> int:
	var gz := StreamPeerGZIP.new()
	gz.start_compression(false, maxi(65536, bytes.size() + 1024))
	gz.put_data(bytes)
	gz.finish()
	var out: PackedByteArray = gz.get_data(gz.get_available_bytes())[1]
	return out.decode_u32(out.size() - 8)


# ---- ZIP records (APPNOTE 4.3.7 local header, 4.3.12 central directory, 4.3.14 / 4.3.15 zip64 end, 4.3.16 end; little-endian) -------------

const ZIP_VERSION := 45      # 4.5: zip64
const ZIP_UTF8 := 0x0800     # bit 11: the names are UTF-8
const ZIP64 := 0xFFFFFFFF


# Every file's local header carries a zip64 extra field with both sizes (as make_game_file.py's force_zip64): its sizes are put in afterwards.
func _local_header(f: FileAccess, e: Dictionary) -> void:
	var name: PackedByteArray = e.name.to_utf8_buffer()
	var zip64: bool = e.name != "manifest.json"
	f.store_32(0x04034b50)
	f.store_16(ZIP_VERSION)
	f.store_16(ZIP_UTF8)
	f.store_16(e.method)
	f.store_16(e.time & 0xFFFF)
	f.store_16(e.time >> 16)
	f.store_32(e.crc)
	f.store_32(ZIP64 if zip64 else e.csize)
	f.store_32(ZIP64 if zip64 else e.size)
	f.store_16(name.size())
	f.store_16(20 if zip64 else 0)
	f.store_buffer(name)
	if zip64:
		f.store_16(0x0001)
		f.store_16(16)
		f.store_64(e.size)
		f.store_64(e.csize)


# The central directory (every entry with a zip64 extra field: size, compressed size, offset) and its zip64 and classic end records.
func _central_directory(f: FileAccess, entries: Array) -> void:
	var start := f.get_position()
	for e in entries:
		var name: PackedByteArray = e.name.to_utf8_buffer()
		f.store_32(0x02014b50)
		f.store_16((3 << 8) | ZIP_VERSION) # made by: Unix (the permissions below)
		f.store_16(ZIP_VERSION)
		f.store_16(ZIP_UTF8)
		f.store_16(e.method)
		f.store_16(e.time & 0xFFFF)
		f.store_16(e.time >> 16)
		f.store_32(e.crc)
		f.store_32(ZIP64)
		f.store_32(ZIP64)
		f.store_16(name.size())
		f.store_16(28)
		f.store_16(0)                 # comment
		f.store_16(0)                 # disk
		f.store_16(0)                 # internal attributes
		f.store_32(0x81A4 << 16)      # a regular file, rw-r--r-- (octal 100644)
		f.store_32(ZIP64)
		f.store_buffer(name)
		f.store_16(0x0001)
		f.store_16(24)
		f.store_64(e.size)
		f.store_64(e.csize)
		f.store_64(e.offset)
	var size := f.get_position() - start
	var zip64_end := f.get_position()
	f.store_32(0x06064b50)
	f.store_64(44)
	f.store_16((3 << 8) | ZIP_VERSION)
	f.store_16(ZIP_VERSION)
	f.store_32(0)
	f.store_32(0)
	f.store_64(entries.size())
	f.store_64(entries.size())
	f.store_64(size)
	f.store_64(start)
	f.store_32(0x07064b50)
	f.store_32(0)
	f.store_64(zip64_end)
	f.store_32(1)
	f.store_32(0x06054b50)
	f.store_16(0)
	f.store_16(0)
	f.store_16(mini(entries.size(), 0xFFFF))
	f.store_16(mini(entries.size(), 0xFFFF))
	f.store_32(mini(size, ZIP64))
	f.store_32(mini(start, ZIP64))
	f.store_16(0)


# MS-DOS time and date (ZIP's), local time as zipfile writes it; 1980 at the earliest
static func _dos_time(unix: int) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_datetime_dict_from_unix_time(maxi(unix + bias, 315532800 + 86400))
	var time: int = (t.hour << 11) | (t.minute << 5) | (t.second / 2)
	var date: int = ((t.year - 1980) << 9) | (t.month << 5) | t.day
	return (date << 16) | time


# ---- the folders -------------------------------------------------------------------------------------------------------------------------

# make_game_file.py's classify() for a file that is not an archive: "" = it goes in, else why it stays out
static func _classify(rel: String) -> String:
	var low := rel.to_lower()
	var name := low.get_file()
	if name.begins_with("."):
		return "hidden file (folder metadata)"
	var top := low.get_slice("/", 0) if low.contains("/") else ""
	if top == "data" or top == "lang":
		return ""
	if top == "mss":
		return "Windows sound driver (mss/)"
	if top.is_empty():
		if name == "gi.dat" or name == "livingworld.txt" or name.ends_with("splash.jpg"):
			return ""
		if SKIP_NAMES.has(name):
			return SKIP_NAMES[name]
		if SKIP_EXTENSIONS.has(name.get_extension()):
			return SKIP_EXTENSIONS[name.get_extension()]
	return "not a file the game reads"


# Every file below `root` as a relative path with "/", sorted as make_game_file.py sorts them (lower case, then as written)
static func _walk(root: String) -> PackedStringArray:
	var out: Array = []
	var dirs := [""]
	while not dirs.is_empty():
		var rel: String = dirs.pop_back()
		var abs := root.path_join(rel) if not rel.is_empty() else root
		for name in DirAccess.get_files_at(abs):
			out.append(rel.path_join(name) if not rel.is_empty() else name)
		for name in DirAccess.get_directories_at(abs):
			dirs.append(rel.path_join(name) if not rel.is_empty() else name)
	out.sort_custom(func(a: String, b: String) -> bool:
		var la := a.to_lower()
		var lb := b.to_lower()
		return la < lb if la != lb else a < b)
	return PackedStringArray(out)


# `path` relative to `root` ("" when it is not below it); compared case-insensitively, as the mount and Windows / macOS file systems do
static func _below(path: String, root: String) -> String:
	var p := path.replace("\\", "/").simplify_path()
	var r := root.replace("\\", "/").simplify_path().trim_suffix("/") + "/"
	if not p.to_lower().begins_with(r.to_lower()):
		return ""
	return p.substr(r.length())


static func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else -1


static func _space_left(dir: String) -> int:
	var d := DirAccess.open(dir)
	return d.get_space_left() if d != null else 0


func _cancelled() -> bool:
	_mutex.lock()
	var c := _cancel
	_mutex.unlock()
	return c


func _set_state(phase: String, why: String) -> void:
	_mutex.lock()
	_phase = phase
	_error = why
	_mutex.unlock()


func _fail(why: String) -> bool:
	_mutex.lock()
	_error = why
	_mutex.unlock()
	printerr("GAME FILE PREPARE ", why)
	return false
