extends Node
## Lane IOS-5 (OpenBFME, not retail): the device's on-screen keyboard for the menus' text entries.
##
## The entries (the profile name, Create-a-Hero's name, the save name, the lobby and in-game chat, the online login) are SAGE gadgets
## (GadgetTextEntry in the shell's gadget layer), not Godot LineEdits, so Godot never shows the keyboard for them. The shell player reports the
## entry with the keyboard focus (AptMenuPlayer.text_entry_focus / text_entry_state); this shows the keyboard while one has it and hides it when
## the focus goes. Return reaches the entry (its GEM_EDIT_DONE: send, accept) and hides the keyboard; a new focus (another entry, or a tap on
## the same one: GameWindowManager::winFocusSerial) shows it again.
##
## The keyboard's typing comes back as InputEventKey (Godot 4.7 drivers/apple_embedded/godot_keyboard_input_view.mm enterText / deleteText and
## display_server_apple_embedded.mm key()): a press and a release per character, unicode set, keycode the upper-case ASCII character (or NONE
## beyond ASCII), no physical keycode; Backspace and Return as KEY_BACKSPACE / KEY_ENTER without a character. AptMenuPlayer::menuKey takes them
## by keycode and unicode as it does a desktop key (the in-game chat's keys via the HUD's menu_input).
##
## The keyboard view keeps a text of its own and sends only the difference after each change, so it must hold the entry's text: an entry that
## refused a character (its maximum length, RW 0x72260B; its validator, RW 0x75E4DF) or a screen that set the text is given to it again.
##
## Only a focus the player gave by a tap (a click) on the entry shows the keyboard: a screen that focuses an entry by itself (the Skirmish
## lobby's chat, AptSkirmish.cpp:1284) leaves it down until the entry is tapped, so the keyboard does not cover half a screen nobody typed on.
## Prototype choice for the owner's review (REPORT.md).
##
## Active on a mobile build whose display server has a virtual keyboard; desktops never show one and this node does nothing there.

const TAP_FOCUS_MS := 400        # a focus this soon after a press inside the entry is the player's

var _shell: Node                 # the shell's AptMenuPlayer
var _active := false
var _shown := false
var _mirror := ""                # the keyboard view's text as its key events tell it
var _return_pressed := false     # Return went to the entry this frame: the keyboard goes after the event (not inside the view's own callback)
var _press_ms := -100000         # the last left press (a tap: TouchControls makes it a click) and where
var _press_at := Vector2(-1, -1)


func _init(shell: Node) -> void:
	_shell = shell
	name = "VirtualKeyboard"


func _ready() -> void:
	_active = OS.has_feature("mobile") and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)
	set_process(_active)
	if not _active:
		return
	_shell.text_entry_focus.connect(_on_text_entry_focus)
	# the root window's every event before any node's _input (Window._window_input): the keys the menus or the HUD mark handled are counted too
	get_tree().root.window_input.connect(_on_window_input)
	print("IOS-5 virtual keyboard on")


func _on_text_entry_focus(focused: bool, _text: String, _max_length: int) -> void:
	if not focused:
		_hide()
		return
	var state: Dictionary = _shell.text_entry_state()
	if not _tapped(state):
		print("IOS-5 an entry took the focus by itself: the keyboard waits for a tap on it")
		return
	_show(state)


## the focus followed a press inside the entry's rectangle (any press when the entry reports none)
func _tapped(state: Dictionary) -> bool:
	if Time.get_ticks_msec() - _press_ms > TAP_FOCUS_MS:
		return false
	var rect: Rect2 = state.get("rect", Rect2())
	return not rect.has_area() or rect.grow(8.0).has_point(_press_at)


func _on_window_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
		_press_ms = Time.get_ticks_msec()
		_press_at = press.position
	if not _shown:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_return_pressed = true
	elif key.keycode == KEY_BACKSPACE:
		_mirror = _mirror.left(-1)
	elif key.unicode >= 32 and key.unicode != 127:
		_mirror += char(key.unicode)


func _process(_delta: float) -> void:
	if not _shown:
		return
	if _return_pressed:
		_return_pressed = false
		_hide()
		return
	var state: Dictionary = _shell.text_entry_state()
	if state.get("focused", false) and str(state.get("text", "")) != _mirror:
		_show(state) # the entry and the keyboard differ: the entry's text is the keyboard's again


func _show(state: Dictionary) -> void:
	var text := str(state.get("text", ""))
	var type := DisplayServer.KEYBOARD_TYPE_DEFAULT
	if state.get("secret", false):
		type = DisplayServer.KEYBOARD_TYPE_PASSWORD
	elif state.get("numeric", false):
		type = DisplayServer.KEYBOARD_TYPE_NUMBER
	var max_length := int(state.get("max_length", 0))
	# the entry inserts at its end only (GadgetTextEntryInsertCharacter at charPos, Backspace pops the last): the keyboard's cursor is at the end
	DisplayServer.virtual_keyboard_show(text, state.get("rect", Rect2()), type, max_length if max_length > 0 else -1, text.length())
	_mirror = text
	_shown = true
	_return_pressed = false


func _hide() -> void:
	_return_pressed = false
	if not _shown:
		return
	DisplayServer.virtual_keyboard_hide()
	_shown = false
	_mirror = ""
