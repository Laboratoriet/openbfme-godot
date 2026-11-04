## Lane IOS-32 (OpenBFME presentation, not retail): the game's logo on black while a phone or tablet starts, instead of a black screen.
##
## The app ships no EA art, so the logo comes from the player's own game files: once they are mounted, save_from() takes RotWK's title logo
## (art\compiledtextures\lo\logowithshadow.tga in Textures2.big: 704 x 491, alpha, "The Lord of the Rings / The Battle for Middle-earth II /
## The Rise of the Witch-king") from the mounted archives, crops it to what it draws, scales it DOWN to SHARE of the screen's shorter edge (never up:
## at most its own size, so it stays sharp) and saves it as user://boot-logo.png. Next to it, user://boot-splash.cfg turns Godot's own boot
## splash on for that image (project.godot application/config/project_settings_override.mobile reads it before the engine draws anything; Godot's
## Main::setup_boot_logo, stretch mode Disabled: the image's pixels centred in the window), so from the second start the logo is up from the first
## frame Godot draws. Without the file (the first start, before the game files are in) nothing is read and the screen stays black.
##
## This layer (Release's child) draws the same image at the same place once the scene tree runs, over a black backdrop, until the main menu is
## shown, then fades out (FADE_OUT; at once with the system's reduced motion). The boot splash cannot fade in (Godot draws it before any script
## runs), so the logo appears at once; a fade-in would have to hold the start for its length, since the start-up work blocks the frames.
## On a phone or tablet, and with --touch (the Mac's mobile check); never headless. Desktops are unchanged.
## --boot-logo-shot=FILE (a proof capture): the window saved to FILE as the start-up ends, the logo on it.
extends CanvasLayer

const PNG := "user://boot-logo.png"
const CFG := "user://boot-splash.cfg"
const SOURCE := "art\\compiledtextures\\lo\\logowithshadow.tga"
const SHARE := 0.65      # the logo's width: at most this share of the screen's shorter edge
const FADE_OUT := 0.25   # s: into the main menu
const ARMED_TIMEOUT := 3.0 # s after the start-up without a main menu (a scripted start straight into a game): the logo goes anyway

var _rect: TextureRect
var _ending := false
var _armed := -1.0


static func enabled() -> bool:
	return (OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")) and DisplayServer.get_name() != "headless"


## the logo of the mounted game files saved for the next starts ("" when it is there or was saved; else why not). The image is made again when the
## screen's shorter edge changed (another device, a folding phone's other screen) or the boot splash's file is missing.
static func save_from(fs: RefCounted) -> String:
	var window := DisplayServer.window_get_size() # a phone's or tablet's screen (full screen); the window with --touch on a Mac
	var short_edge := mini(window.x, window.y)
	var stamp := "; OpenBFME boot logo for a %d px screen edge" % short_edge
	if FileAccess.file_exists(PNG) and FileAccess.file_exists(CFG) and FileAccess.get_file_as_string(CFG).begins_with(stamp):
		return ""
	if not fs.file_exists(SOURCE):
		return "the game files have no " + SOURCE
	var image := Image.new()
	var err := image.load_tga_from_buffer(fs.read_file(SOURCE))
	if err != OK:
		return "%s: %s" % [SOURCE, error_string(err)]
	image = image.get_region(image.get_used_rect())
	var width := mini(image.get_width(), int(short_edge * SHARE))
	if width < image.get_width():
		image.resize(width, maxi(1, roundi(image.get_height() * float(width) / image.get_width())), Image.INTERPOLATE_LANCZOS)
	err = image.save_png(PNG)
	if err != OK:
		return "%s: %s" % [PNG, error_string(err)]
	# Godot's boot splash on a phone or tablet (the .mobile keys project.godot sets): the image's own pixels, centred, on black
	var cfg := FileAccess.open(CFG, FileAccess.WRITE)
	if cfg == null:
		return "%s: %s" % [CFG, error_string(FileAccess.get_open_error())]
	cfg.store_string(stamp + "\n[application]\nboot_splash/show_image.mobile=true\nboot_splash/image.mobile=\"%s\"\nboot_splash/stretch_mode.mobile=0\n" % PNG)
	cfg.close()
	print("BOOT logo saved: %dx%d from %s (screen edge %d px)" % [image.get_width(), image.get_height(), SOURCE.get_file(), short_edge])
	return ""


## the layer when the logo is saved and this is a phone or tablet (null otherwise). A boot splash file left without its image (deleted in the
## Files app) is removed, so the next start does not ask Godot for a missing image.
static func make() -> CanvasLayer:
	if not enabled():
		return null
	if not FileAccess.file_exists(PNG):
		if FileAccess.file_exists(CFG):
			DirAccess.remove_absolute(CFG)
		return null
	var image := Image.load_from_file(PNG)
	if image == null or image.is_empty():
		return null
	var layer: CanvasLayer = load("res://scripts/release/boot_logo.gd").new()
	layer._build(ImageTexture.create_from_image(image))
	return layer


func _build(texture: Texture2D) -> void:
	name = "BootLogo"
	layer = 128 # over every game layer
	process_mode = Node.PROCESS_MODE_ALWAYS
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_rect = TextureRect.new()
	_rect.texture = texture
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_rect)


func _ready() -> void:
	get_viewport().size_changed.connect(_place)
	_place()


## where Godot's boot splash drew it: the image's pixels centred in the window (floored), in this canvas's units
func _place() -> void:
	var window := Vector2(DisplayServer.window_get_size())
	var px := Vector2(_rect.texture.get_size())
	var to_canvas := get_viewport().get_final_transform().affine_inverse()
	_rect.position = to_canvas * ((window - px) / 2.0).floor()
	_rect.size = to_canvas.basis_xform(px)


## the start-up is done: the logo goes when the main menu is shown (end), or ARMED_TIMEOUT later
func arm() -> void:
	_armed = ARMED_TIMEOUT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boot-logo-shot="):
			_shot(a.trim_prefix("--boot-logo-shot=")) # a proof capture: the window as the start-up ends, the logo on it


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	print("BOOT --boot-logo-shot: %s %dx%d %s, logo at %s size %s" % [path.get_file(), image.get_width(), image.get_height(), error_string(image.save_png(path)),
		str(_rect.position), str(_rect.size)])


func _process(delta: float) -> void:
	if _armed > 0.0:
		_armed -= delta
		if _armed <= 0.0:
			end(true)


## the logo goes: faded into what is under it, or at once (an error box, the first-run screen, the start-up movies need the screen now)
func end(fade: bool) -> void:
	if _ending:
		return
	_ending = true
	_armed = -1.0
	if not fade or DisplayServer.accessibility_should_reduce_animation() == 1:
		queue_free()
		return
	# the backdrop and the logo together (a CanvasLayer has no modulate of its own)
	var tween := create_tween().set_parallel().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for c in get_children():
		tween.tween_property(c, "modulate:a", 0.0, FADE_OUT)
	tween.chain().tween_callback(queue_free)
