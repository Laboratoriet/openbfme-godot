"""tools/release/package_ios.py: the iOS preset it configures and the Info.plist / entitlements it writes (no Xcode, Godot or game files)."""
import plistlib
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_ios  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


def section(text, name):
    return re.search(r'^\[' + re.escape(name) + r'\]\n(.*?)(?=^\[|\Z)', text, re.M | re.S).group(1)


def test_the_real_presets_change_only_ios():
    # the iOS preset is found by its name and platform, wherever it sits; every other preset stays byte for byte
    source = (REPO / "godot/export_presets.cfg").read_text(encoding="utf-8")
    result = package_ios.configure_ios_preset(source, {
        "custom_template/debug": "/tmp/ios.zip", "application/app_store_team_id": "TEAM123",
        "icons/icon_1024x1024": "res://assets/app_icon/ios-1024.png"})
    ios = re.search(r'^\[preset\.(\d+)\]\n\nname="iOS"', source, re.M).group(1)
    for name in re.findall(r'^\[([^\]]+)\]', source, re.M):
        if name == f"preset.{ios}.options":
            options = section(result, name)
            assert 'custom_template/debug="/tmp/ios.zip"' in options
            assert 'application/app_store_team_id="TEAM123"' in options
            assert options.count('icons/icon_1024x1024="res://assets/app_icon/ios-1024.png"') == 1  # added: the preset has none
        else:
            assert section(result, name) == section(source, name)


def test_the_committed_ios_preset_is_neutral():
    # no team, the project's own bundle id, and the toolchain's minimum iOS version
    source = (REPO / "godot/export_presets.cfg").read_text(encoding="utf-8")
    assert package_ios.preset_option(source, "application/app_store_team_id") == ""
    assert package_ios.preset_option(source, "application/bundle_identifier") == "org.openbfme.game"
    assert package_ios.preset_option(source, "application/export_project_only") is True
    toolchain = (REPO / "engine/cmake/toolchains/ios-arm64.cmake").read_text(encoding="utf-8")
    minimum = re.search(r'set\(OPENBFME_IOS_MIN_VERSION (\S+) ', toolchain).group(1)
    assert package_ios.preset_option(source, "application/min_ios_version") == minimum


def test_the_extension_manifest_names_the_xcframework():
    manifest = (REPO / "godot/openbfme.gdextension").read_text(encoding="utf-8")
    assert 'ios.debug = "res://bin/openbfme.ios.xcframework"' in manifest
    assert 'ios.release = "res://bin/openbfme.ios.xcframework"' in manifest


def test_a_reordered_preset_and_an_escaped_path():
    source = ('[preset.19]\nname="iOS"\nplatform="iOS"\n[preset.19.options]\ncustom_template/debug=""\n'
              'application/app_store_team_id=""\n\n[preset.20]\nname="Other"\nplatform="Linux"\n')
    result = package_ios.configure_ios_preset(source, {"custom_template/debug": '/tmp/with "quotes"/ios.zip',
                                                       "application/bundle_identifier": "org.example.game"})
    assert 'custom_template/debug="/tmp/with \\"quotes\\"/ios.zip"' in result
    assert '\napplication/bundle_identifier="org.example.game"\n\n[preset.20]' in result  # added inside the iOS section
    assert result.endswith('[preset.20]\nname="Other"\nplatform="Linux"\n')


def test_a_missing_or_ambiguous_ios_preset_is_an_error():
    with pytest.raises(ValueError, match="exactly one iOS"):
        package_ios.configure_ios_preset('[preset.3]\nname="macOS"\nplatform="macOS"\n', {})
    with pytest.raises(ValueError, match="exactly one iOS"):
        package_ios.configure_ios_preset('[preset.1]\nname="iOS"\nplatform="iOS"\n[preset.2]\nname="iOS"\nplatform="iOS"\n', {})
    with pytest.raises(ValueError, match="no options"):
        package_ios.configure_ios_preset('[preset.1]\nname="iOS"\nplatform="iOS"\n', {})


def test_the_info_plist_keys_keep_the_templates_own(tmp_path):
    info = tmp_path / "OpenBFME-Info.plist"
    template = {"CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "UIRequiresFullScreen": True, "UIFileSharingEnabled": False}
    info.write_bytes(plistlib.dumps(template))
    changed = package_ios.patch_plist(info, package_ios.INFO_PLIST)
    assert sorted(changed) == sorted(package_ios.INFO_PLIST)
    assert plistlib.loads(info.read_bytes()) == {
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "UIRequiresFullScreen": False,
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
        "UIApplicationSupportsIndirectInputEvents": True,
        "LSApplicationQueriesSchemes": ["shareddocuments"],
    }
    first = info.read_bytes()
    assert package_ios.patch_plist(info, package_ios.INFO_PLIST) == []  # a second run changes nothing
    assert info.read_bytes() == first


def test_the_entitlements_ask_for_the_increased_memory_limit(tmp_path):
    entitlements = tmp_path / "OpenBFME.entitlements"
    entitlements.write_bytes(plistlib.dumps({"aps-environment": "development"}))
    assert package_ios.patch_plist(entitlements, package_ios.ENTITLEMENTS) == ["com.apple.developer.kernel.increased-memory-limit"]
    assert plistlib.loads(entitlements.read_bytes()) == {
        "aps-environment": "development", "com.apple.developer.kernel.increased-memory-limit": True}


def test_the_team_placeholder_is_removed(tmp_path):
    project = tmp_path / "project.pbxproj"
    project.write_text(f'DEVELOPMENT_TEAM = {package_ios.TEAM_PLACEHOLDER};\nOTHER = 1;\n', encoding="utf-8")
    package_ios.strip_team_placeholder(project)
    assert project.read_text(encoding="utf-8") == 'DEVELOPMENT_TEAM = "";\nOTHER = 1;\n'
