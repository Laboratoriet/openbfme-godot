extends Node
## Lane IOS-14 (development): the first autoload. A debug build on iOS takes its scripts and scenes from user://OpenBFME-dev.pck when there is
## one (tools/ios/push_mac_pack.sh), so they can be tried without re-signing the app. It loads nothing itself and runs before every other
## autoload, so no script was loaded from the app's own pack before the development pack replaces it (a script another autoload preloads
## would stay the app's: why this is not in release.gd). Never in a release export.

const PACK := "user://OpenBFME-dev.pck"


func _init() -> void:
	if OS.has_feature("ios") and OS.is_debug_build() and FileAccess.file_exists(PACK):
		print("DEVPACK %s: %s" % [PACK, "loaded" if ProjectSettings.load_resource_pack(PACK, true) else "NOT loaded"])
